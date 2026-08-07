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
        if candidate.runId != nil,
           candidate.event == .vendorParked || candidate.event == .vendorResumed {
            return !policy.deliveredLifecycleEventIds.contains(candidate.id)
        }
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
        if candidate.runId != nil,
           candidate.event == .vendorParked || candidate.event == .vendorResumed {
            policy.deliveredLifecycleEventIds.insert(candidate.id)
        }
    }

    public static func eventEnabled(_ event: NotificationEventKind, policy: NotificationPolicy) -> Bool {
        switch event {
        case .turnCompleted:
            return policy.notifyReplies
        case .teamRunCompleted:
            return policy.notifyTeamRunComplete
        case .turnFailed, .turnTimedOut, .turnAwaitingManualPaste, .turnAuthRequired,
             .threadNeedsAttention, .vendorParked, .vendorResumed,
             .relayNeedsAnswer, .relayStopped, .relayStreamStalled,
             .loopParked, .loopResumed:
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
        case .vendorParked:
            return VendorContinuityPresentation.parkNotification(
                vendorDisplayName: candidate.vendorDisplayName ?? workerDisplayName ?? "Vendor"
            )
        case .vendorResumed:
            return VendorContinuityPresentation.recoveryNotification(
                vendorDisplayName: candidate.vendorDisplayName ?? workerDisplayName ?? "Vendor",
                resumedAt: candidate.occurredAt
            )
        case .turnCompleted:
            let who = workerDisplayName ?? "Agent"
            return "\(who) replied in \(quoted)"
        case .teamRunCompleted:
            return "Team run complete: \(quoted)"
        case .turnFailed, .threadNeedsAttention:
            return "\(workerDisplayName ?? "Agent") needs attention in \(quoted)"
        case .turnTimedOut:
            return "Timed out in \(quoted)"
        case .turnAwaitingManualPaste:
            return "Paste required in \(quoted)"
        case .turnAuthRequired:
            return "\(workerDisplayName ?? "Agent") needs sign-in"
        case .relayNeedsAnswer:
            return "Delivery Loop needs an answer"
        case .relayStopped:
            return "Delivery Loop stopped"
        case .relayStreamStalled:
            return "Relay worker stream stalled"
        case .loopParked:
            let vendor = candidate.vendorDisplayName ?? workerDisplayName ?? "vendor"
            return "Loop parked — waiting on \(vendor)"
        case .loopResumed:
            return "Loop resumed"
        }
    }

    public static func body(candidate: NotificationCandidate) -> String {
        switch candidate.event {
        case .vendorParked:
            return "Allnighter will continue this run locally."
        case .vendorResumed:
            return "The same run is working again."
        case .turnCompleted, .teamRunCompleted:
            return "Open Allnighter to continue."
        case .turnFailed, .turnTimedOut, .threadNeedsAttention:
            return "A worker needs your attention."
        case .turnAwaitingManualPaste:
            return "Paste the worker reply to continue."
        case .turnAuthRequired:
            return "Sign in to continue the thread."
        case .relayNeedsAnswer:
            return "Open Allnighter to answer."
        case .relayStopped:
            return "Check the relay's final state."
        case .relayStreamStalled:
            return "Agent output has been silent — inspect with `alln loop status` or `alln ps`."
        case .loopParked:
            return "Capacity park — waiting on the vendor."
        case .loopResumed:
            return "The loop is working again."
        }
    }

    private static func quoteTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "thread" }
        if trimmed.count <= 40 { return "\"\(trimmed)\"" }
        return "\"\(String(trimmed.prefix(37)))…\""
    }
}
