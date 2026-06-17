import Foundation

/// User-facing notification preferences (02 Notifications S01).
public struct NotificationPolicy: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var notifyReplies: Bool
    public var notifyTeamRunComplete: Bool
    public var notifyDispatchReturned: Bool
    public var notifyFailuresAndBlocked: Bool
    public var quietHoursEnabled: Bool
    /// Minutes from midnight for quiet-hours start (local calendar).
    public var quietHoursStartMinutes: Int
    /// Minutes from midnight for quiet-hours end (local calendar).
    public var quietHoursEndMinutes: Int
    public var mutedThreadIds: Set<String>
    /// Debounce key → last delivered time (thread-scoped).
    public var lastDeliveredAtByThread: [String: Date]
    public var debounceIntervalSeconds: Int
    /// Whether macOS notification permission was granted when last checked.
    public var macOSPermissionGranted: Bool?

    public init(
        enabled: Bool = true,
        notifyReplies: Bool = true,
        notifyTeamRunComplete: Bool = true,
        notifyDispatchReturned: Bool = true,
        notifyFailuresAndBlocked: Bool = true,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinutes: Int = 22 * 60,
        quietHoursEndMinutes: Int = 8 * 60,
        mutedThreadIds: Set<String> = [],
        lastDeliveredAtByThread: [String: Date] = [:],
        debounceIntervalSeconds: Int = 30,
        macOSPermissionGranted: Bool? = nil
    ) {
        self.enabled = enabled
        self.notifyReplies = notifyReplies
        self.notifyTeamRunComplete = notifyTeamRunComplete
        self.notifyDispatchReturned = notifyDispatchReturned
        self.notifyFailuresAndBlocked = notifyFailuresAndBlocked
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
        self.mutedThreadIds = mutedThreadIds
        self.lastDeliveredAtByThread = lastDeliveredAtByThread
        self.debounceIntervalSeconds = debounceIntervalSeconds
        self.macOSPermissionGranted = macOSPermissionGranted
    }

    public func isThreadMuted(_ threadId: String) -> Bool {
        mutedThreadIds.contains(threadId)
    }

    public mutating func setThreadMuted(_ threadId: String, muted: Bool) {
        if muted {
            mutedThreadIds.insert(threadId)
        } else {
            mutedThreadIds.remove(threadId)
        }
    }
}
