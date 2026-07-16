import Foundation

/// Async team lifecycle contracts (`Agent_First_MCP_And_Messaging_Workflows.md` §A0).
/// Live polling vocabulary is distinct from archived `TeamRunJSON.teamRun.status`.
public enum AsyncTeamLiveStatus: String, Codable, Sendable, CaseIterable {
    case accepted, running, synthesizing
    case completed, failed, timedOut, cancelled, interrupted

    public var isTerminal: Bool {
        switch self {
        case .accepted, .running, .synthesizing: return false
        case .completed, .failed, .timedOut, .cancelled, .interrupted: return true
        }
    }
}

/// Extended start request — same resolution surface as `TeamRequest` plus async metadata.
public struct AsyncTeamStartRequest: Codable, Sendable, Equatable {
    public var question: String
    public var lane: WorkLane?
    public var teamPresetId: String?
    public var effort: EffortLevel?
    /// Bench model id when pinning a single-worker mutating run (Default Team / Auto).
    public var modelId: String?
    public var type: String?
    public var context: String?
    public var threadId: String?
    public var originAgent: String?
    public var originConversationId: String?
    public var originMessageId: String?
    public var idempotencyKey: String?
    /// Repo root for worker subprocess cwd. nil ⇒ ProbeScratch (chat-without-project).
    public var repoRoot: String?

    public init(
        question: String,
        lane: WorkLane? = nil,
        teamPresetId: String? = nil,
        effort: EffortLevel? = nil,
        modelId: String? = nil,
        type: String? = nil,
        context: String? = nil,
        threadId: String? = nil,
        originAgent: String? = nil,
        originConversationId: String? = nil,
        originMessageId: String? = nil,
        idempotencyKey: String? = nil,
        repoRoot: String? = nil
    ) {
        self.question = question
        self.lane = lane
        self.teamPresetId = teamPresetId
        self.effort = effort
        self.modelId = modelId
        self.type = type
        self.context = context
        self.threadId = threadId
        self.originAgent = originAgent
        self.originConversationId = originConversationId
        self.originMessageId = originMessageId
        self.idempotencyKey = idempotencyKey
        self.repoRoot = repoRoot
    }

    public var teamRequest: TeamRequest {
        TeamRequest(question: question, lane: lane, teamPresetId: teamPresetId,
                    effort: effort, type: type, context: context, repoRoot: repoRoot)
    }
}

public struct AsyncTeamNextAction: Codable, Equatable, Sendable {
    public var kind: String
    public var tool: String
    public var runId: String

    public init(kind: String, tool: String, runId: String) {
        self.kind = kind; self.tool = tool; self.runId = runId
    }
}

public struct TeamStartResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runId: String
    public var status: AsyncTeamLiveStatus
    public var lane: String?
    public var teamPresetId: String?
    public var teamDisplayName: String?
    public var effort: String?
    public var acceptedAt: Date
    public var nextPollAfterMs: Int
    public var nextActions: [AsyncTeamNextAction]

    public init(
        schemaVersion: Int = 1,
        runId: String,
        status: AsyncTeamLiveStatus,
        lane: String?,
        teamPresetId: String?,
        teamDisplayName: String?,
        effort: String?,
        acceptedAt: Date,
        nextPollAfterMs: Int,
        nextActions: [AsyncTeamNextAction]
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.status = status
        self.lane = lane
        self.teamPresetId = teamPresetId
        self.teamDisplayName = teamDisplayName
        self.effort = effort
        self.acceptedAt = acceptedAt
        self.nextPollAfterMs = nextPollAfterMs
        self.nextActions = nextActions
    }
}

public struct TeamStatusWorker: Codable, Equatable, Sendable {
    public var workerId: String
    public var displayName: String
    public var status: String
    public var startedAt: Date?
    public var finishedAt: Date?
    public var warning: String?

    public init(workerId: String, displayName: String, status: String,
                startedAt: Date? = nil, finishedAt: Date? = nil, warning: String? = nil) {
        self.workerId = workerId
        self.displayName = displayName
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.warning = warning
    }
}

public struct TeamStatusResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runId: String
    public var status: AsyncTeamLiveStatus
    public var lane: String?
    public var teamPresetId: String?
    public var effort: String?
    public var currentStage: String?
    public var workers: [TeamStatusWorker]
    /// Terminal workers (completed, failed, timedOut, cancelled).
    public var workersDone: Int
    public var workersTotal: Int
    public var warnings: [String]
    public var resultAvailable: Bool
    public var nextPollAfterMs: Int
    public var traceId: String

    public init(
        schemaVersion: Int = 1,
        runId: String,
        status: AsyncTeamLiveStatus,
        lane: String?,
        teamPresetId: String?,
        effort: String?,
        currentStage: String?,
        workers: [TeamStatusWorker],
        workersDone: Int,
        workersTotal: Int,
        warnings: [String],
        resultAvailable: Bool,
        nextPollAfterMs: Int,
        traceId: String
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.status = status
        self.lane = lane
        self.teamPresetId = teamPresetId
        self.effort = effort
        self.currentStage = currentStage
        self.workers = workers
        self.workersDone = workersDone
        self.workersTotal = workersTotal
        self.warnings = warnings
        self.resultAvailable = resultAvailable
        self.nextPollAfterMs = nextPollAfterMs
        self.traceId = traceId
    }
}

/// Emitted when `team result` is called before the run is terminal/ready.
public struct TeamResultNotReady: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var success: Bool
    public var runId: String
    public var status: AsyncTeamLiveStatus
    public var resultAvailable: Bool
    public var nextPollAfterMs: Int
    public var error: ErrorEnvelope

    public init(
        schemaVersion: Int = 1,
        runId: String,
        status: AsyncTeamLiveStatus,
        resultAvailable: Bool,
        nextPollAfterMs: Int,
        error: ErrorEnvelope
    ) {
        self.schemaVersion = schemaVersion
        self.success = false
        self.runId = runId
        self.status = status
        self.resultAvailable = resultAvailable
        self.nextPollAfterMs = nextPollAfterMs
        self.error = error
    }
}

public struct TeamCancelResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runId: String
    public var status: AsyncTeamLiveStatus
    public var cancelledAt: Date

    public init(schemaVersion: Int = 1, runId: String, status: AsyncTeamLiveStatus, cancelledAt: Date) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.status = status
        self.cancelledAt = cancelledAt
    }
}

/// Canonical payload hashed for `team start` idempotency (24h retention).
public struct AsyncTeamCanonicalPayload: Codable, Equatable, Sendable {
    public var prompt: String
    public var lane: String?
    public var teamPresetId: String?
    public var effort: String?
    public var modelId: String?
    public var type: String?
    public var context: String?
    public var repoRoot: String?

    public init(from request: AsyncTeamStartRequest) {
        prompt = request.question
        lane = request.lane?.rawValue
        teamPresetId = request.teamPresetId
        effort = request.effort?.rawValue
        modelId = request.modelId
        type = request.type
        context = request.context
        repoRoot = request.repoRoot
    }
}
