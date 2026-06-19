import Foundation

/// Composite mutating-dispatch gate for PRJ-S11 and agent surfaces. Core owns the
/// policy; CLI/MCP/Mac render the structured result. Source gate runs before dirty
/// state and per-Project worker readiness (`Execution_Team_Source_Gate.md` §7).
public enum ProjectMutatingDispatchGate: Equatable, Sendable {
    case allowed(scope: ProjectExecutionScope, dirtyWarnings: [String])
    case blockedNotDispatchMode
    case blockedNoProjectRoot
    case blockedSourceGate(SourceGateBlocker)
    case blockedDirty(ProjectDispatchGate)
    case blockedWorkerNotReady(sourceId: String)
    case blockedBaseHeadChanged(observed: String, expected: String?)

    public var allowsDispatch: Bool {
        if case .allowed = self { return true }
        return false
    }

    public var primaryErrorCode: String {
        switch self {
        case .allowed: return ""
        case .blockedNotDispatchMode: return "PROPOSAL_NOT_APPROVED"
        case .blockedNoProjectRoot: return "PROJECT_ROOT_UNAVAILABLE"
        case .blockedSourceGate(let b): return b.code
        case .blockedDirty(let g):
            switch g {
            case .blockedNoProjectRoot: return "PROJECT_ROOT_UNAVAILABLE"
            case .blockedDirtyScopeOverlap: return "DIRTY_SCOPE_CONFLICT"
            case .needsDirtyAcknowledgement: return "DIRTY_SCOPE_CONFLICT"
            case .allowed: return "DISPATCH_GATE_FAILED"
            }
        case .blockedWorkerNotReady: return "WORKER_NOT_READY_IN_PROJECT"
        case .blockedBaseHeadChanged: return "BASE_HEAD_CHANGED"
        }
    }

    public var message: String {
        switch self {
        case .allowed: return ""
        case .blockedNotDispatchMode:
            return "Dispatch requires a work order in dispatch mode after approval."
        case .blockedNoProjectRoot:
            return "Project root is unavailable; mutating dispatch is blocked."
        case .blockedSourceGate(let b):
            return b.message
        case .blockedDirty(let g):
            switch g {
            case .blockedNoProjectRoot:
                return "Project root is unavailable; mutating dispatch is blocked."
            case .blockedDirtyScopeOverlap(let files):
                return "Dirty files overlap the proposal scope: \(files.joined(separator: ", ")). Acknowledge or clean them first."
            case .needsDirtyAcknowledgement(let files):
                return "Dirty tree must be acknowledged before dispatch: \(files.joined(separator: ", "))."
            case .allowed:
                return "Dispatch gate failed."
            }
        case .blockedWorkerNotReady(let sourceId):
            return "Worker \(sourceId) is not ready in this Project root."
        case .blockedBaseHeadChanged(let observed, let expected):
            return "Base head changed from \(expected ?? "unknown") to \(observed). Revalidate before dispatch."
        }
    }

    public var repairOptions: [SourceGateRepairOption] {
        if case .blockedSourceGate(let b) = self { return b.repairOptions }
        return []
    }
}

public enum ProjectMutatingDispatchEvaluator {

    public static func evaluate(
        workOrder: WorkOrder,
        project: Project,
        proposal: ProjectProposal?,
        observedRootState: RootState,
        dirtyFiles: [String],
        dirtyAcknowledged: Bool,
        workerReadiness: [ProjectWorkerReadiness],
        readyModels: [Model],
        currentGitHead: String? = nil,
        teams: [TeamPreset] = TeamCatalog.all,
        registry: DriverRegistry? = nil
    ) -> ProjectMutatingDispatchGate {
        guard workOrder.mode == .dispatch else {
            return .blockedNotDispatchMode
        }

        let scope = ProjectExecutionScope(project: project, observedRootState: observedRootState)
        guard scope.isMutatingDispatchAllowed else {
            return .blockedNoProjectRoot
        }

        if let expected = workOrder.baseGitHead, let current = currentGitHead, !expected.isEmpty, expected != current {
            return .blockedBaseHeadChanged(observed: current, expected: expected)
        }

        if let teamId = workOrder.executionTeamId,
           let team = teams.first(where: { $0.id == teamId }) {
            let effort = proposal?.suggestedEffort ?? team.defaultEffort
            let lane: WorkLane = {
                switch workOrder.lane {
                case .code: return .code
                case .design: return .design
                case .copy: return .copy
                case .none: return team.lane
                }
            }()
            let resolved = TeamResolver.resolve(
                team: team, requestLane: lane, requestEffort: effort, readyModels: readyModels)
            let gate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels, registry: registry)
            if let blocker = gate.sourceGateBlocker {
                return .blockedSourceGate(blocker)
            }
        }

        let likely = proposal?.likelyFilesOrAreas ?? []
        let dirtyGate = ProjectDispatchGateEvaluator.evaluate(
            project: project,
            observedRootState: observedRootState,
            likelyFilesOrAreas: likely,
            dirtyFiles: dirtyFiles,
            dirtyAcknowledged: dirtyAcknowledged
        )
        guard dirtyGate.allowsDispatch else {
            return .blockedDirty(dirtyGate)
        }

        if let sourceId = workOrder.resolvedTargetSourceId {
            let ready = workerReadiness.first { $0.sourceId == sourceId && $0.projectId == project.id }
            if ready?.status.isDispatchable != true {
                return .blockedWorkerNotReady(sourceId: sourceId)
            }
        }

        let warnings: [String]
        if case .allowed(let w) = dirtyGate { warnings = w } else { warnings = [] }
        return .allowed(scope: scope, dirtyWarnings: warnings)
    }
}

public extension WorkOrder {
    /// The single CLI driver dispatch will invoke — explicit `targetSourceId` wins,
    /// then `targetAgent` (historically a source slug like `codex`).
    var resolvedTargetSourceId: String? {
        if let targetSourceId, !targetSourceId.isEmpty { return targetSourceId }
        if let targetAgent, !targetAgent.isEmpty { return targetAgent }
        return nil
    }
}

/// Pending mutating paths share the same source law before spawn.
public enum PendingMutatingSourceGate {
    /// Returns a blocker when a Pending item would start a mutating team run across
    /// multiple CLI sources. `nil` when the gate does not apply.
    public static func evaluate(
        item: PendingItem,
        readyModels: [Model],
        teams: [TeamPreset] = TeamCatalog.all,
        registry: DriverRegistry? = nil
    ) -> SourceGateBlocker? {
        let mutatingKinds: Set<PendingItemKind> = [.teamRun, .dispatch, .workOrder]
        guard mutatingKinds.contains(item.kind) else { return nil }
        if item.kind == .workOrder, item.execution?.intent != .execute { return nil }

        if let teamId = item.target.teamPresetId,
           let team = teams.first(where: { $0.id == teamId }) {
            let lane = team.lane
            let resolved = TeamResolver.resolve(
                team: team, requestLane: lane, requestEffort: team.defaultEffort, readyModels: readyModels)
            return ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels, registry: registry)
                .sourceGateBlocker
        }

        // Multiple explicit worker targets must not cross sources on execute intent.
        guard item.execution?.intent == .execute else { return nil }
        let workerIds = item.target.preferredWorkerIds + item.target.workerIds + item.target.requiredWorkerIds
        let byModel = Dictionary(readyModels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sources = Array(Set(workerIds.compactMap { byModel[$0]?.driverId })).sorted()
        guard sources.count > 1 else { return nil }
        let names = sources.map { TeamSourceFacts.sourceDisplayName(sourceId: $0, registry: registry) }
        return SourceGateBlocker(
            code: ExecutionTeamSourceGate.mixedSourcesCode,
            message: "Execution teams run on one CLI. This pending item targets \(ExecutionTeamSourceGate.formattedSourceList(names)). Pick one execution source.",
            resolvedSourceIds: sources,
            resolvedSourceNames: names,
            repairOptions: ExecutionTeamSourceGate.defaultRepairOptions(sourceIds: sources, sourceNames: names)
        )
    }
}
