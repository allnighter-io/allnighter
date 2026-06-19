import Foundation

/// One prompt fanned out to a panel of seats plus the stage sequence that
/// follows (analysis, plan, reviews, and final output).
/// The Mac owns this as truth; the run-event stream (§6) is derived from it.
public struct TeamRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var prompt: String
    public var status: RunStatus
    /// How the run was started (gui by default; cli/mcp/http for tool runs, RB6).
    public var origin: RunOrigin
    /// Best-effort caller label for tool runs, e.g. `claude-code`.
    public var originAgent: String?
    /// The team this run was launched from (the catalog `TeamPreset.id`).
    public var presetId: String?
    /// The workers the prompt was sent to, in display order.
    public var workers: [Worker]
    /// One result per answer/review worker (keyed by `workerId`).
    public var workerAnswers: [WorkerAnswer]
    /// Everything after the answer stage: review/plan/output stages.
    public var stages: [StageOutput]
    public var createdAt: Date

    // Catalog facts, so the persisted run is self-describing (Fan out runs set
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

    public init(
        id: String,
        prompt: String,
        status: RunStatus = .draft,
        origin: RunOrigin = .gui,
        originAgent: String? = nil,
        presetId: String? = nil,
        workers: [Worker] = [],
        workerAnswers: [WorkerAnswer] = [],
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
        originMessageId: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
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
    }
}

// MARK: - Derived state

public extension TeamRun {
    var answeredWorkers: [WorkerAnswer] {
        workerAnswers.filter(\.hasAnswer)
    }

    var failedWorkerAnswers: [WorkerAnswer] {
        workerAnswers.filter { $0.status == .failed || $0.status == .timedOut }
    }

    /// True once every non-skipped member has reached a terminal state.
    var allWorkerAnswersSettled: Bool {
        workerAnswers.allSatisfy { $0.status.isTerminal || $0.status == .skipped }
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

    func workerAnswer(workerId: String) -> WorkerAnswer? {
        workerAnswers.first { $0.workerId == workerId }
    }
}

// MARK: - Run state machine (single source of truth)

public extension RunStatus {
    var isTerminal: Bool {
        switch self {
        case .complete, .partial, .cancelled, .failed, .interrupted:
            return true
        case .draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing:
            return false
        }
    }

    /// Legal next states. `planning` spans the analysis + plan reduces.
    /// `reviewing`/`finalizing` are entered only by review-board presets.
    /// `failed` is reachable from any non-terminal state; `cancelled` from any
    /// active state. Mutating follow-up work is represented as a separate run,
    /// not a `RunStatus` value.
    func allowedTransitions() -> Set<RunStatus> {
        switch self {
        case .draft:
            return [.fanningOut, .cancelled, .failed, .interrupted]
        case .fanningOut:
            return [.answersIn, .cancelled, .failed, .interrupted]
        case .answersIn:
            return [.planning, .reviewing, .cancelled, .failed, .interrupted]
        case .planning:
            return [.complete, .partial, .reviewing, .cancelled, .failed, .interrupted]
        case .reviewing:
            return [.finalizing, .complete, .partial, .cancelled, .failed, .interrupted]
        case .finalizing:
            return [.complete, .partial, .cancelled, .failed, .interrupted]
        case .complete, .partial, .cancelled, .failed, .interrupted:
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

public extension WorkerAnswer {
    func canTransition(to next: WorkerAnswerStatus) -> Bool {
        status.allowedTransitions().contains(next)
    }
}
