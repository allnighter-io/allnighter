import Foundation
import AgentOSCLI

/// PF-S00 — read-time freshness for the probe cache.
///
/// The probe cache is returned whole by `SourceProbeService`'s fast path with no
/// TTL, so a verdict could outlive its own evidence indefinitely: on 2026-08-08
/// `cli_setup.json` was 38 hours old, its observations declared
/// `retryAfterSeconds: 3600`, and `alln menu` still reported Grok and Kimi as
/// unavailable while both answered live prompts in the same minute.
///
/// Two laws, from `Run_Readout_Truth`'s sibling packet `Probe_Freshness.md`:
///
/// 1. **Expiry projects; it never rewrites.** This is a read-time view. The
///    persisted record and its `lastProbeAt` are untouched — a menu invocation
///    must not mutate durable state, and the disclosure slice needs the original
///    timestamp to report age.
/// 2. **Staleness may never rank a seat below unknown.** The costs are not
///    symmetric: a stale positive costs one loud failed run, while a stale
///    negative silently removes a seat the user pays for, for as long as the
///    cache survives. So an expired *negative* stops being asserted; it does not
///    become a stronger claim, and it never becomes a `blockedReason`.
///
/// Dispatch is unaffected either way — `DispatchReadiness` already refuses to
/// block on probe caches. This gate governs the selection surfaces, which is
/// where the seat actually disappeared from view.
public enum ProbeFreshnessGate {

    /// One freshness constant, shared with capacity paint
    /// (`CapacityPaintGate.gateInterval`). A second clock here would be a second
    /// thing to explain when the two disagree.
    public static var gateInterval: TimeInterval { 30 * 60 }

    /// True when the record may no longer be asserted as current.
    ///
    /// Either its own stated validity has elapsed — an observation that said
    /// "retry after an hour" is not evidence 38 hours later — or it is simply
    /// older than the freshness clock.
    public static func isExpired(_ record: ToolProbeRecord, now: Date) -> Bool {
        let age = now.timeIntervalSince(record.lastProbeAt)
        if let retryAfter = retryAfterSeconds(of: record.status), age >= Double(retryAfter) {
            return true
        }
        return age >= gateInterval
    }

    /// Why a stored negative may not be asserted. Both project the same status;
    /// they differ in what is honest to say about it, and the difference is the
    /// point — "not checked recently" is itself a lie about a record probed two
    /// minutes ago whose verdict was never evidence.
    public enum UnassertedReason: String, Sendable, Equatable {
        /// Observed, but the observation has outlived its own evidence (PF-S00).
        case expired
        /// Never observed — we computed it. The vendor said nothing (PF-S02).
        case inferred
    }

    /// Drivers whose NEGATIVE verdict may not be asserted: unknown now, and
    /// therefore selectable.
    ///
    /// Reported as a projection rather than by rewriting the record's status.
    /// Decaying into `installedNotProbed` was the obvious move and is wrong —
    /// that case already means "installed, never smoke-checked", and overloading
    /// it makes an unassertable verdict indistinguishable from a never-probed
    /// one, so every consumer of that case silently changes behavior for both.
    /// Callers ask this question explicitly and keep their own semantics.
    ///
    /// Positives are not included: decaying `.ready` would remove a working seat
    /// from selection to fix a problem whose entire harm is seats disappearing.
    /// Their age is disclosed, not acted on.
    ///
    /// `inferred` outranks `expired` when a record is both: "we never knew" is a
    /// deeper statement than "we knew a while ago", and refreshing an inferred
    /// verdict does not make it evidence.
    public static func unassertableNegatives(
        _ records: [ToolProbeRecord], now: Date
    ) -> [String: UnassertedReason] {
        var out: [String: UnassertedReason] = [:]
        for record in records where assertsUnavailable(record.status) {
            if isInferred(record.status) {
                out[record.driverId] = .inferred
            } else if isExpired(record, now: now) {
                out[record.driverId] = .expired
            }
        }
        return out
    }

    /// True when a `.rateLimited` verdict was computed locally rather than
    /// stated by the vendor.
    ///
    /// PF-S02. VSI's law is that absence of a declared signal yields no
    /// observation, never an inferred one — so a limit no vendor asserted is not
    /// a limit, it is silence. `.probeFailed` is deliberately excluded: a probe
    /// that actually failed is a local fact we genuinely observed, and it ages
    /// out on the clock like any other.
    public static func isInferred(_ status: ModelSetupStatus) -> Bool {
        guard case .rateLimited(let observation) = status else { return false }
        return !isVendorStated(observation)
    }

    /// The one definition of "the vendor said this", shared with
    /// `DoctorReport.rateLimitedDetail`. Two copies of this predicate is how a
    /// surface ends up withholding the limit while another still prints it.
    public static func isVendorStated(_ observation: CapacityObservation) -> Bool {
        observation.sourceConfidence == .structured
            || observation.sourceConfidence == .messageFallback
    }

    /// Negative verdicts that are OBSERVATIONS, and therefore age.
    ///
    /// Deliberately narrow. `notInstalled` is a detection fact — the binary was
    /// or was not on PATH — and it does not decay into "maybe available"; a
    /// newly installed CLI is picked up by re-probing (the scheduler slice), not
    /// by auto-seating something that may be absent. `installedNotSignedIn` and
    /// `shimmedNeedsConfirm` are standing setup facts that name a fix the user
    /// can act on. `installedNotProbed` is already the weakest claim.
    ///
    /// What is left is exactly what burned us: a smoke-derived `rateLimited` or
    /// `probeFailed` that outlived its own evidence.
    public static func assertsUnavailable(_ status: ModelSetupStatus) -> Bool {
        switch status {
        case .rateLimited, .probeFailed:
            return true
        case .ready, .installedNotProbed, .installedNotSignedIn,
             .shimmedNeedsConfirm, .notInstalled:
            return false
        }
    }

    private static func retryAfterSeconds(of status: ModelSetupStatus) -> Int? {
        guard case .rateLimited(let observation) = status else { return nil }
        return observation.retryAfterSeconds
    }
}
