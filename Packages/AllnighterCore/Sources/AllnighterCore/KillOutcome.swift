import Foundation

/// The typed verdict of one kill/cancel settlement (RLR-L5, RLR-S04b).
///
/// The whole phase turns on this: an operator kill/cancel stamps a terminal
/// `endReason` (`killed`/`cancelled`) **only** on `.stopped` — every recorded
/// member is verified identity-dead (zombie-aware) and its group empty. The
/// other three outcomes record the verdict durably and leave the lifecycle
/// **non-terminal** (the operator-vs-clock asymmetry: a non-verified operator
/// stop is honest partial/refused, never a `killed` lie over live work; the
/// clocks — RLR-L8 — stay terminal regardless).
///
/// - `stopped`: every recorded member is identity-dead and every recorded group
///   is empty (a zombie-only residual also settles `stopped`, with a cleanup
///   warning). The only outcome that stamps terminal.
/// - `partial`: signalled, but ≥1 recorded member is still identity-alive (or a
///   recorded group is non-empty) after the grace. Survivors are named;
///   non-terminal.
/// - `refused`: recorded members exist but none could be signalled (all
///   identity-mismatched / non-PG-killable). Nothing was stopped; non-terminal.
/// - `verificationUnavailable`: a run that is executing but carries **no**
///   recorded worker `runtimeOwnership` (warm workers / unrecorded legacy) — the
///   stop cannot be verified, so it is never stamped `killed`. This is the warm
///   exclusion seam (RLR §1.9): warm drivers record nothing, so this rule covers
///   them with no warm-specific code.
public enum KillOutcome: String, Codable, Sendable, CaseIterable, Equatable {
    case stopped
    case partial
    case refused
    case verificationUnavailable

    /// True only for `.stopped` — the sole outcome that may stamp a terminal
    /// `endReason`. The other three leave the lifecycle non-terminal.
    public var stampsTerminal: Bool { self == .stopped }

    /// The error-envelope code this outcome projects onto (RLR-L5 / spec error
    /// catalog). `.stopped` has no error projection (it is the success path);
    /// nil there. Same fact as the journal's `killOutcome`, never a second truth.
    public var errorCode: String? {
        switch self {
        case .stopped: return nil
        case .partial: return "KILL_PARTIAL"
        case .refused: return "KILL_REFUSED"
        case .verificationUnavailable: return "KILL_VERIFICATION_UNAVAILABLE"
        }
    }
}
