import Foundation

/// Derived thread/turn events that may surface a local notification (02 Notifications).
public enum NotificationEventKind: String, Codable, Sendable, CaseIterable {
    case turnCompleted = "turn.completed"
    case turnFailed = "turn.failed"
    case turnTimedOut = "turn.timed_out"
    case turnAwaitingManualPaste = "turn.awaiting_manual_paste"
    case turnAuthRequired = "turn.auth_required"
    case threadNeedsAttention = "thread.needs_attention"
    case dispatchReturned = "dispatch.returned"
    case returnReviewCompleted = "return_review.completed"
    case teamRunCompleted = "team_run.completed"
}

/// A notification-worthy state transition on a thread turn.
public struct NotificationCandidate: Sendable, Equatable, Identifiable {
    public var id: String { "\(threadId):\(turnId):\(event.rawValue)" }
    public let threadId: String
    public let turnId: String
    public let event: NotificationEventKind
    public let threadTitle: String
    public let workerId: String?
    public let occurredAt: Date

    public init(
        threadId: String,
        turnId: String,
        event: NotificationEventKind,
        threadTitle: String,
        workerId: String? = nil,
        occurredAt: Date
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.event = event
        self.threadTitle = threadTitle
        self.workerId = workerId
        self.occurredAt = occurredAt
    }
}
