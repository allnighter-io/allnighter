import Foundation

/// User-facing notification preferences (02 Notifications S01).
public struct NotificationPolicy: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var notifyReplies: Bool
    public var notifyTeamRunComplete: Bool
    public var notifyFailuresAndBlocked: Bool
    public var quietHoursEnabled: Bool
    /// Minutes from midnight for quiet-hours start (local calendar).
    public var quietHoursStartMinutes: Int
    /// Minutes from midnight for quiet-hours end (local calendar).
    public var quietHoursEndMinutes: Int
    public var mutedThreadIds: Set<String>
    /// Debounce key → last delivered time (thread-scoped).
    public var lastDeliveredAtByThread: [String: Date]
    /// Durable run-scoped once-each keys for vendor park/recovery notifications.
    /// Bounded naturally to two entries per run and stored with the existing
    /// notification policy; no parallel delivery state.
    public var deliveredLifecycleEventIds: Set<String>
    public var debounceIntervalSeconds: Int
    /// Whether macOS notification permission was granted when last checked.
    public var macOSPermissionGranted: Bool?

    public init(
        enabled: Bool = true,
        notifyReplies: Bool = true,
        notifyTeamRunComplete: Bool = true,
        notifyFailuresAndBlocked: Bool = true,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinutes: Int = 22 * 60,
        quietHoursEndMinutes: Int = 8 * 60,
        mutedThreadIds: Set<String> = [],
        lastDeliveredAtByThread: [String: Date] = [:],
        deliveredLifecycleEventIds: Set<String> = [],
        debounceIntervalSeconds: Int = 30,
        macOSPermissionGranted: Bool? = nil
    ) {
        self.enabled = enabled
        self.notifyReplies = notifyReplies
        self.notifyTeamRunComplete = notifyTeamRunComplete
        self.notifyFailuresAndBlocked = notifyFailuresAndBlocked
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
        self.mutedThreadIds = mutedThreadIds
        self.lastDeliveredAtByThread = lastDeliveredAtByThread
        self.deliveredLifecycleEventIds = deliveredLifecycleEventIds
        self.debounceIntervalSeconds = debounceIntervalSeconds
        self.macOSPermissionGranted = macOSPermissionGranted
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, notifyReplies, notifyTeamRunComplete, notifyFailuresAndBlocked
        case quietHoursEnabled, quietHoursStartMinutes, quietHoursEndMinutes
        case mutedThreadIds, lastDeliveredAtByThread, deliveredLifecycleEventIds
        case debounceIntervalSeconds, macOSPermissionGranted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        notifyReplies = try c.decode(Bool.self, forKey: .notifyReplies)
        notifyTeamRunComplete = try c.decode(Bool.self, forKey: .notifyTeamRunComplete)
        notifyFailuresAndBlocked = try c.decode(Bool.self, forKey: .notifyFailuresAndBlocked)
        quietHoursEnabled = try c.decode(Bool.self, forKey: .quietHoursEnabled)
        quietHoursStartMinutes = try c.decode(Int.self, forKey: .quietHoursStartMinutes)
        quietHoursEndMinutes = try c.decode(Int.self, forKey: .quietHoursEndMinutes)
        mutedThreadIds = try c.decode(Set<String>.self, forKey: .mutedThreadIds)
        lastDeliveredAtByThread = try c.decode(
            [String: Date].self,
            forKey: .lastDeliveredAtByThread
        )
        deliveredLifecycleEventIds = try c.decodeIfPresent(
            Set<String>.self,
            forKey: .deliveredLifecycleEventIds
        ) ?? []
        debounceIntervalSeconds = try c.decode(Int.self, forKey: .debounceIntervalSeconds)
        macOSPermissionGranted = try c.decodeIfPresent(
            Bool.self,
            forKey: .macOSPermissionGranted
        )
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
