import Foundation

/// Agent-first bootstrap + preflight projections (Agent_First_MCP_And_Messaging_
/// Workflows.md — historical name; the CLI is now the only agent surface, see
/// MCP_Retirement.md). These are the make-or-break entry points for messaging agents
/// (OpenClaw/Hermes): discover readiness without guessing, and preflight a team
/// without spending provider quota. Pure Core truth; the CLI adds transport facts
/// (binaryVersion, tool list, traceId).

/// A team an agent can start right now (passes resolution against the ready bench).
public struct ReadyTeam: Codable, Sendable, Equatable {
    public var lane: String
    public var team: String
    public var displayName: String
    public init(lane: String, team: String, displayName: String) {
        self.lane = lane; self.team = team; self.displayName = displayName
    }
}

/// What the agent should do next. Same shape as `AgentSurfaceNextAction`
/// (kind + label + runnable `alln …` command) — foundation-first, no tool-id grammar.
public struct AgentNextAction: Codable, Sendable, Equatable {
    /// startTeamRun | runDoctor | installOrAuthSource | retryLater | performHumanAction
    public var kind: String
    public var label: String
    public var command: String
    public init(kind: String, label: String, command: String) {
        self.kind = kind; self.label = label; self.command = command
    }

    public static func startTeamRun(teamId: String? = nil) -> AgentNextAction {
        let team = teamId ?? "<team-id>"
        return AgentNextAction(
            kind: "startTeamRun",
            label: "Start team run",
            command: "alln team start --team \(team) --json \"<message>\"")
    }

    public static func retryLater(teamId: String? = nil) -> AgentNextAction {
        let team = teamId ?? "<team-id>"
        return AgentNextAction(
            kind: "retryLater",
            label: "Retry team start when capacity frees",
            command: "alln team start --team \(team) --json \"<message>\"")
    }

    public static let runDoctor = AgentNextAction(
        kind: "runDoctor", label: "Check setup and sources", command: "alln doctor --json")

    public static let installOrAuthSource = AgentNextAction(
        kind: "installOrAuthSource", label: "Install or authenticate a source", command: "alln doctor --json")

    public static let performHumanAction = AgentNextAction(
        kind: "performHumanAction", label: "Fix the named blocker, then re-preflight", command: "alln doctor --json")
}

/// The readiness verdict agents branch on — never inferred from prose or individual
/// checks. `canStartTeamRun` is the single field to test.
public enum AgentReadiness {
    public struct Verdict: Codable, Sendable, Equatable {
        public var canStartTeamRun: Bool
        public var readyTeams: [ReadyTeam]
        public var blockedReason: String?
        public var nextAction: AgentNextAction
        public init(canStartTeamRun: Bool, readyTeams: [ReadyTeam], blockedReason: String?, nextAction: AgentNextAction) {
            self.canStartTeamRun = canStartTeamRun; self.readyTeams = readyTeams
            self.blockedReason = blockedReason; self.nextAction = nextAction
        }
    }

    /// A team is ready when it resolves to a runnable run at its default effort
    /// against the ready bench. `readyTeams` lists only startable teams (one-model
    /// self-fusion still counts as ready).
    public static func evaluate(
        teams: [TeamPreset],
        readyModels: [Model],
        capabilities: (String) -> ModelCapabilities = ModelCatalog.capabilities,
        skill: (String) -> Skill? = SkillCatalog.skill
    ) -> Verdict {
        let ready = teams.compactMap { team -> ReadyTeam? in
            let resolved = TeamResolver.resolve(
                team: team, requestLane: team.lane, requestEffort: team.defaultEffort,
                readyModels: readyModels, capabilities: capabilities, skill: skill
            )
            guard resolved.isRunnable else { return nil }
            let gate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels)
            guard gate.sourceGateStatus != .blocked else { return nil }
            return ReadyTeam(lane: team.lane.rawValue, team: team.id, displayName: team.displayName)
        }
        if !ready.isEmpty {
            return Verdict(canStartTeamRun: true, readyTeams: ready, blockedReason: nil,
                           nextAction: .startTeamRun())
        }
        if readyModels.isEmpty {
            return Verdict(canStartTeamRun: false, readyTeams: [],
                           blockedReason: "No ready model on the bench. Connect or authenticate at least one CLI.",
                           nextAction: .installOrAuthSource)
        }
        return Verdict(canStartTeamRun: false, readyTeams: [],
                       blockedReason: "No team resolves with the current bench. Run doctor for the blocking check.",
                       nextAction: .runDoctor)
    }
}

/// Preflight a specific team without creating a run or spending quota. Surfaces
/// resolved/blocked workers, self-fusion, and warnings so an agent can show
/// blockers in chat before the user expects a run to have started.
public enum TeamPreflight {
    public struct WorkerRef: Codable, Sendable, Equatable {
        public var workerId: String
        public var skillId: String?
        public var skillName: String?
        public var modelId: String
        public var sourceId: String?
        public var sourceDisplayName: String?
        public var purpose: String
        public init(workerId: String, skillId: String?, skillName: String?, modelId: String,
                    sourceId: String? = nil, sourceDisplayName: String? = nil, purpose: String) {
            self.workerId = workerId; self.skillId = skillId; self.skillName = skillName
            self.modelId = modelId; self.sourceId = sourceId; self.sourceDisplayName = sourceDisplayName
            self.purpose = purpose
        }
    }
    public struct BlockedRef: Codable, Sendable, Equatable {
        public var skillId: String
        public var skillName: String
        public var required: Bool
        public var reason: String
        public init(skillId: String, skillName: String, required: Bool, reason: String) {
            self.skillId = skillId; self.skillName = skillName; self.required = required; self.reason = reason
        }
    }
    public struct SelfFusion: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var reason: String?
        public init(enabled: Bool, reason: String?) { self.enabled = enabled; self.reason = reason }
    }
    public struct Result: Codable, Sendable, Equatable {
        public var canStart: Bool
        public var lane: String?
        public var teamPresetId: String?
        public var teamDisplayName: String?
        public var effort: String?
        public var outputKind: String?
        public var readyWorkers: [WorkerRef]
        public var blockedWorkers: [BlockedRef]
        public var selfFusion: SelfFusion
        public var warnings: [String]
        public var blockedReason: String?
        public var nextAction: AgentNextAction
        public var executionSourcePolicy: String?
        public var resolvedSourceIds: [String]
        public var executionSourceId: String?
        public var sourceGateStatus: String?
        public var sourceGateBlocker: SourceGateBlocker?
        public var repairOptions: [SourceGateRepairOption]

        public init(
            canStart: Bool, lane: String?, teamPresetId: String?, teamDisplayName: String?,
            effort: String?, outputKind: String?, readyWorkers: [WorkerRef], blockedWorkers: [BlockedRef],
            selfFusion: SelfFusion, warnings: [String], blockedReason: String?, nextAction: AgentNextAction,
            executionSourcePolicy: String? = nil, resolvedSourceIds: [String] = [],
            executionSourceId: String? = nil, sourceGateStatus: String? = nil,
            sourceGateBlocker: SourceGateBlocker? = nil, repairOptions: [SourceGateRepairOption] = []
        ) {
            self.canStart = canStart; self.lane = lane; self.teamPresetId = teamPresetId
            self.teamDisplayName = teamDisplayName; self.effort = effort; self.outputKind = outputKind
            self.readyWorkers = readyWorkers; self.blockedWorkers = blockedWorkers
            self.selfFusion = selfFusion; self.warnings = warnings; self.blockedReason = blockedReason
            self.nextAction = nextAction; self.executionSourcePolicy = executionSourcePolicy
            self.resolvedSourceIds = resolvedSourceIds; self.executionSourceId = executionSourceId
            self.sourceGateStatus = sourceGateStatus; self.sourceGateBlocker = sourceGateBlocker
            self.repairOptions = repairOptions
        }
    }

    /// Resolve a request the same way `team_start` would, but never run it.
    public static func preflight(
        teams: [TeamPreset],
        lane: WorkLane?,
        teamId: String?,
        type: String?,
        effort: EffortLevel?,
        readyModels: [Model],
        capabilities: (String) -> ModelCapabilities = ModelCatalog.capabilities,
        skill: (String) -> Skill? = SkillCatalog.skill
    ) -> Result {
        switch TeamRequestResolver.resolve(teams: teams, lane: lane, teamId: teamId, type: type, effort: effort) {
        case .failure(let failure):
            let teamDiscovery = AgentNextAction(
                kind: "discover",
                label: "List teams",
                command: ErrorDiscovery.discoveryCommand(forErrorCode: "TEAM_NOT_FOUND", lane: lane?.rawValue)
                    ?? "alln teams --json")
            let next: AgentNextAction = {
                if failure.code == "CLI_USAGE_ERROR" { return .performHumanAction }
                if failure.code == "TEAM_NOT_FOUND" || failure.description.lowercased().contains("unknown team") {
                    return teamDiscovery
                }
                return ErrorDiscovery.nextAction(forErrorCode: failure.code) ?? .runDoctor
            }()
            return Result(
                canStart: false, lane: lane?.rawValue, teamPresetId: teamId, teamDisplayName: nil,
                effort: effort?.rawValue, outputKind: nil, readyWorkers: [], blockedWorkers: [],
                selfFusion: SelfFusion(enabled: false, reason: nil), warnings: [],
                blockedReason: failure.description,
                nextAction: next,
                sourceGateStatus: nil)
        case .success(let req):
            let resolved = TeamResolver.resolve(
                team: req.team, requestLane: req.lane, requestEffort: req.effort,
                readyModels: readyModels, capabilities: capabilities, skill: skill)
            let byModel = Dictionary(readyModels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let workers = resolved.allWorkers.map {
                let sourceId = byModel[$0.modelId]?.driverId
                return WorkerRef(
                    workerId: $0.id, skillId: $0.skillId, skillName: $0.skillName,
                    modelId: $0.modelId,
                    sourceId: sourceId,
                    sourceDisplayName: sourceId.map { TeamSourceFacts.sourceDisplayName(sourceId: $0) },
                    purpose: ($0.purpose ?? .answer).rawValue)
            }
            let blocked = resolved.disabledRows.map {
                BlockedRef(skillId: $0.skillId, skillName: $0.skillName, required: $0.required, reason: $0.reason)
            }
            let distinctModels = Set(resolved.allWorkers.map(\.modelId))
            let fusion = SelfFusion(
                enabled: distinctModels.count == 1 && resolved.allWorkers.count > 1,
                reason: distinctModels.count == 1 && resolved.allWorkers.count > 1
                    ? "Only one ready model; prompts run with different skills (self-fusion)." : nil)
            let sourceGate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels)
            let runnable = resolved.isRunnable && sourceGate.sourceGateStatus != .blocked
            let blockedReason = sourceGate.sourceGateBlocker?.message ?? resolved.blockReason
            return Result(
                canStart: runnable, lane: req.lane.rawValue, teamPresetId: req.team.id,
                teamDisplayName: req.team.displayName, effort: req.effort.rawValue,
                outputKind: req.team.outputKind.rawValue, readyWorkers: workers, blockedWorkers: blocked,
                selfFusion: fusion, warnings: resolved.warnings, blockedReason: blockedReason,
                nextAction: runnable
                    ? .startTeamRun(teamId: req.team.id)
                    : (sourceGate.sourceGateStatus == .blocked ? .performHumanAction : .runDoctor),
                executionSourcePolicy: sourceGate.executionSourcePolicy.rawValue,
                resolvedSourceIds: sourceGate.resolvedSourceIds,
                executionSourceId: sourceGate.executionSourceId,
                sourceGateStatus: sourceGate.sourceGateStatus.rawValue,
                sourceGateBlocker: sourceGate.sourceGateBlocker,
                repairOptions: sourceGate.sourceGateBlocker?.repairOptions ?? [])
        }
    }
}
