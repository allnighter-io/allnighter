import AppKit
import Foundation
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

@MainActor
extension ThreadsViewModel {
    // MARK: - Notifications (02 + UNR-S06)

    func isThreadNotificationsMuted(_ threadId: String) -> Bool {
        notificationPolicy.isThreadMuted(threadId)
    }

    func setThreadNotificationsMuted(_ threadId: String, muted: Bool) {
        notificationPolicy.setThreadMuted(threadId, muted: muted)
        try? notificationPolicyStore.save(notificationPolicy)
    }

    func shouldSuppressNotification(candidate: NotificationCandidate) -> Bool {
        guard let thread = threads.first(where: { $0.id == candidate.threadId }) else { return true }
        return NotificationSuppression.shouldSuppress(
            candidate: candidate,
            thread: thread,
            visibility: notificationVisibilityContext()
        )
    }

    func notificationVisibilityContext() -> NotificationVisibilityContext {
        NotificationVisibilityContext(
            selectedThreadId: selectedThreadId,
            visibleTurnIdsByThread: latestVisibleTurnIds,
            isAppActive: isAppActiveForReadClear()
        )
    }

    func openFromNotification(threadId: String, turnId: String) {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return }
        select(thread)
        pendingScrollToTurnId = turnId
    }

    func openPriorityThreadFromMenuBar() {
        guard let id = floorStatus?.priorityThreadId,
              let thread = threads.first(where: { $0.id == id }) else { return }
        select(thread)
    }

    func processNotificationTransitions(
        before: [String: ThreadNotificationSnapshot]?,
        after: [String: ThreadNotificationSnapshot]
    ) async {
        let now = Date()
        var candidates = NotificationCandidateDetection.candidates(before: before, after: after, now: now)

        var runsById: [String: TeamRun] = [:]
        for thread in threads {
            for turn in thread.turns {
                guard let runId = turn.runId, runsById[runId] == nil else { continue }
                if let run = teamRun(forRunId: runId) {
                    runsById[runId] = run
                }
            }
        }
        let afterRuns = NotificationCandidateDetection.runSnapshots(
            from: threads,
            runsById: runsById
        )
        let beforeRuns: [String: RunNotificationSnapshot]? = {
            guard before != nil else { return nil }
            // Cold-start quiet: first reload after launch should not flood park notices.
            // Subsequent reloads pass the previous run snapshot via stored property.
            return previousRunNotificationSnapshots
        }()
        candidates += NotificationCandidateDetection.runCandidates(
            before: beforeRuns,
            after: afterRuns,
            now: now
        )
        previousRunNotificationSnapshots = afterRuns

        guard !candidates.isEmpty, notificationPolicy.enabled else { return }
        // URN-S01 "exactly one owner": `alln serve`'s NotificationScheduler
        // already delivers every transition below when the daemon is alive —
        // an open Mac app must not also fire, or the same event double-fires.
        // The daemon wins; the cost is this path's deep link, a Mac-only
        // affordance, acceptable for v1.
        guard serveDaemonProbe.health(binaryVersion: "").state != .available else { return }
        _ = await MacNotificationDelivery.shared.requestAuthorizationIfNeeded()
        for candidate in candidates {
            guard let thread = threads.first(where: { $0.id == candidate.threadId }) else { continue }
            if NotificationSuppression.shouldSuppress(
                candidate: candidate,
                thread: thread,
                visibility: notificationVisibilityContext()
            ) { continue }
            if !NotificationDeliveryFilter.shouldDeliver(
                candidate: candidate, policy: notificationPolicy, now: now
            ) { continue }
            let workerName = candidate.modelId.map { driverName(for: $0) }
            await notificationDelivery.deliver(candidate: candidate, workerDisplayName: workerName)
            NotificationDeliveryFilter.recordDelivery(
                candidate: candidate, policy: &notificationPolicy, now: now
            )
            try? notificationPolicyStore.save(notificationPolicy)
        }
    }
}
