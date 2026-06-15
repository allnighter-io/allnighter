import Foundation

/// One prompt fanned out to a panel of seats plus the stage sequence that
/// follows (analysis → plan, and — in RB — reviews/final spec/dispatch/return).
/// The Mac owns this as truth; the run-event stream (§6) is derived from it.
public struct TeamRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var prompt: String
    public var status: RunStatus
    /// How the run was started (gui by default; cli/mcp/http for tool runs, RB6).
    public var origin: RunOrigin
    /// Best-effort caller label for tool runs, e.g. `claude-code`.
    public var originAgent: String?
    /// The preset this run was launched from (replaces Phase 05 `teamPresetId`).
    public var presetId: String?
    /// The seats the prompt was sent to, in display order.
    public var workers: [Worker]
    /// One result per seat (keyed by `workerId`).
    public var workerAnswers: [WorkerAnswer]
    /// Everything after the panel: analysis, plan, then RB stages.
    public var stages: [StageOutput]
    public var createdAt: Date

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
        createdAt: Date
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
        case .complete, .partial, .cancelled, .failed:
            return true
        case .draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing:
            return false
        }
    }

    /// Legal next states. `planning` spans the analysis + plan reduces.
    /// `reviewing`/`finalizing` are entered only by review-board presets.
    /// `failed` is reachable from any non-terminal state; `cancelled` from any
    /// active state. Dispatch/return-review (RB4/RB5) are post-judgment stages on
    /// a `complete` run — they are not `RunStatus` values.
    func allowedTransitions() -> Set<RunStatus> {
        switch self {
        case .draft:
            return [.fanningOut, .cancelled, .failed]
        case .fanningOut:
            return [.answersIn, .cancelled, .failed]
        case .answersIn:
            return [.planning, .reviewing, .cancelled, .failed]
        case .planning:
            return [.complete, .partial, .reviewing, .cancelled, .failed]
        case .reviewing:
            return [.finalizing, .complete, .partial, .cancelled, .failed]
        case .finalizing:
            return [.complete, .partial, .cancelled, .failed]
        case .complete, .partial, .cancelled, .failed:
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
