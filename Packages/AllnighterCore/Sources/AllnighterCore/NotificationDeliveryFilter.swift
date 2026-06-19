import Foundation

/// Policy, mute, quiet-hours, and debounce gate before macOS delivery (NOTIF-S04).
public enum NotificationDeliveryFilter {
    public static func shouldDeliver(
        candidate: NotificationCandidate,
        policy: NotificationPolicy,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard policy.enabled else { return false }
        guard !policy.isThreadMuted(candidate.threadId) else { return false }
        guard eventEnabled(candidate.event, policy: policy) else { return false }
        guard !isQuietHours(policy: policy, now: now, calendar: calendar) else { return false }
        if let last = policy.lastDeliveredAtByThread[candidate.threadId] {
            let interval = TimeInterval(policy.debounceIntervalSeconds)
            if now.timeIntervalSince(last) < interval { return false }
        }
        return true
    }

    public static func recordDelivery(
        candidate: NotificationCandidate,
        policy: inout NotificationPolicy,
        now: Date
    ) {
        policy.lastDeliveredAtByThread[candidate.threadId] = now
    }

    public static func eventEnabled(_ event: NotificationEventKind, policy: NotificationPolicy) -> Bool {
        switch event {
        case .turnCompleted:
            return policy.notifyReplies
        case .teamRunCompleted:
            return policy.notifyTeamRunComplete
        case .turnFailed, .turnTimedOut, .turnAwaitingManualPaste, .turnAuthRequired,
             .threadNeedsAttention:
            return policy.notifyFailuresAndBlocked
        }
    }

    public static func isQuietHours(
        policy: NotificationPolicy,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard policy.quietHoursEnabled else { return false }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let start = policy.quietHoursStartMinutes
        let end = policy.quietHoursEndMinutes
        if start == end { return false }
        if start < end {
            return minutes >= start && minutes < end
        }
        return minutes >= start || minutes < end
    }
}

/// Default notification copy — no secrets in the body (02 Notifications).
public enum NotificationCopy {
    public static func title(
        candidate: NotificationCandidate,
        workerDisplayName: String?
    ) -> String {
        let quoted = quoteTitle(candidate.threadTitle)
        switch candidate.event {
        case .turnCompleted:
            let who = workerDisplayName ?? "Worker"
            return "\(who) replied in \(quoted)"
        case .teamRunCompleted:
            return "Team run complete: \(quoted)"
        case .turnFailed, .threadNeedsAttention:
            return "\(workerDisplayName ?? "Worker") needs attention in \(quoted)"
        case .turnTimedOut:
            return "Timed out in \(quoted)"
        case .turnAwaitingManualPaste:
            return "Paste required in \(quoted)"
        case .turnAuthRequired:
            return "\(workerDisplayName ?? "Worker") needs sign-in"
        }
    }

    public static func body(candidate: NotificationCandidate) -> String {
        switch candidate.event {
        case .turnCompleted, .teamRunCompleted:
            return "Open Allnighter to continue."
        case .turnFailed, .turnTimedOut, .threadNeedsAttention:
            return "A worker needs your attention."
        case .turnAwaitingManualPaste:
            return "Paste the worker reply to continue."
        case .turnAuthRequired:
            return "Sign in to continue the thread."
        }
    }

    private static func quoteTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "thread" }
        if trimmed.count <= 40 { return "\"\(trimmed)\"" }
        return "\"\(String(trimmed.prefix(37)))…\""
    }
}
