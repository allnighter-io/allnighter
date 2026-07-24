import Foundation
import AgentOSTeam

/// One prompt sent to a team of workers plus the stage sequence that
/// follows (analysis, plan, reviews, and final output).
/// The Mac owns this as truth; the run-event stream (§6) is derived from it.
/// A durable link between two runs (Try Fix chain). `nextActions` describe what CAN happen;
/// links record what DID happen — diagnosis -> fix attempt -> proof -> retry.
public struct RunLink: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case diagnosisOf, fixAttemptFor, proofFor, retryOf
        /// Pair-programming slice envelope → executor attempt.
        case sliceOf, sliceAttemptFor
    }
    public var kind: Kind
    public var runId: String
    public init(kind: Kind, runId: String) { self.kind = kind; self.runId = runId }
}

/// What a non-terminal run is durably waiting on (RLR-L4). S01b wrote the
/// minimal stub — `resource` + canonical `scopeRoot`. S02a enriches it, while the
/// run is parked in the per-root FIFO, with the ticket facts (holder ref, queue
/// position, holder acquire time) so a second process can name WHO holds the lock
/// and WHERE we sit in line. Terminal transitions clear it in the same journal
/// revision (RLR-L3 atomic rule). The frozen S01 names `resource`/`scopeRoot` are
/// untouched — the S02a fields are additive and optional so legacy `run.json`
/// decodes them `nil`.
public struct RunBlocker: Codable, Sendable, Equatable {
    public enum Resource: String, Codable, Sendable, CaseIterable {
        case repoWriteLock, teamGovernor, driverCapacity, vendorBackoff
    }
    public var resource: Resource
    /// Canonical (symlink + case normalized) repo root for write-lock waits.
    /// Vendor parks leave this nil and use `quotaScope`.
    public var scopeRoot: String?
    /// Canonical id of the holding work (S02a: the holder run's own id). Nil until
    /// the ticket is minted / when there is no identified holder.
    public var holderId: String?
    /// Public holder kind — always `run` in P0 (RLR-L4; relay/pilot/proof later),
    /// never the raw internal `ExecutionLaneSite` string.
    public var holderKind: String?
    /// 1-based FIFO position among blocked waiters (head of queue = 1).
    public var ticketPosition: Int?
    /// When the current holder acquired the lane; `heldSinceSeconds` is derived at
    /// projection, never stored (RLR-L4).
    public var holderAcquiredAt: Date?
    /// Driver/account/profile/model-family quota key. Nil for write-lock blockers.
    public var quotaScope: String?
    /// Conservative local wake boundary. Nil routes to S02's unknown-reset path.
    public var wakeAfter: Date?
    /// The single sourced capacity truth. Never mint a parallel rate-limit payload.
    public var capacityObservation: CapacityObservation?
    public init(
        resource: Resource,
        scopeRoot: String? = nil,
        holderId: String? = nil,
        holderKind: String? = nil,
        ticketPosition: Int? = nil,
        holderAcquiredAt: Date? = nil,
        quotaScope: String? = nil,
        wakeAfter: Date? = nil,
        capacityObservation: CapacityObservation? = nil
    ) {
        self.resource = resource
        self.scopeRoot = scopeRoot
        self.holderId = holderId
        self.holderKind = holderKind
        self.ticketPosition = ticketPosition
        self.holderAcquiredAt = holderAcquiredAt
        self.quotaScope = quotaScope
        self.wakeAfter = wakeAfter
        self.capacityObservation = capacityObservation
    }
}

public struct TeamRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var prompt: String
    public var status: RunStatus
    /// Durable phase (RLR-L3/L6). Only meaningful for non-terminal runs; terminal
    /// transitions clear it. Optional so legacy `run.json` (no `phase` key) decodes
    /// to `nil`. Phase truth lives here on the journal, not on heartbeat.json.
    public var phase: RunPhase?
    /// How the run was started (gui by default; cli/mcp/http for tool runs, RB6).
    public var origin: RunOrigin
    /// Best-effort caller label for tool runs, e.g. `claude-code`.
    public var originAgent: String?
    /// The team this run was launched from (the catalog `TeamPreset.id`).
    public var presetId: String?
    /// The workers the prompt was sent to, in display order.
    public var workers: [Worker]
    /// One result per answer/review worker (keyed by `memberId`, F2_B.3c: was
    /// `[WorkerAnswer]`, now AgentOSTeam's `[TeamAnswer]` — same shape, `result:
    /// WorkerRunResult` instead of the flat inline fields).
    public var workerAnswers: [TeamAnswer]
    /// Everything after the answer stage: review/plan/output stages.
    public var stages: [StageOutput]
    public var createdAt: Date

    // Catalog facts, so the persisted run is self-describing (catalog team runs set
    // these; legacy runs leave them nil/empty). The public projection prefers
    // these over caller-supplied context.
    public var lane: WorkLane?
    public var type: String?
    public var effort: EffortLevel?
    public var teamDisplayName: String?
    public var outputKind: TeamOutputKind?
    /// Captured at run start so the Floor stays self-describing after catalog
    /// changes. Legacy runs leave `mutating` false.
    public var mutating: Bool = false
    /// When this is a mutating run, the single CLI driver that owns execution.
    public var executionSourceId: String? = nil
    /// Non-fatal warnings recorded at run time (one-model self-fusion, fallbacks,
    /// disabled optional rows, admission queueing). Defaulted so legacy persisted
    /// runs (no `warnings` key) still decode.
    public var warnings: [String] = []
    public var threadId: String?
    public var originConversationId: String?
    public var originMessageId: String?
    /// Repo root workers were launched in (team/MCP runs with `repoRoot` / `project`).
    public var repoRoot: String? = nil
    /// Try Fix chain (Try_Fix_Auto_Implement): a child fix-attempt run records the parent
    /// Bug Hunt run it came from; the parent links forward to the child. So the Floor can
    /// show diagnosis -> fix attempt -> proof. Optional so existing run.json (which predates
    /// these keys) still decodes; read via `runLinks`.
    public var parentRunId: String?
    public var links: [RunLink]?
    /// Timing ladder and counters captured from the GUI/engine hot path. Optional so
    /// legacy persisted runs decode unchanged.
    public var timing: RunTimingReport?
    /// Observed git delta for mutating runs (Field_Reports_1.md §FR3). `nil` for read-only runs.
    public var repoDelta: RepoDelta? = nil
    /// CR-S02 — bounded pre/post Git observation for a research (read-only) run. `nil`
    /// for mutating runs (they carry `repoDelta`) and for runs recorded before CR-S02.
    /// `changed == true` is a surfaced research-write violation; files are never reset.
    public var researchGitObservation: ResearchGitObservation? = nil
    /// True when `--lane` was passed alongside an explicit `--worker` — lane is context
    /// metadata on the run identity, not the router (`Field_Reports_3.md` FR7).
    public var laneContextOnly: Bool? = nil
    /// ADP-S01 — the caller's explicit `--worker` selector(s) at run acceptance,
    /// canonicalized to the resolved worker id(s). Persisted so every replay surface
    /// (`reproduceCommand`) can round-trip the explicit selection that `workers` alone
    /// can't distinguish from default-team resolution. Optional so legacy `run.json`
    /// (no key) decodes to `nil`; `nil`/empty means no explicit `--worker` was given.
    public var explicitWorkerIds: [String]? = nil
    /// FR12 — requested verbatim commit message (verification only).
    public var requestedCommitMessage: String? = nil
    /// FR12 — worker was instructed to leave work uncommitted.
    public var noCommitOrdered: Bool? = nil
    /// FR12 — dirty file count observed when `noCommitOrdered` and no new commits landed.
    public var uncommittedFileCount: Int? = nil
    /// FR13 — bounded proof subprocess result (after worker settlement).
    public var proofResult: RunProofResult? = nil
    /// Why this run ended — required for terminal runs (PO-S01). Optional so
    /// legacy `run.json` still decodes; reconcile/cancel/complete stamp it.
    public var endReason: RunEndReason? = nil
    /// The typed verdict of the last kill/cancel settlement (RLR-L5, S04b). Set
    /// on every operator kill/cancel; a `.stopped` verdict also stamps a terminal
    /// `endReason`, while `partial`/`refused`/`verificationUnavailable` record the
    /// verdict here and leave the lifecycle non-terminal (S01c pre-reserved this
    /// name as owed-by-S04). Optional so legacy `run.json` decodes to `nil`.
    public var killOutcome: KillOutcome? = nil
    /// What a non-terminal run is waiting on (RLR-L4). Set while `queued`
    /// (`waitingForWriteLock` or `waitingForVendor`), cleared when the lock/vendor
    /// wait is acquired and on any terminal transition. Optional so legacy
    /// `run.json` decodes to `nil`.
    public var blocker: RunBlocker? = nil
    /// Sequential unified-run attempts. Append-only once runtime wiring lands in
    /// S02/S04; legacy journals with no key decode as an empty array.
    @LegacySafeArray public var attempts: [RunAttempt] = []
    /// Durable last-activity clock (RLR-L6 / S03a). Advances ONLY on post-spawn
    /// L6 activity (structured message, bounded stdout/stderr metadata, child
    /// transition, exit) — NEVER on spawn, heartbeats, or per-tick timers. Nil
    /// until the first post-spawn activity; legacy `run.json` decodes to `nil`.
    /// A second process polls this off `run.json` (the durable truth), replacing
    /// the retired `heartbeat.json`.
    public var lastActivityAt: Date? = nil
    /// Kind of the last recorded activity (RLR-L6). Nil before first activity.
    public var lastActivityKind: RunActivityKind? = nil
    /// Per-run clock budgets (RLR-L8 / S05). Persisted at acceptance so a second
    /// process can reason about handshake / first-activity / idle / wall bounds.
    /// Optional so legacy `run.json` decodes to `nil`.
    public var clockBudgets: RunClockBudgets? = nil
    /// Non-optional view of `links` for callers.
    public var runLinks: [RunLink] { links ?? [] }

    public init(
        id: String,
        prompt: String,
        status: RunStatus = .draft,
        phase: RunPhase? = nil,
        origin: RunOrigin = .gui,
        originAgent: String? = nil,
        presetId: String? = nil,
        workers: [Worker] = [],
        workerAnswers: [TeamAnswer] = [],
        stages: [StageOutput] = [],
        createdAt: Date,
        lane: WorkLane? = nil,
        type: String? = nil,
        effort: EffortLevel? = nil,
        teamDisplayName: String? = nil,
        outputKind: TeamOutputKind? = nil,
        mutating: Bool = false,
        executionSourceId: String? = nil,
        warnings: [String] = [],
        threadId: String? = nil,
        originConversationId: String? = nil,
        originMessageId: String? = nil,
        repoRoot: String? = nil,
        timing: RunTimingReport? = nil,
        repoDelta: RepoDelta? = nil,
        laneContextOnly: Bool? = nil,
        explicitWorkerIds: [String]? = nil,
        requestedCommitMessage: String? = nil,
        noCommitOrdered: Bool? = nil,
        uncommittedFileCount: Int? = nil,
        proofResult: RunProofResult? = nil,
        endReason: RunEndReason? = nil,
        killOutcome: KillOutcome? = nil,
        blocker: RunBlocker? = nil,
        attempts: [RunAttempt] = [],
        lastActivityAt: Date? = nil,
        lastActivityKind: RunActivityKind? = nil,
        clockBudgets: RunClockBudgets? = nil,
        links: [RunLink]? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.phase = phase
        self.origin = origin
        self.originAgent = originAgent
        self.presetId = presetId
        self.workers = workers
        self.workerAnswers = workerAnswers
        self.stages = stages
        self.createdAt = createdAt
        self.lane = lane
        self.type = type
        self.effort = effort
        self.teamDisplayName = teamDisplayName
        self.outputKind = outputKind
        self.mutating = mutating
        self.executionSourceId = executionSourceId
        self.warnings = warnings
        self.threadId = threadId
        self.originConversationId = originConversationId
        self.originMessageId = originMessageId
        self.repoRoot = repoRoot
        self.timing = timing
        self.repoDelta = repoDelta
        self.laneContextOnly = laneContextOnly
        self.explicitWorkerIds = explicitWorkerIds
        self.requestedCommitMessage = requestedCommitMessage
        self.noCommitOrdered = noCommitOrdered
        self.uncommittedFileCount = uncommittedFileCount
        self.proofResult = proofResult
        self.endReason = endReason
        self.killOutcome = killOutcome
        self.blocker = blocker
        self.attempts = attempts
        self.lastActivityAt = lastActivityAt
        self.lastActivityKind = lastActivityKind
        self.clockBudgets = clockBudgets
        self.links = links
    }
}

// MARK: - Derived state

public extension TeamRun {
    var answeredWorkers: [TeamAnswer] {
        workerAnswers.filter(\.hasAnswer)
    }

    var failedWorkerAnswers: [TeamAnswer] {
        workerAnswers.filter { $0.result.status == .failed || $0.result.status == .timedOut }
    }

    /// True once every non-skipped member has reached a terminal state.
    var allWorkerAnswersSettled: Bool {
        workerAnswers.allSatisfy { $0.result.status.isTerminal || $0.result.status == .skipped }
    }

    /// The latest stage output of a given purpose (stages are append-only; the
    /// latest of a purpose/lens is the active one).
    func latestStage(_ purpose: StagePurpose) -> StageOutput? {
        stages.last { $0.purpose == purpose }
    }

    /// The structured judge analysis, if the analysis stage completed.
    var analysis: PlanAnalysis? {
        latestStage(.analysis).flatMap { $0.status == .done ? $0.payload?.analysis : nil }
    }

    /// The plan Markdown, if the plan stage completed.
    var plan: String? {
        guard let plan = latestStage(.plan), plan.status == .done else { return nil }
        return plan.payload?.markdown
    }

    func workerAnswer(workerId: String) -> TeamAnswer? {
        workerAnswers.first { $0.memberId == workerId }
    }
}

// MARK: - Run state machine (single source of truth)

public extension RunStatus {
    var isTerminal: Bool {
        switch self {
        case .done, .complete, .partial, .timedOut, .cancelled, .failed, .interrupted:
            return true
        case .queued, .running, .draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing:
            return false
        }
    }

    /// Legal next states. `queued → running` is the one-worker path; `running`
    /// still advances into the multi-stage machine (`answers_in → planning → …`)
    /// so a single-worker team run synthesizes normally. `planning` spans the
    /// analysis + plan reduces. `reviewing`/`finalizing` are entered only by
    /// review-board presets. `failed`/`timedOut` are reachable from any
    /// non-terminal state; `cancelled` from any active state. Mutating follow-up
    /// work is a separate run, not a `RunStatus` value.
    func allowedTransitions() -> Set<RunStatus> {
        switch self {
        case .draft:
            return [.queued, .running, .fanningOut, .cancelled, .failed, .timedOut, .interrupted]
        case .queued:
            return [.running, .fanningOut, .cancelled, .failed, .timedOut, .interrupted]
        case .running:
            return [.answersIn, .done, .complete, .partial, .cancelled, .failed, .timedOut, .interrupted]
        case .fanningOut:
            return [.answersIn, .cancelled, .failed, .timedOut, .interrupted]
        case .answersIn:
            return [.planning, .reviewing, .cancelled, .failed, .timedOut, .interrupted]
        case .planning:
            return [.complete, .done, .partial, .reviewing, .cancelled, .failed, .timedOut, .interrupted]
        case .reviewing:
            return [.finalizing, .complete, .done, .partial, .cancelled, .failed, .timedOut, .interrupted]
        case .finalizing:
            return [.complete, .done, .partial, .cancelled, .failed, .timedOut, .interrupted]
        case .done, .complete, .partial, .timedOut, .cancelled, .failed, .interrupted:
            return []
        }
    }
}

public extension TeamRun {
    func canTransition(to next: RunStatus) -> Bool {
        status.allowedTransitions().contains(next)
    }
}

// MARK: - Member state machine

public extension WorkerAnswerStatus {
    var isTerminal: Bool {
        switch self {
        case .done, .failed, .timedOut, .cancelled:
            return true
        case .queued, .running, .skipped:
            return false
        }
    }

    func allowedTransitions() -> Set<WorkerAnswerStatus> {
        switch self {
        case .queued:
            return [.running, .skipped, .cancelled]
        case .running:
            return [.done, .failed, .timedOut, .cancelled]
        case .skipped:
            // A manual-paste member: pasted answer -> done, or run later, or cancel.
            return [.running, .done, .cancelled]
        case .done, .failed, .timedOut, .cancelled:
            return []
        }
    }
}

public extension TeamAnswer {
    func canTransition(to next: WorkerAnswerStatus) -> Bool {
        result.status.allowedTransitions().contains(next)
    }
}
