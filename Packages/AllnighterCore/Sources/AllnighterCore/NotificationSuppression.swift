import Foundation

/// Viewport facts the notification policy may consult (UNR-S06).
public struct NotificationVisibilityContext: Sendable, Equatable {
    public var selectedThreadId: String?
    public var visibleTurnIdsByThread: [String: Set<String>]
    public var isAppActive: Bool

    public init(
        selectedThreadId: String? = nil,
        visibleTurnIdsByThread: [String: Set<String>] = [:],
        isAppActive: Bool = false
    ) {
        self.selectedThreadId = selectedThreadId
        self.visibleTurnIdsByThread = visibleTurnIdsByThread
        self.isAppActive = isAppActive
    }
}

/// Suppresses local notification delivery when the landed turn is already visible
/// or read. Delivery and click-through are never read truth (06 + 02).
public enum NotificationSuppression {
    public static func shouldSuppress(
        candidate: NotificationCandidate,
        thread: WorkThread,
        visibility: NotificationVisibilityContext
    ) -> Bool {
        if !UnreadDerivation.unreadTurnIds(thread: thread).contains(candidate.turnId) {
            return true
        }
        guard visibility.isAppActive,
              visibility.selectedThreadId == candidate.threadId,
              let visible = visibility.visibleTurnIdsByThread[candidate.threadId],
              visible.contains(candidate.turnId)
        else {
            return false
        }
        return true
    }
}
