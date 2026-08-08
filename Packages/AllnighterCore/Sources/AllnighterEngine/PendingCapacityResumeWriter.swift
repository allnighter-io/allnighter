import Foundation
import AllnighterCore

/// Maps sourced capacity observations onto existing Pending items (WTK-S01c).
/// Does not create new Pending work or Wake Tickets for auth/manual blockers.
public enum PendingCapacityResumeWriter {
    /// Apply capacity resume facts to linked Pending items after a worker/thread attempt.
    public static func applyLinkedCapacity(
        store: PendingStore,
        threadId: String? = nil,
        runId: String? = nil,
        outcome: WorkerRunOutcome? = nil,
        now: Date = Date()
    ) throws {
        guard let observation = outcome?.capacityObservation else { return }
        switch observation.kind {
        case .authRequired, .manualRequired: return
        default: break
        }

        let items = try store.loadOrdered().items
        let linked = items.filter { item in
            guard item.status == .running || item.status == .pending else { return false }
            if let runId, item.runId == runId { return true }
            if let threadId, item.threadId == threadId { return true }
            return false
        }
        guard !linked.isEmpty else { return }

        for var item in linked {
            guard var attempt = item.attempts.last else { continue }
            attempt.status = .blocked
            attempt.reason = observation.kind.rawValue
            attempt.completedAt = now
            item.attempts[item.attempts.count - 1] = attempt
            item.status = .pending
            item.lease = nil
            item.resume = resume(
                from: observation, attemptId: attempt.attemptId,
                transcriptRef: attempt.transcriptRef, now: now)
            item.updatedAt = now
            try store.save(item)
        }
    }

    /// Local recheck cadence for a transient block whose vendor stated no reset.
    ///
    /// VSI §10.2 rule 2: an OBSERVATION carries no invented numbers — a vendor
    /// that did not state a reset does not get one attributed to it. But a Wake
    /// Ticket is a local SCHEDULING artifact, and without any wake a blocked
    /// item never becomes due (`PendingWakePlanner` only selects among items
    /// with a due `nextWakeAt` — it does not mint them), so the work sits
    /// forever. The cadence therefore lives here, locally computed and never
    /// written back onto `capacityObservation`, which stays vendor truth.
    static let localRecheckInterval: TimeInterval = 60

    /// Single capacity -> resume policy. `PendingService` delegates here so the
    /// mapping (and its local wake cadence) cannot drift between the two call
    /// paths — it had already been copied once.
    static func resume(
        from observation: CapacityObservation,
        attemptId: String,
        transcriptRef: String?,
        now: Date
    ) -> PendingResume? {
        // A vendor-stated wake always wins; the local cadence only fills silence.
        func wake() -> Date {
            observation.wakeAfter
                ?? observation.observedResetAt
                ?? now.addingTimeInterval(localRecheckInterval)
        }
        switch observation.kind {
        case .accountRateLimit, .cooldown, .unknownCapacity:
            return PendingResume(
                reason: .cooldown,
                lastAttemptId: attemptId,
                transcriptRef: transcriptRef,
                observedResetAt: observation.observedResetAt,
                wakeAfter: wake(),
                capacityObservation: observation
            )
        case .providerBusy:
            return PendingResume(
                reason: .providerBusy,
                lastAttemptId: attemptId,
                transcriptRef: transcriptRef,
                observedResetAt: observation.observedResetAt,
                wakeAfter: wake(),
                capacityObservation: observation
            )
        case .authRequired, .manualRequired:
            return nil
        }
    }
}
