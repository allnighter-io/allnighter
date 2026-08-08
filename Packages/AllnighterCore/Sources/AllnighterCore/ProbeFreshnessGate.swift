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

    /// Drivers whose NEGATIVE verdict has aged out: unknown now, and therefore
    /// selectable.
    ///
    /// Reported as a set rather than by rewriting the record's status. Decaying
    /// into `installedNotProbed` was the obvious move and is wrong — that case
    /// already means "installed, never smoke-checked", and overloading it makes
    /// an expired verdict indistinguishable from a never-probed one, so every
    /// consumer of that case silently changes behavior for both. Callers ask
    /// this question explicitly and keep their own semantics.
    ///
    /// Positives are not included: decaying `.ready` would remove a working seat
    /// from selection to fix a problem whose entire harm is seats disappearing.
    /// Their age is disclosed, not acted on.
    public static func expiredNegativeDriverIds(
        _ records: [ToolProbeRecord], now: Date
    ) -> Set<String> {
        Set(records
            .filter { assertsUnavailable($0.status) && isExpired($0, now: now) }
            .map(\.driverId))
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
