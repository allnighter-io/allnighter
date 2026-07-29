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
    /// RSC-S02: set by `start()` when `RelayCoordinator.preflightStart` refuses a
    /// duplicate live relay on this project root + doc. Deliberately NOT folded into
    /// `validationIssues`/`canStart` — those gate the Start button on pure form
    /// completeness; a duplicate-relay refusal is a dynamic, disk-backed fact that can
    /// change the moment the existing relay settles, so blocking the button on it would
    /// dead-end the form until the user edits an unrelated field. Cleared at the top of
    /// every `start()` attempt so retrying re-checks fresh.
    private(set) var startRefusalIssue: ValidationIssue?

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
    /// RSC-S02: the store `preflightStart` scans. Defaults to production
    /// (`RelayStateStore()`), the SAME default root `RelayGUIRuntime.makeCoordinator`'s
    /// internal `RelayCoordinator` uses — a test-injected store must point at the SAME
    /// root the injected `makeCoordinator` factory's coordinator was built against, or
    /// the preflight would scan a different directory than the one `run()` persists to.
    private let stateStore: RelayStateStore
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
        makeThreadProjector: @escaping () -> RelayThreadProjector = { RelayThreadProjector() },
        stateStore: RelayStateStore = RelayStateStore()
    ) {
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.models = models
        self.registry = registry
        self.readyModels = readyModels
        self.makeCoordinator = makeCoordinator
        self.makeThreadProjector = makeThreadProjector
        self.stateStore = stateStore
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
            issues.append(.init(id: "same-seat", message: "PM and dev seats must be different models."))
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

    /// Seeds the relay thread only after a durable claim succeeds, then runs the loop
    /// in a background Task. Returns the relay id on claim success, `nil` on refusal.
    @discardableResult
    func start(onEvent: (@Sendable (RelayCoordinator.RelayEvent) -> Void)? = nil) -> String? {
        guard canStart, let pmWorkerId, let devWorkerId else { return nil }
        startRefusalIssue = nil
        let trimmedDoc = docPath.trimmingCharacters(in: .whitespacesAndNewlines)

        let relayId = RelayGUIRuntime.newRelayId()
        let config = RelayCoordinator.Config(
            projectRoot: projectRoot,
            projectId: projectId,
            docPath: trimmedDoc,
            pmWorkerId: pmWorkerId,
            devWorkerId: devWorkerId,
            maxRounds: maxRounds,
            until: RelayGUIRuntime.parseUntil(untilTime)
        )

        let coordinator = makeCoordinator { relayId }
        // RSC-HF: claim under the real start lock before seeding/navigating — never
        // return an id from a lock-free preflight while ignoring the guarded result.
        switch coordinator.claimStart(config: config, id: relayId) {
        case .failure(let refusal):
            if case .alreadyActive(let existingRelayId) = refusal {
                startRefusalIssue = ValidationIssue(
                    id: "already-active",
                    message: "A relay is already running for this doc (id \(existingRelayId)) — open it, resume/adopt it, or wait instead of starting a second one."
                )
            } else if case .journalUnavailable = refusal {
                startRefusalIssue = ValidationIssue(
                    id: "journal-unavailable",
                    message: "Could not claim the relay on disk."
                )
            }
            return nil
        case .success(let claimed):
            makeThreadProjector().started(state: claimed, projectId: projectId)
            isStarting = true
            Task { @MainActor [weak self] in
                await coordinator.complete(claimed, config: config) { event in
                    Task { @MainActor in onEvent?(event) }
                }
                self?.isStarting = false
            }
            return claimed.id
        }
    }
}
