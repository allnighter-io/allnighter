import Foundation
import AllnighterCore

/// Why a Pending item was skipped by the resident wake planner (debug/tests only).
public struct PendingWakeSkip: Sendable, Equatable {
    public var itemId: String
    public var reason: String

    public init(itemId: String, reason: String) {
        self.itemId = itemId
        self.reason = reason
    }
}

/// Pure wake selection — earliest due workerChat Wake Ticket, or next future deadline.
public struct PendingWakePlan: Sendable, Equatable {
    public var dueItemId: String?
    public var nextWakeAt: Date?
    public var skips: [PendingWakeSkip]

    public init(dueItemId: String? = nil, nextWakeAt: Date? = nil, skips: [PendingWakeSkip] = []) {
        self.dueItemId = dueItemId
        self.nextWakeAt = nextWakeAt
        self.skips = skips
    }
}

public enum PendingWakePlanner {
  /// Eligible: `pending` + `workerChat` + `projectId` + resume `cooldown`/`providerBusy` + due `nextWakeAt`.
    public static func plan(items: [PendingItem], now: Date) -> PendingWakePlan {
        var skips: [PendingWakeSkip] = []
        var dueCandidates: [(id: String, wakeAt: Date)] = []
        var futureWakes: [Date] = []

        for item in items {
            if let skip = skipReason(for: item, now: now) {
                skips.append(.init(itemId: item.id, reason: skip))
                continue
            }
            guard let wakeAt = PendingItemDerivation.nextWakeAt(for: item) else {
                skips.append(.init(itemId: item.id, reason: "noNextWakeAt"))
                continue
            }
            if wakeAt <= now {
                dueCandidates.append((item.id, wakeAt))
            } else {
                futureWakes.append(wakeAt)
            }
        }

        let dueItemId = dueCandidates.min(by: { $0.wakeAt < $1.wakeAt })?.id
        let nextWakeAt = futureWakes.min()
        return PendingWakePlan(dueItemId: dueItemId, nextWakeAt: nextWakeAt, skips: skips)
    }

    /// Returns a skip reason string, or `nil` when the item may participate in wake planning.
    public static func skipReason(for item: PendingItem, now: Date) -> String? {
        switch item.status {
        case .draft: return "draft"
        case .running: return "running"
        case .done: return "done"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .pending: break
        }

        guard item.kind == .workerChat else { return "unsupportedKind:\(item.kind.rawValue)" }
        guard item.projectId != nil else { return "unassigned" }

        guard let resume = item.resume else { return "idlePending" }
        switch resume.reason {
        case .cooldown, .providerBusy: break
        case .localBusy, .timeout, .stopped, .appRestart, .macSleep, .userPaused:
            return "resumeReason:\(resume.reason.rawValue)"
        }

        if let kind = resume.capacityObservation?.kind {
            switch kind {
            case .authRequired, .manualRequired: return "blocker:\(kind.rawValue)"
            default: break
            }
        }

        guard PendingItemDerivation.nextWakeAt(for: item) != nil else { return "noNextWakeAt" }
        _ = now
        return nil
    }
}
