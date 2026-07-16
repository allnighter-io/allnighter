import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// R-S08 — the Mac GUI's PM Relay launch surface (`docs/phases/PM_Relay.md` §6). Owns the
/// launch form's state (doc, seats, ceilings) and starts a relay via
/// `RelayGUIRuntime.makeCoordinator` — construction-identical to `RelayDispatch.makeCoordinator`
/// (CLI), so a GUI-launched relay is the exact same durable object the CLI produces.
///
/// Validation is a pure static function (`validate`) so it is unit-testable without SwiftUI
/// or a running app.
@MainActor
@Observable
final class RelayLaunchViewModel {
    var docPath: String = ""
    var pmWorkerId: String?
    var devWorkerId: String?
    var maxRounds: Int = 20
    /// Optional `HH:MM` deadline. Empty = no deadline (`--max-rounds` is the only ceiling).
    var untilTime: String = ""
    private(set) var isStarting = false

    let projectId: String
    let projectRoot: String
    /// Full model roster (mirrors `RelayGUIRuntime.makeCoordinator`'s `RunService` — the
    /// unfiltered catalog, matching the CLI; NOT `ThreadsViewModel.readyModels`). Seat
    /// pickers still only OFFER ready models (below).
    let models: [Model]
    let registry: DriverRegistry
    /// Only ready models are offered as seats — an unreachable seat can never be picked in
    /// the GUI (the CLI still accepts any known worker id; the GUI is stricter by
    /// construction, same as every other composer picker in the app).
    let readyModels: [Model]

    private let makeCoordinator: (@escaping @Sendable () -> String) -> RelayCoordinator
    /// Builds the `RelayThreadProjector` used for the synchronous pre-seed in `start()`
    /// (below). Defaults to the SAME default-store projector `RelayGUIRuntime.makeCoordinator`
    /// builds internally — in production these are two instances over the identical default
    /// `ThreadStore()`/`RunStore()` paths (the type carries no state of its own), so they're
    /// interchangeable; a test that injects a `makeCoordinator` pointed at temp stores also
    /// injects a matching `makeThreadProjector` so the pre-seed lands in the SAME store the
    /// coordinator will read back.
    private let makeThreadProjector: () -> RelayThreadProjector

    init(
        projectId: String,
        projectRoot: String,
        models: [Model],
        registry: DriverRegistry,
        readyModels: [Model],
        makeCoordinator: @escaping (@escaping @Sendable () -> String) -> RelayCoordinator = RelayGUIRuntime.makeCoordinator,
        makeThreadProjector: @escaping () -> RelayThreadProjector = { RelayThreadProjector() }
    ) {
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.models = models
        self.registry = registry
        self.readyModels = readyModels
        self.makeCoordinator = makeCoordinator
        self.makeThreadProjector = makeThreadProjector
    }

    // MARK: - Validation (pure, testable)

    struct ValidationIssue: Equatable, Identifiable {
        let id: String
        let message: String
    }

    static func validate(
        docPath: String, pmWorkerId: String?, devWorkerId: String?, maxRounds: Int
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let trimmedDoc = docPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDoc.isEmpty {
            issues.append(.init(id: "doc", message: "Pick a spec doc to relay against."))
        }
        if pmWorkerId == nil {
            issues.append(.init(id: "pm", message: "Pick a PM seat."))
        }
        if devWorkerId == nil {
            issues.append(.init(id: "dev", message: "Pick a dev seat."))
        }
        if let pmWorkerId, let devWorkerId, pmWorkerId == devWorkerId {
            issues.append(.init(id: "same-seat", message: "PM and dev seats must be different workers."))
        }
        if maxRounds < 1 {
            issues.append(.init(id: "max-rounds", message: "Max rounds must be at least 1."))
        }
        return issues
    }

    var validationIssues: [ValidationIssue] {
        Self.validate(docPath: docPath, pmWorkerId: pmWorkerId, devWorkerId: devWorkerId, maxRounds: maxRounds)
    }

    var canStart: Bool { validationIssues.isEmpty && !isStarting }

    // MARK: - Start

    /// Seeds the relay's thread synchronously (so the caller can `select()` it immediately —
    /// no race with the background `Task`), then runs the loop in a detached `Task`.
    /// Returns the relay id (== the thread id, `RelayThreadProjector`'s identity rule) on
    /// success, `nil` when validation fails.
    @discardableResult
    func start(onEvent: (@Sendable (RelayCoordinator.RelayEvent) -> Void)? = nil) -> String? {
        guard canStart, let pmWorkerId, let devWorkerId else { return nil }
        let relayId = RelayGUIRuntime.newRelayId()
        let trimmedDoc = docPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = RelayCoordinator.Config(
            projectRoot: projectRoot,
            projectId: projectId,
            docPath: trimmedDoc,
            pmWorkerId: pmWorkerId,
            devWorkerId: devWorkerId,
            maxRounds: maxRounds,
            until: RelayGUIRuntime.parseUntil(untilTime)
        )

        // Pre-seed the thread (idempotent — `RelayCoordinator.run` calls `started` again
        // for the SAME id, a no-op besides re-affirming the project bind) so the caller can
        // navigate to it before the background Task has even been scheduled.
        let seedState = RelayState(
            id: relayId, projectRoot: projectRoot, docPath: trimmedDoc,
            pmWorkerId: pmWorkerId, devWorkerId: devWorkerId, status: .running,
            createdAt: Date()
        )
        makeThreadProjector().started(state: seedState, projectId: projectId)

        isStarting = true
        let coordinator = makeCoordinator { relayId }
        Task { @MainActor [weak self] in
            _ = await coordinator.run(config: config) { event in
                Task { @MainActor in onEvent?(event) }
            }
            self?.isStarting = false
        }
        return relayId
    }
}
