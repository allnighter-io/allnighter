import Foundation
import AllnighterCore

/// Vendor-stated reset per source, read from the capacity crawler's history.
///
/// A rate-limited badge is built from a **failed run's error text**, which
/// structurally never carries a reset time — that is why the badge used to print
/// a locally invented one (`observedAt + 3600`, rendered with no date, which is
/// how two CLIs both showed "resets 4:55 PM" from a probe the previous day).
///
/// The crawler is the sensor that actually reads each CLI's own usage screen, so
/// its reset is the only honest one. One definition, because the CLI badge and
/// the GUI badge describing the same seat must not disagree about when it clears.
public enum CapacityResetLookup {

    /// Future vendor resets keyed by source id. Sources with no recorded window
    /// are absent, so callers fall back to whatever they showed before.
    ///
    /// `lastKnownWindows` reads recorded history and nothing else: no probe, no
    /// spawn, no quota. Rendering a badge must never cost the user a vendor call.
    public static func bySource(
        now: Date,
        historyStore: CapacityHistoryStore = CapacityHistoryStore()
    ) -> [String: Date] {
        var out: [String: Date] = [:]
        for window in historyStore.lastKnownWindows(now: now) {
            guard let reset = window.resetAt, reset > now else { continue }
            // The long allowance is what gates a seat for hours. A 5h bucket
            // clearing sooner does not make the CLI usable while the weekly
            // allowance is still spent, so the later boundary is the honest
            // "wait until".
            out[window.source] = out[window.source].map { max($0, reset) } ?? reset
        }
        return out
    }
}
