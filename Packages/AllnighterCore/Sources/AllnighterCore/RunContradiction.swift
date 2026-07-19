import Foundation

/// Named contradiction a status/`ps` projection may surface (RLR-L5 / S04c).
///
/// Derived at read time from retained ownership receipts + zombie-aware
/// identity-alive — never a stored boolean on `TeamRun`. This is the negative
/// proof for the inference ban "Owner → kill: terminal ⇒ nothing survives".
public enum RunContradiction: String, Codable, Sendable, Equatable {
    /// A terminal journal revision coexists with ≥1 retained recorded member
    /// that is still identity-alive (zombie-aware). Typical producer: a clock
    /// `timedOut` stamp (operator-vs-clock asymmetry) while a worker group
    /// survived the reap; never invented for a clean verified stop.
    case terminalWithLiveOwnership
}

/// Pure read-time contradiction projection (RLR-S04c). Mirrors `RunActivity`:
/// no I/O, no stored flag — callers supply terminality + precomputed
/// identity-alive facts (zombie-aware) from retained receipts.
public enum RunContradictionSurface {
    /// How long after terminal retained ownership receipts must remain readable
    /// so a second process can observe `terminalWithLiveOwnership`. Same
    /// named-constant pattern as `ProcessOwnership.stageLeaseSeconds`. The
    /// bounded reaper (`ProcessOwnership.reapExpiredOwnershipReceipts`) clears
    /// them once identity-dead **and** past this window (wired through GC).
    public static let ownershipReceiptRetentionSeconds: TimeInterval = 3_600

    /// Derive the contradiction, or `nil` when none applies.
    ///
    /// - Parameters:
    ///   - isTerminal: `run.status.isTerminal`.
    ///   - anyWorkerIdentityAlive: true when any retained `workers/<id>.owner.json`
    ///     member is still identity-alive (zombie-aware).
    ///   - coordinatorIdentityAlive: true when the retained coordinator
    ///     `owner.json` is identity-alive; ignored unless the coordinator is
    ///     process-group-killable (see below).
    ///   - coordinatorIsProcessGroupKillable: only a detached/PG-killable
    ///     coordinator counts as "live ownership." An `inProcess` coordinator
    ///     is the reader/app itself and must never trip the contradiction.
    public static func contradiction(
        isTerminal: Bool,
        anyWorkerIdentityAlive: Bool,
        coordinatorIdentityAlive: Bool = false,
        coordinatorIsProcessGroupKillable: Bool = false
    ) -> RunContradiction? {
        guard isTerminal else { return nil }
        if anyWorkerIdentityAlive { return .terminalWithLiveOwnership }
        if coordinatorIsProcessGroupKillable, coordinatorIdentityAlive {
            return .terminalWithLiveOwnership
        }
        return nil
    }
}
