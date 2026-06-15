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

// MARK: - Dispatch + return (RB4/RB5)

public enum ExecutionStatus: String, Codable, Sendable, CaseIterable {
    case queued, running, done, failed, timedOut = "timed_out", partial, reveal
}

/// The captured result of dispatching a spec to an executor CLI (RB4); also the
/// single source of truth RB5 reads. Observational only — no landing/commit logic.
public struct ExecutionReturn: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var executionWorkerId: String
    public var workingDirectory: String
    public var dispatchIndex: Int
    public var status: ExecutionStatus
    public var exitCode: Int?
    public var transcriptPath: String?
    public var transcriptExcerpt: String?
    public var diffSummary: String?
    public var baselineCommit: String?
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: String, executionWorkerId: String, workingDirectory: String, dispatchIndex: Int,
        status: ExecutionStatus, exitCode: Int? = nil, transcriptPath: String? = nil,
        transcriptExcerpt: String? = nil, diffSummary: String? = nil, baselineCommit: String? = nil,
        startedAt: Date? = nil, finishedAt: Date? = nil
    ) {
        self.id = id
        self.executionWorkerId = executionWorkerId
        self.workingDirectory = workingDirectory
        self.dispatchIndex = dispatchIndex
        self.status = status
        self.exitCode = exitCode
        self.transcriptPath = transcriptPath
        self.transcriptExcerpt = transcriptExcerpt
        self.diffSummary = diffSummary
        self.baselineCommit = baselineCommit
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public enum RoutingAction: String, Codable, Sendable, CaseIterable { case rerun, remix, pick }

public struct RoutingRecommendation: Codable, Sendable, Equatable {
    public var action: RoutingAction
    public var reasoning: String
    public init(action: RoutingAction, reasoning: String) { self.action = action; self.reasoning = reasoning }
}

/// The return review (RB5): advisory evaluation of an execution return.
public struct ReturnReviewPayload: Codable, Sendable, Equatable {
    public var markdown: String
    public var recommendation: RoutingRecommendation?
    public init(markdown: String, recommendation: RoutingRecommendation? = nil) {
        self.markdown = markdown; self.recommendation = recommendation
    }
}
