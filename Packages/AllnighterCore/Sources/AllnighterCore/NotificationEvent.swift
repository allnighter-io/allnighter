import Foundation

/// Derived thread/turn events that may surface a local notification (02 Notifications).
public enum NotificationEventKind: String, Codable, Sendable, CaseIterable {
    case turnCompleted = "turn.completed"
    case turnFailed = "turn.failed"
    case turnTimedOut = "turn.timed_out"
    case turnAwaitingManualPaste = "turn.awaiting_manual_paste"
    case turnAuthRequired = "turn.auth_required"
    case threadNeedsAttention = "thread.needs_attention"
    case teamRunCompleted = "team_run.completed"
    case vendorParked = "team_run.vendor_parked"
    case vendorResumed = "team_run.vendor_resumed"
    case relayNeedsAnswer = "loop.needs_answer"
    case relayStopped = "relay.stopped"
    case relayStreamStalled = "relay.stream_stalled"
}

/// A notification-worthy state transition on a thread turn.
public struct NotificationCandidate: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(threadId):\(runId ?? turnId):\(event.rawValue)"
    }
    public let threadId: String
    public let turnId: String
    public let event: NotificationEventKind
    public let threadTitle: String
    public let modelId: String?
    /// Present for run-lifecycle events. It gives delivery a stable run-scoped
    /// once-each key without creating a parallel notification identity.
    public let runId: String?
    public let vendorDisplayName: String?
    public let wakeAfter: Date?
    public let occurredAt: Date

    public init(
        threadId: String,
        turnId: String,
        event: NotificationEventKind,
        threadTitle: String,
        modelId: String? = nil,
        runId: String? = nil,
        vendorDisplayName: String? = nil,
        wakeAfter: Date? = nil,
        occurredAt: Date
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.event = event
        self.threadTitle = threadTitle
        self.modelId = modelId
        self.runId = runId
        self.vendorDisplayName = vendorDisplayName
        self.wakeAfter = wakeAfter
        self.occurredAt = occurredAt
    }
}
