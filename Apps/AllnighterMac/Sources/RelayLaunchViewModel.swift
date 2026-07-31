import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// R-S08 / ATL-S03 — the Mac GUI's Delivery Loop launch surface. Owns the launch
/// form's state (kickoff, doc, seats, ceilings) and starts a loop via detached
/// `alln loop start --no-wait` — the same survival contract as the CLI, not
/// in-process `complete`.
///
/// Validation is a pure static function (`validate`) so it is unit-testable without SwiftUI
/// or a running app.
@MainActor
@Observable
final class RelayLaunchViewModel {
    var kickoffMessage: String = ""
    var docPath: String = ""
    var pmModelId: String?
    var devModelId: String?
    var maxRounds: Int = 20
    /// Optional `HH:MM` deadline. Empty = no deadline (`--max-rounds` is the only ceiling).
    var untilTime: String = ""
    private(set) var isStarting = false
    /// Set by `start()` when detached spawn refuses (e.g. `RELAY_ALREADY_ACTIVE`). Cleared
    /// at the top of every `start()` attempt.
    private(set) var startRefusalIssue: ValidationIssue?

    let projectId: String
    let projectRoot: String
    let models: [Model]
    let registry: DriverRegistry
    let readyModels: [Model]

    private let stateStore: RelayStateStore
    private let detachedLaunch: (_ cwd: String, _ arguments: [String]) -> RelayDetachedLauncher.Outcome

    init(
        projectId: String,
        projectRoot: String,
        models: [Model],
        registry: DriverRegistry,
        readyModels: [Model],
        initialKickoffMessage: String = "",
        stateStore: RelayStateStore = RelayStateStore(),
        detachedLaunch: @escaping (_ cwd: String, _ arguments: [String]) -> RelayDetachedLauncher.Outcome = {
            RelayDetachedLauncher.launchAndAwaitAcceptance(cwd: $0, arguments: $1)
        }
    ) {
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.models = models
        self.registry = registry
        self.readyModels = readyModels
        self.kickoffMessage = initialKickoffMessage
        self.stateStore = stateStore
        self.detachedLaunch = detachedLaunch

        // LVC-S07 — seat defaults come from the tier SSOT (PM = Frontier, dev =
        // Balanced), never a hardcoded model id: hardcoding is what stops a down
        // CLI from being routed around. Mirrors `LoopCLI.resolveSeats`'s own
        // defaults exactly. Only pre-fills a seat whose tier default is actually
        // ready — the picker below only ever lists ready seats, so silently
        // arming Start on an unready default would be a dead end; an unready
        // default just leaves the seat unset for the user to pick.
        let readyIds = Set(readyModels.map(\.id))
        let defaultSettings = DefaultModelSettingsPersistence().load()
        if let frontierDefault = defaultSettings.tierDefault(.frontier), readyIds.contains(frontierDefault) {
            self.pmModelId = frontierDefault
        }
        if let balancedDefault = defaultSettings.tierDefault(.balanced), readyIds.contains(balancedDefault) {
            self.devModelId = balancedDefault
        }
    }

    // MARK: - Validation (pure, testable)

    struct ValidationIssue: Equatable, Identifiable {
        let id: String
        let message: String
    }

    static func validate(
        kickoffMessage: String,
        docPath: String,
        pmModelId: String?,
        devModelId: String?,
        maxRounds: Int
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if kickoffMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(id: "kickoff", message: "Brief the PM — kickoff is required."))
        }
        let trimmedDoc = docPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDoc.isEmpty {
            issues.append(.init(id: "doc", message: "Pick a spec doc to relay against."))
        }
        if pmModelId == nil {
            issues.append(.init(id: "pm", message: "Pick a PM seat."))
        }
        if devModelId == nil {
            issues.append(.init(id: "dev", message: "Pick a dev seat."))
        }
        if let pmModelId, let devModelId, pmModelId == devModelId {
            issues.append(.init(id: "same-seat", message: "PM and dev seats must be different models."))
        }
        if maxRounds < 1 {
            issues.append(.init(id: "max-rounds", message: "Max rounds must be at least 1."))
        }
        return issues
    }

    var validationIssues: [ValidationIssue] {
        Self.validate(
            kickoffMessage: kickoffMessage,
            docPath: docPath,
            pmModelId: pmModelId,
            devModelId: devModelId,
            maxRounds: maxRounds
        )
    }

    var canStart: Bool { validationIssues.isEmpty && !isStarting }

    // MARK: - Start (detached)

    /// Spawns `alln loop start --no-wait` and waits for durable accept. Returns the loop
    /// id on success, `nil` on refusal. Does not pre-claim — the detached child owns claim.
    @discardableResult
    func start() async -> String? {
        guard canStart, let pmModelId, let devModelId else { return nil }
        startRefusalIssue = nil
        let trimmedDoc = docPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKickoff = kickoffMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .failure(let refusal) = RelayCoordinator.preflightStart(
            projectRoot: projectRoot, docPath: trimmedDoc, stateStore: stateStore
        ) {
            mapPreflightRefusal(refusal)
            return nil
        }

        let arguments = RelayDetachedLauncher.relayStartArguments(
            docPath: trimmedDoc,
            projectId: projectId,
            pmModelId: pmModelId,
            devModelId: devModelId,
            kickoffMessage: trimmedKickoff,
            maxRounds: maxRounds,
            until: RelayGUIRuntime.parseUntil(untilTime)
        )

        isStarting = true
        defer { isStarting = false }

        switch detachedLaunch(projectRoot, arguments) {
        case .accepted(let id, _):
            return id
        case .refused(let code, let message):
            mapDetachedRefusal(code: code, message: message)
            return nil
        case .timedOut:
            startRefusalIssue = ValidationIssue(
                id: "detached-timeout",
                message: "The loop did not accept within the handoff window — try again."
            )
            return nil
        case .unresolvedExecutable:
            startRefusalIssue = ValidationIssue(
                id: "unresolved-binary",
                message: "Could not resolve `alln` on this Mac — install the CLI from Setup."
            )
            return nil
        case .spawnFailed(let detail):
            startRefusalIssue = ValidationIssue(
                id: "spawn-failed",
                message: "Could not start the loop process: \(detail)"
            )
            return nil
        }
    }

    private func mapPreflightRefusal(_ refusal: RelayCoordinator.DispatchRefusal) {
        switch refusal {
        case .alreadyActive(let existingRelayId):
            startRefusalIssue = ValidationIssue(
                id: "already-active",
                message: "A relay is already running for this doc (id \(existingRelayId)) — open it, resume/adopt it, or wait instead of starting a second one."
            )
        case .journalUnavailable:
            startRefusalIssue = ValidationIssue(
                id: "journal-unavailable",
                message: "Could not claim the relay on disk."
            )
        case .relayNotFound, .notResumable, .roundInFlight:
            startRefusalIssue = ValidationIssue(
                id: "start-refused",
                message: "Could not start the loop for this project and doc."
            )
        }
    }

    private func mapDetachedRefusal(code: String, message: String) {
        switch code {
        case "RELAY_ALREADY_ACTIVE":
            startRefusalIssue = ValidationIssue(id: "already-active", message: message)
        default:
            startRefusalIssue = ValidationIssue(id: "start-refused", message: message)
        }
    }
}
