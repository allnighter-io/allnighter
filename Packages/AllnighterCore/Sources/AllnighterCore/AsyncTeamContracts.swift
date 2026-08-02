import Foundation

/// Async team lifecycle contracts (`Agent_First_MCP_And_Messaging_Workflows.md` §A0).
/// The live polling wire speaks the frozen public `RunLifecycle` (RLR-L3) — the
/// legacy `AsyncTeamLiveStatus` (accepted/synthesizing/interrupted) is retired.
///
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

/// Agent-visible next step for async team envelopes. Same grammar as
/// `AgentSurfaceNextAction` (kind + label + runnable command), plus `runId`.
public struct AsyncTeamNextAction: Codable, Equatable, Sendable {
    public var kind: String
    public var label: String
    public var command: String
    public var runId: String

    public init(kind: String, label: String, command: String, runId: String) {
        self.kind = kind; self.label = label; self.command = command; self.runId = runId
    }

    public static func waitForTerminal(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "waitForTerminal",
            label: "Wait for the terminal PM Turn",
            command: "alln show \(runId) --stream",
            runId: runId)
    }

    public static func fetchResult(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "fetchResult",
            label: "Fetch terminal result",
            command: "alln show \(runId) --json",
            runId: runId)
    }

    /// AVQ-S01: progress is stale — do not keep waiting as primary action.
    public static func inspectStall(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "inspectStall",
            label: "Inspect stall (progressStale) — correlate with alln ps before waiting again",
            command: "alln ps --json",
            runId: runId)
    }

    /// AVQ-S01: run is behind the write lock — inspect the holder.
    public static func inspectBlocker(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "inspectBlocker",
            label: "Inspect write-lock holder / FIFO ticket (this run does not hold the mutator)",
            command: "alln ps --json",
            runId: runId)
    }
}

public struct TeamStartResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runId: String
    public var status: RunLifecycle
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
        status: RunLifecycle,
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

public struct TeamCancelResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runId: String
    public var status: RunLifecycle
    public var cancelledAt: Date

    public init(schemaVersion: Int = 1, runId: String, status: RunLifecycle, cancelledAt: Date) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.status = status
        self.cancelledAt = cancelledAt
    }
}

/// Coordinator-owned result of an explicit Team lifecycle reconciliation. This
/// is intentionally a public contract rather than a CLI-local envelope: the
/// resident is the one authority allowed to decide whether an owned run was
/// reclaimed, so every client must receive the same projection.
public struct TeamReconcileResponse: Codable, Equatable, Sendable {
    public struct ReapedRun: Codable, Equatable, Sendable {
        public var runId: String
        public var status: String
        public var endReason: String?

        public init(runId: String, status: String, endReason: String?) {
            self.runId = runId
            self.status = status
            self.endReason = endReason
        }
    }

    public var schemaVersion: Int
    public var reapedCount: Int
    public var reaped: [ReapedRun]

    public init(schemaVersion: Int = 1, reaped: [ReapedRun]) {
        self.schemaVersion = schemaVersion
        self.reapedCount = reaped.count
        self.reaped = reaped
    }
}

/// Result of the free resident admission probe used by `doctor --full`.
/// `reservationCount` must remain one when the same idempotency key is
/// delivered twice. It is deliberately separate from a TeamRun: no vendor
/// worker, journal run, or quota-bearing action exists for this probe.
public struct AdmissionProbeResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var reservationCount: Int
    public var vendorStarts: Int

    public init(schemaVersion: Int = 1, reservationCount: Int = 1, vendorStarts: Int = 0) {
        self.schemaVersion = schemaVersion
        self.reservationCount = reservationCount
        self.vendorStarts = vendorStarts
    }
}

/// Canonical payload hashed for `team start` / `alln run` idempotency (24h
/// retention, RLR-L9). The generalized field list (attachments, thread,
/// resolved team/worker, the four timeouts, proof command, commit policy,
/// contract version) is what a transport-replay match compares — one store, one
/// digest. New fields are additive; a legacy payload with fewer keys simply
/// hashes to a different digest (24h retention makes that self-healing).
public struct AsyncTeamCanonicalPayload: Codable, Equatable, Sendable {
    public var prompt: String
    public var lane: String?
    public var teamPresetId: String?
    public var effort: String?
    public var modelId: String?
    public var type: String?
    public var context: String?
    public var repoRoot: String?
    // RLR-L9 canonical generalization (S01b):
    public var attachmentDigests: [String]
    public var threadId: String?
    public var resolvedTeamId: String?
    public var resolvedWorkerIds: [String]
    public var handshakeTimeout: Int?
    public var firstActivityTimeout: Int?
    public var idleTimeout: Int?
    public var wallTimeout: Int?
    public var proofCommand: String?
    public var commitMessage: String?
    public var noCommit: Bool
    public var contractVersion: String?
    /// RSO-S01 — ordered explicit `--seat` ids at acceptance (input selectors, not resolved workers).
    public var explicitSeatModelIds: [String] = []

    public init(from request: AsyncTeamStartRequest) {
        prompt = request.question
        lane = request.lane?.rawValue
        teamPresetId = request.teamPresetId
        effort = request.effort?.rawValue
        modelId = request.modelId
        type = request.type
        context = request.context
        repoRoot = request.repoRoot
        attachmentDigests = []
        threadId = request.threadId
        resolvedTeamId = request.teamPresetId
        resolvedWorkerIds = request.modelId.map { [$0] } ?? []
        handshakeTimeout = nil
        firstActivityTimeout = nil
        idleTimeout = nil
        wallTimeout = nil
        proofCommand = nil
        commitMessage = nil
        noCommit = false
        contractVersion = nil
        explicitSeatModelIds = []
    }

    /// Sync `alln run` acceptance payload (RunService). Carries the mutating-run
    /// facts (proof command, commit policy, idle timeout, attachments) the async
    /// start request does not model.
    public init(
        prompt: String,
        lane: String?,
        teamPresetId: String?,
        effort: String?,
        modelId: String?,
        type: String?,
        context: String?,
        repoRoot: String?,
        attachmentDigests: [String] = [],
        threadId: String? = nil,
        resolvedTeamId: String? = nil,
        resolvedWorkerIds: [String] = [],
        handshakeTimeout: Int? = nil,
        firstActivityTimeout: Int? = nil,
        idleTimeout: Int? = nil,
        wallTimeout: Int? = nil,
        proofCommand: String? = nil,
        commitMessage: String? = nil,
        noCommit: Bool = false,
        contractVersion: String? = nil,
        explicitSeatModelIds: [String] = []
    ) {
        self.prompt = prompt
        self.lane = lane
        self.teamPresetId = teamPresetId
        self.effort = effort
        self.modelId = modelId
        self.type = type
        self.context = context
        self.repoRoot = repoRoot
        self.attachmentDigests = attachmentDigests
        self.threadId = threadId
        self.resolvedTeamId = resolvedTeamId
        self.resolvedWorkerIds = resolvedWorkerIds
        self.handshakeTimeout = handshakeTimeout
        self.firstActivityTimeout = firstActivityTimeout
        self.idleTimeout = idleTimeout
        self.wallTimeout = wallTimeout
        self.proofCommand = proofCommand
        self.commitMessage = commitMessage
        self.noCommit = noCommit
        self.contractVersion = contractVersion
        self.explicitSeatModelIds = explicitSeatModelIds
    }
}
