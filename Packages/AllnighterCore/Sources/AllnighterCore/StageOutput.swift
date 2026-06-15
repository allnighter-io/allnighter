import Foundation

/// What a post-panel stage produces. A **closed** enum: exhaustive `switch`es
/// force every new purpose to be handled — a feature, not a trap. RB milestones
/// add cases (`review`, `final_spec`, `dispatch`, `return_review`, `outcome_score`).
public enum StagePurpose: String, Codable, Sendable, CaseIterable {
    case analysis
    case plan
    // RB extends additively:
    case review
    case finalSpec = "final_spec"
    case dispatch
    case returnReview = "return_review"
    case outcomeScore = "outcome_score"
    // Design council (Lane 2) adds the gallery board.
    case board
}

/// Lifecycle of one stage. `reused` = a content-addressed prior output was reused
/// instead of spending a call (RB1).
public enum StageStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case done
    case failed
    case timedOut = "timed_out"
    case skipped
    case reused
}

/// Typed structured truth for one stage — one case per `StagePurpose`. Markdown
/// views are derived from this; the payload is the only truth. New milestones add
/// a case here, never a parallel struct or loose optional fields.
public enum StagePayload: Sendable, Equatable {
    case analysis(PlanAnalysis)
    case plan(markdown: String)
    case review(ReviewResult)
    case finalSpec(FinalSpecPayload)
    case dispatch(ExecutionReturn)
    case returnReview(ReturnReviewPayload)
    case outcomeScore(EvalScore)
    case board(BoardPayload)

    public var purpose: StagePurpose {
        switch self {
        case .analysis: return .analysis
        case .plan: return .plan
        case .review: return .review
        case .finalSpec: return .finalSpec
        case .dispatch: return .dispatch
        case .returnReview: return .returnReview
        case .outcomeScore: return .outcomeScore
        case .board: return .board
        }
    }

    /// The Markdown the stage carries, if any; nil for purely structured payloads.
    public var markdown: String? {
        switch self {
        case .analysis, .dispatch, .outcomeScore, .board: return nil
        case .plan(let md): return md
        case .review(let r): return r.markdown
        case .finalSpec(let f): return f.markdown
        case .returnReview(let r): return r.markdown
        }
    }

    public var analysis: PlanAnalysis? {
        if case .analysis(let a) = self { return a }
        return nil
    }
    public var review: ReviewResult? {
        if case .review(let r) = self { return r }
        return nil
    }
    public var finalSpec: FinalSpecPayload? {
        if case .finalSpec(let f) = self { return f }
        return nil
    }
    public var executionReturn: ExecutionReturn? {
        if case .dispatch(let e) = self { return e }
        return nil
    }
    public var returnReview: ReturnReviewPayload? {
        if case .returnReview(let r) = self { return r }
        return nil
    }
    public var outcomeScore: EvalScore? {
        if case .outcomeScore(let s) = self { return s }
        return nil
    }
    public var board: BoardPayload? {
        if case .board(let b) = self { return b }
        return nil
    }
}

extension StagePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, analysis, markdown, review, finalSpec, dispatch, returnReview, outcomeScore, board
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(purpose, forKey: .kind)
        switch self {
        case .analysis(let a): try c.encode(a, forKey: .analysis)
        case .plan(let md): try c.encode(md, forKey: .markdown)
        case .review(let r): try c.encode(r, forKey: .review)
        case .finalSpec(let f): try c.encode(f, forKey: .finalSpec)
        case .dispatch(let e): try c.encode(e, forKey: .dispatch)
        case .returnReview(let r): try c.encode(r, forKey: .returnReview)
        case .outcomeScore(let s): try c.encode(s, forKey: .outcomeScore)
        case .board(let b): try c.encode(b, forKey: .board)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(StagePurpose.self, forKey: .kind)
        switch kind {
        case .analysis: self = .analysis(try c.decode(PlanAnalysis.self, forKey: .analysis))
        case .plan: self = .plan(markdown: try c.decode(String.self, forKey: .markdown))
        case .review: self = .review(try c.decode(ReviewResult.self, forKey: .review))
        case .finalSpec: self = .finalSpec(try c.decode(FinalSpecPayload.self, forKey: .finalSpec))
        case .dispatch: self = .dispatch(try c.decode(ExecutionReturn.self, forKey: .dispatch))
        case .returnReview: self = .returnReview(try c.decode(ReturnReviewPayload.self, forKey: .returnReview))
        case .outcomeScore: self = .outcomeScore(try c.decode(EvalScore.self, forKey: .outcomeScore))
        case .board: self = .board(try c.decode(BoardPayload.self, forKey: .board))
        }
    }
}

/// One post-panel stage in a team run. The panel fan-out produces `members`;
/// everything after is a `StageOutput`. A reduce is produced by a worker
/// invocation that is **not** a worker, so `producedByWorkerId` is the
/// producer; `producedBySeatId` is set only on the rare seat-produced stage.
public struct StageOutput: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var purpose: StagePurpose
    public var producedByWorkerId: String?
    public var producedBySeatId: String?
    /// The named profile used — OR `customInstruction` (exactly one is set). The
    /// honest record of what ran.
    public var promptProfileId: String?
    public var customInstruction: String?
    public var status: StageStatus
    public var payload: StagePayload?
    /// Content address for automatic reuse (RB1 computes/matches; nil in Phase 06).
    public var reuseKey: String?
    public var errorReason: String?
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: String,
        purpose: StagePurpose,
        producedByWorkerId: String? = nil,
        producedBySeatId: String? = nil,
        promptProfileId: String? = nil,
        customInstruction: String? = nil,
        status: StageStatus = .queued,
        payload: StagePayload? = nil,
        reuseKey: String? = nil,
        errorReason: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.purpose = purpose
        self.producedByWorkerId = producedByWorkerId
        self.producedBySeatId = producedBySeatId
        self.promptProfileId = promptProfileId
        self.customInstruction = customInstruction
        self.status = status
        self.payload = payload
        self.reuseKey = reuseKey
        self.errorReason = errorReason
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public extension StageStatus {
    var isTerminal: Bool {
        switch self {
        case .done, .failed, .timedOut, .skipped, .reused: return true
        case .queued, .running: return false
        }
    }
}
