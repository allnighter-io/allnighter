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

    public static func pollStatus(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "poll",
            label: "Poll run status",
            command: "alln team status \(runId) --json",
            runId: runId)
    }

    public static func fetchResult(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "fetchResult",
            label: "Fetch terminal result",
            command: "alln team result \(runId) --json",
            runId: runId)
    }

    public static func waitForStatus(runId: String) -> AsyncTeamNextAction {
        AsyncTeamNextAction(
            kind: "waitForStatus",
            label: "Wait, then re-check status",
            command: "alln team status \(runId) --json",
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
    public var status: RunLifecycle
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
    /// Why a terminal run ended (PO-S01). Nil while still live. Never inferred.
    public var endReason: String?
    /// Last real progress event (worker transition / output). Progress-truth only.
    public var lastProgressAt: Date?
    /// Identity-alive but no progress for the stale threshold — never auto-reaped.
    public var progressStale: Bool?
    /// Last kill/cancel settlement verdict (RLR-L5 / S04b). Nil when never settled.
    public var killOutcome: String?
    /// Read-time contradiction (RLR-S04c). `terminalWithLiveOwnership` when a
    /// terminal journal coexists with a still identity-alive retained member.
    public var contradiction: String?
    /// Human-readable silence when identity-alive (IDLE-HF-S04), e.g.
    /// `alive, no stream for 120s`.
    public var silenceStatus: String?
    /// Agent next step after status / wait (PO-F3). Always set on wait-for
    /// returns; optional on plain status for forward compatibility.
    public var nextAction: AsyncTeamNextAction?
    /// Seconds the harness suggests sleeping before the next check when the
    /// target is not yet reached (PO-F3). 0 when terminal / target matched.
    public var waitHintSeconds: Double?

    public init(
        schemaVersion: Int = 1,
        runId: String,
        status: RunLifecycle,
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
        traceId: String,
        endReason: String? = nil,
        lastProgressAt: Date? = nil,
        progressStale: Bool? = nil,
        killOutcome: String? = nil,
        contradiction: String? = nil,
        silenceStatus: String? = nil,
        nextAction: AsyncTeamNextAction? = nil,
        waitHintSeconds: Double? = nil
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
        self.endReason = endReason
        self.lastProgressAt = lastProgressAt
        self.progressStale = progressStale
        self.killOutcome = killOutcome
        self.contradiction = contradiction
        self.silenceStatus = silenceStatus
        self.nextAction = nextAction
        self.waitHintSeconds = waitHintSeconds
    }
}

/// Explicit, read-only projection of a durable Team journal. This is never a
/// substitute for the resident's live lifecycle answer: callers must opt in
/// with `team status --persisted`, and the envelope makes the observation's
/// source and possible staleness machine-visible.
public struct PersistedTeamStatusResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var source: String
    public var live: Bool
    public var eventSequence: Int64
    public var observedAt: Date
    public var status: TeamStatusResponse

    public init(
        schemaVersion: Int = 1,
        source: String = "journal",
        live: Bool = false,
        eventSequence: Int64,
        observedAt: Date = Date(),
        status: TeamStatusResponse
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.live = live
        self.eventSequence = eventSequence
        self.observedAt = observedAt
        self.status = status
    }
}

/// Target for `team status --wait-for` (PO-F3 / RLR-L3). Lifecycle states only
/// (`queued|running|done|failed|timedOut|cancelled`) plus the aggregate
/// `terminal` alias (any `RunLifecycle.isTerminal`).
public enum TeamStatusWaitTarget: Sendable, Equatable {
    case live(RunLifecycle)
    case anyTerminal

    public static func parse(_ raw: String) -> TeamStatusWaitTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "terminal" { return .anyTerminal }
        guard let live = RunLifecycle(rawValue: trimmed) else { return nil }
        return .live(live)
    }

    public func matches(_ status: RunLifecycle) -> Bool {
        switch self {
        case .live(let target): return status == target
        case .anyTerminal: return status.isTerminal
        }
    }

    public var description: String {
        switch self {
        case .live(let s): return s.rawValue
        case .anyTerminal: return "terminal"
        }
    }
}

/// Outcome of an in-process `team status --wait-for` (PO-F3).
public struct TeamStatusWaitOutcome: Sendable, Equatable {
    public var response: TeamStatusResponse
    /// True when the deadline elapsed without the target matching.
    public var timedOut: Bool
    /// True when a non-matching terminal state was observed while waiting for a
    /// different target (agent should stop polling).
    public var terminalMismatch: Bool

    public init(response: TeamStatusResponse, timedOut: Bool, terminalMismatch: Bool = false) {
        self.response = response
        self.timedOut = timedOut
        self.terminalMismatch = terminalMismatch
    }
}

/// Emitted when `team result` is called before the run is terminal/ready.
public struct TeamResultNotReady: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var success: Bool
    public var runId: String
    public var status: RunLifecycle
    public var resultAvailable: Bool
    public var nextPollAfterMs: Int
    public var error: ErrorEnvelope

    public init(
        schemaVersion: Int = 1,
        runId: String,
        status: RunLifecycle,
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
        contractVersion: String? = nil
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
    }
}
