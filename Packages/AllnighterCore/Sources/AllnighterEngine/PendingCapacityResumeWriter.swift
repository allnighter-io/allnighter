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
        workerAnswer: WorkerAnswer? = nil,
        now: Date = Date()
    ) throws {
        guard let observation = outcome?.capacityObservation ?? workerAnswer?.capacityObservation else { return }
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
            item.resume = resume(from: observation, attemptId: attempt.attemptId, transcriptRef: attempt.transcriptRef)
            item.updatedAt = now
            try store.save(item)
        }
    }

    private static func resume(from observation: CapacityObservation, attemptId: String, transcriptRef: String?) -> PendingResume? {
        switch observation.kind {
        case .accountRateLimit, .cooldown, .unknownCapacity:
            return PendingResume(
                reason: .cooldown,
                lastAttemptId: attemptId,
                transcriptRef: transcriptRef,
                observedResetAt: observation.observedResetAt,
                wakeAfter: observation.wakeAfter,
                capacityObservation: observation
            )
        case .providerBusy:
            return PendingResume(
                reason: .providerBusy,
                lastAttemptId: attemptId,
                transcriptRef: transcriptRef,
                observedResetAt: observation.observedResetAt,
                wakeAfter: observation.wakeAfter,
                capacityObservation: observation
            )
        case .authRequired, .manualRequired:
            return nil
        }
    }
}
