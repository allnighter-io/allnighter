import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP `pair_relay` — PM Relay control plane, action-dispatched (docs/phases/
/// PM_Relay.md §6 R-S06). One tool, not three: the CLI keeps three separate
/// subcommands (`pair relay` / `relay-status` / `relay-resume` — distinct flag
/// shapes read better as separate verbs at a terminal), but the MCP tool-count
/// cap (§3 of the tool-upgrade doc, `MCPWireConformanceTests.testToolCountRatchet`,
/// ≤32) doesn't have three tools' worth of headroom (30 baseline + 3 = 33, over
/// cap). `action: start | status | resume` folds status/resume into `pair_relay`
/// the same way `teams_edit`/`skills_edit`/`pending_update` already dispatch
/// mutations — costs one new slot (30 → 31), not three.
/// Same engine path, same JSON as `alln pair relay*` (`RelayDispatch`, `RelayJSON`).
enum MCPRelayHandlers {
    enum Outcome: Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    /// The single MCP entry point (`pair_relay`) — dispatches on `action`.
    static func pairRelay(
        runtime: ToolRuntime, args: [String: Any],
        projectStore: ProjectStore = ProjectStore(), stateStore: RelayStateStore = RelayStateStore()
    ) async -> Outcome {
        guard let action = args["action"] as? String, !action.isEmpty else {
            return usageError("action required (start | status | resume)")
        }
        switch action {
        case "start":
            return await relay(runtime: runtime, args: args, projectStore: projectStore)
        case "status":
            return status(args: args, stateStore: stateStore)
        case "resume":
            return await resume(runtime: runtime, args: args, stateStore: stateStore, projectStore: projectStore)
        default:
            return usageError("unknown action: \(action) (use start | status | resume)")
        }
    }

    static func relay(runtime: ToolRuntime, args: [String: Any], projectStore: ProjectStore = ProjectStore()) async -> Outcome {
        guard let docPath = args["doc"] as? String, !docPath.isEmpty else {
            return usageError("doc required")
        }
        guard let projectToken = args["project"] as? String, !projectToken.isEmpty else {
            return usageError("project required")
        }
        guard let pmWorkerId = args["pmWorker"] as? String, !pmWorkerId.isEmpty else {
            return usageError("pmWorker required")
        }
        guard let devWorkerId = args["devWorker"] as? String, !devWorkerId.isEmpty else {
            return usageError("devWorker required")
        }
        guard let project = AllnighterCLI.resolveProject(projectToken, store: projectStore) else {
            return .toolError(ErrorEnvelope(
                code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)",
                requiresManual: true, retryable: false))
        }
        guard let maxRounds = maxRoundsArg(args["maxRounds"]) else {
            return usageError("maxRounds must be a positive integer")
        }

        let config = RelayCoordinator.Config(
            projectRoot: project.normalizedRootPath,
            projectId: project.id,
            docPath: docPath,
            pmWorkerId: pmWorkerId,
            devWorkerId: devWorkerId,
            maxRounds: maxRounds,
            until: RelayDispatch.parseUntil(args["until"] as? String),
            pmMayMutate: !((args["pmReadOnly"] as? Bool) ?? false)
        )
        // `--pm-read-only` fail-closed pre-flight (PM_Relay.md §4.2) — same check, same
        // message, as `RelayCLI.runRelay` (agent-first: MCP never richer/different than
        // the CLI). `RunService`'s dispatch-time `RelayReadOnlyEnforcer.enforce` call is
        // the mechanical backstop this can never replace.
        if !config.pmMayMutate,
           let violation = RelayReadOnlyEnforcer.capabilityViolation(
               pmWorkerId: pmWorkerId, models: runtime.models, registry: runtime.registry) {
            return .toolError(ErrorEnvelope(
                code: "RELAY_PM_READONLY_UNSUPPORTED", message: violation,
                requiresManual: true, retryable: false))
        }
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let state = await coordinator.run(config: config)
        return respond(state)
    }

    /// Reconciles via `RelayCoordinator.reconcileOrphan` (not a raw `RelayStateStore.load`)
    /// so a `.running` relay whose owner process died mid-round reconciles to `.stopped`
    /// here — works-test hazard #1: "on load/list/status/start".
    static func status(
        args: [String: Any],
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector()
    ) -> Outcome {
        guard let relayId = args["relay"] as? String, !relayId.isEmpty else {
            return usageError("relay required")
        }
        guard let loaded = stateStore.load(id: relayId) else {
            return relayNotFound(relayId)
        }
        let state = RelayCoordinator.reconcileOrphan(
            loaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init)
        return respond(state)
    }

    static func resume(
        runtime: ToolRuntime, args: [String: Any],
        stateStore: RelayStateStore = RelayStateStore(), projectStore: ProjectStore = ProjectStore()
    ) async -> Outcome {
        guard let relayId = args["relay"] as? String, !relayId.isEmpty else {
            return usageError("relay required")
        }
        guard let answer = (args["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else {
            return usageError("answer required")
        }
        guard let priorState = stateStore.load(id: relayId) else {
            return relayNotFound(relayId)
        }
        // `priorState` is the raw persisted read; `RelayCoordinator.resume` (which this
        // feeds) durably reconciles a dead-owner `.running` relay to `.stopped` — this
        // pre-check only needs to know THAT it would be eligible, via the same owner.pid
        // liveness signal (works-test hazard #1: "escalated-only was too narrow").
        let orphaned = priorState.status == .running && stateStore.isOwnerDead(id: relayId)
        guard priorState.isResumable || orphaned else {
            return .toolError(ErrorEnvelope(
                code: "RELAY_INVALID_STATE",
                message: "relay \(relayId) is \(priorState.status.rawValue), not resumable — only an escalated relay, or one reconciled after its owner process died, can be resumed",
                requiresManual: true, retryable: false))
        }
        guard let maxRounds = maxRoundsArg(args["maxRounds"]) else {
            return usageError("maxRounds must be a positive integer")
        }

        // The coordinator itself re-derives projectRoot/docPath/pmWorkerId/devWorkerId
        // from the persisted state on resume (RelayCoordinator.resume) — resolving the
        // project here too only recovers a real `projectId` for the RunRequest.
        let projectId = AllnighterCLI.resolveProject(priorState.projectRoot, store: projectStore)?.id
        let config = RelayCoordinator.Config(
            projectRoot: priorState.projectRoot,
            projectId: projectId,
            docPath: priorState.docPath,
            pmWorkerId: priorState.pmWorkerId,
            devWorkerId: priorState.devWorkerId,
            maxRounds: maxRounds,
            until: RelayDispatch.parseUntil(args["until"] as? String)
        )
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        guard let state = await coordinator.resume(relayId: relayId, founderAnswer: answer, config: config) else {
            return relayNotFound(relayId)
        }
        return respond(state)
    }

    // MARK: - Helpers

    private static func respond(_ state: RelayState) -> Outcome {
        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let encoded = AllnighterCLI.jsonString(json)
        return .success(encoded, summary: RelayDispatch.humanRelaySummary(json))
    }

    private static func usageError(_ message: String) -> Outcome {
        .toolError(ErrorEnvelope(code: "CLI_USAGE_ERROR", message: message, requiresManual: true, retryable: false))
    }

    private static func relayNotFound(_ relayId: String) -> Outcome {
        .toolError(ErrorEnvelope(code: "RELAY_NOT_FOUND", message: "relay not found: \(relayId)", requiresManual: true, retryable: false))
    }

    /// Nil `maxRounds` defaults to 20; a present-but-invalid value is a usage error
    /// rather than a silent fallback (agent-first: never mask a bad argument).
    private static func maxRoundsArg(_ raw: Any?) -> Int? {
        guard let raw else { return 20 }
        if let n = raw as? Int { return n > 0 ? n : nil }
        if let s = raw as? String { return Int(s).flatMap { $0 > 0 ? $0 : nil } }
        return nil
    }
}
