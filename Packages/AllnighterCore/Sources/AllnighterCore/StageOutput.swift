import Foundation

/// What a post-answer stage produces. A **closed** enum: exhaustive `switch`es
/// force every new purpose to be handled — a feature, not a trap.
public enum StagePurpose: String, Codable, Sendable, CaseIterable {
    case analysis
    case plan
    case review
    case finalSpec = "final_spec"
    // Design lane (Lane 2) adds the gallery board.
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
    case board(BoardPayload)

    public var purpose: StagePurpose {
        switch self {
        case .analysis: return .analysis
        case .plan: return .plan
        case .review: return .review
        case .finalSpec: return .finalSpec
        case .board: return .board
        }
    }

    /// The Markdown the stage carries, if any; nil for purely structured payloads.
    public var markdown: String? {
        switch self {
        case .analysis, .board: return nil
        case .plan(let md): return md
        case .review(let r): return r.markdown
        case .finalSpec(let f): return f.markdown
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
    public var board: BoardPayload? {
        if case .board(let b) = self { return b }
        return nil
    }
}

extension StagePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, analysis, markdown, review, finalSpec, board
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(purpose, forKey: .kind)
        switch self {
        case .analysis(let a): try c.encode(a, forKey: .analysis)
        case .plan(let md): try c.encode(md, forKey: .markdown)
        case .review(let r): try c.encode(r, forKey: .review)
        case .finalSpec(let f): try c.encode(f, forKey: .finalSpec)
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
        case .board: self = .board(try c.decode(BoardPayload.self, forKey: .board))
        }
    }
}

/// One post-answer stage in a team run. Parallel answer workers produce
/// `answers`; everything after is a `StageOutput`. A reduce/review stage is
/// produced by its own worker invocation, recorded in `producedByAgentId`;
/// `producedByAnswerWorkerId` is set only on the rare stage produced directly by
/// an answer worker.
public struct StageOutput: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var purpose: StagePurpose
    public var producedByAgentId: String?
    public var producedByAnswerWorkerId: String?
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
        producedByAgentId: String? = nil,
        producedByAnswerWorkerId: String? = nil,
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
        self.producedByAgentId = producedByAgentId
        self.producedByAnswerWorkerId = producedByAnswerWorkerId
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
