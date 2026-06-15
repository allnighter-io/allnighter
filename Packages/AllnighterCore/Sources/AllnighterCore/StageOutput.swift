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
    case analysis(JudgeAnalysis)
    case plan(markdown: String)
    // RB milestones add: review / finalSpec / dispatch / returnReview / outcomeScore.

    public var purpose: StagePurpose {
        switch self {
        case .analysis: return .analysis
        case .plan: return .plan
        }
    }

    /// The Markdown the stage carries, if any (plan/review/finalSpec); nil for
    /// purely structured payloads like analysis (whose `.md` is rendered).
    public var markdown: String? {
        switch self {
        case .analysis: return nil
        case .plan(let md): return md
        }
    }

    public var analysis: JudgeAnalysis? {
        if case .analysis(let a) = self { return a }
        return nil
    }
}

extension StagePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, analysis, markdown
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(purpose, forKey: .kind)
        switch self {
        case .analysis(let a): try c.encode(a, forKey: .analysis)
        case .plan(let md): try c.encode(md, forKey: .markdown)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(StagePurpose.self, forKey: .kind)
        switch kind {
        case .analysis:
            self = .analysis(try c.decode(JudgeAnalysis.self, forKey: .analysis))
        case .plan:
            self = .plan(markdown: try c.decode(String.self, forKey: .markdown))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "Unsupported StagePayload kind '\(kind.rawValue)' for this build."
            )
        }
    }
}

/// One post-panel stage in a council run. The panel fan-out produces `members`;
/// everything after is a `StageOutput`. A reduce is produced by a worker
/// invocation that is **not** a panel seat, so `producedByWorkerId` is the
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
