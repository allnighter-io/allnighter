import Foundation

// Typed payloads carried by `StageOutput.payload` for the RB stage purposes.
// Defined once so the closed `StagePayload` union (StageOutput.swift) is complete
// and its exhaustive switches are written a single time.

/// A review lens's verdict (RB2). Advisory; never authority.
public enum ReviewVerdict: String, Codable, Sendable, CaseIterable {
    case ok, concerns, blocker
}

/// One advisory review (RB2). `lensId` is known structurally from the binding —
/// never parsed from a malformed header.
public struct ReviewResult: Codable, Sendable, Equatable {
    public var lensId: String
    public var verdict: ReviewVerdict?
    public var topConcerns: [String]
    public var markdown: String
    public init(lensId: String, verdict: ReviewVerdict? = nil, topConcerns: [String] = [], markdown: String) {
        self.lensId = lensId
        self.verdict = verdict
        self.topConcerns = topConcerns
        self.markdown = markdown
    }
}

// MARK: - Final spec (RB3)

public enum ReviewDecisionKind: String, Codable, Sendable, CaseIterable { case adopted, partial, rejected, deferred }
public enum InsightDecisionKind: String, Codable, Sendable, CaseIterable { case preserved, rejected }

public struct ReviewDecision: Codable, Sendable, Equatable {
    public var lensId: String
    public var decision: ReviewDecisionKind
    public var reason: String
    public init(lensId: String, decision: ReviewDecisionKind, reason: String) {
        self.lensId = lensId; self.decision = decision; self.reason = reason
    }
}
public struct ContradictionDecision: Codable, Sendable, Equatable {
    public var topic: String
    public var resolution: String
    public var reason: String
    public init(topic: String, resolution: String, reason: String) {
        self.topic = topic; self.resolution = resolution; self.reason = reason
    }
}
public struct InsightDecision: Codable, Sendable, Equatable {
    public var insight: String
    public var decision: InsightDecisionKind
    public var reason: String
    public init(insight: String, decision: InsightDecisionKind, reason: String) {
        self.insight = insight; self.decision = decision; self.reason = reason
    }
}

/// The final spec (RB3): Markdown + structured decisions + honesty flags.
public struct FinalSpecPayload: Codable, Sendable, Equatable {
    public var markdown: String
    public var reviewDecisions: [ReviewDecision]
    public var contradictionDecisions: [ContradictionDecision]
    public var insightDecisions: [InsightDecision]
    public var reviewBoardRan: Bool
    public var decisionsStructured: Bool
    public var hasProofCommands: Bool

    public init(
        markdown: String,
        reviewDecisions: [ReviewDecision] = [],
        contradictionDecisions: [ContradictionDecision] = [],
        insightDecisions: [InsightDecision] = [],
        reviewBoardRan: Bool = false,
        decisionsStructured: Bool = false,
        hasProofCommands: Bool = false
    ) {
        self.markdown = markdown
        self.reviewDecisions = reviewDecisions
        self.contradictionDecisions = contradictionDecisions
        self.insightDecisions = insightDecisions
        self.reviewBoardRan = reviewBoardRan
        self.decisionsStructured = decisionsStructured
        self.hasProofCommands = hasProofCommands
    }
}
