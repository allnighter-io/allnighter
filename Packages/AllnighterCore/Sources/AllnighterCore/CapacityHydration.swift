import Foundation

/// Live-or-last-known merge for the capacity strip (CAP-HF-00).
///
/// Pure: no IO, no clock reads beyond the caller's `now` for open-window filter.
/// Live known samples always win. Bare `neverSampled` falls back to open history
/// with **original** `observedAt` — never re-stamped.
///
/// **Refresh failure law:** a failed *current attempt* must not be disguised as
/// live by silently substituting history. Callers pass
/// `suppressHistoryForSources` for seats that were probed this turn and failed;
/// those keep the live unknown reason (parser/timeout/spawn/empty).
///
/// History is fallback only; it is not a live stream.
public enum CapacityHydration {

    /// Merge live acquisition with durable last-known windows for display.
    ///
    /// - Parameters:
    ///   - live: Windows from `CapacityAcquisition` (this process).
    ///   - history: Open last-known windows from `CapacityHistoryStore` projection.
    ///   - now: Used only to drop closed history (`resetAt <= now`).
    ///   - benchOrder: Stable product order for sources with no live row.
    ///   - suppressHistoryForSources: Sources whose live result is a failed
    ///     refresh attempt — keep failure, do not paint history as current.
    public static func apply(
        live: [CapacityWindow],
        history: [CapacityWindow],
        now: Date,
        benchOrder: [String] = CapacityAcquisition.benchSourceOrder,
        suppressHistoryForSources: Set<String> = []
    ) -> [CapacityWindow] {
        let liveBy = Dictionary(grouping: live, by: \.source)
        let histBy = Dictionary(grouping: history, by: \.source)
        var seen = Set<String>()
        var order: [String] = []
        for id in benchOrder where seen.insert(id).inserted {
            order.append(id)
        }
        for id in liveBy.keys.sorted() where seen.insert(id).inserted {
            order.append(id)
        }
        for id in histBy.keys.sorted() where seen.insert(id).inserted {
            order.append(id)
        }

        var result: [CapacityWindow] = []
        for source in order {
            result.append(contentsOf: prefer(
                live: liveBy[source] ?? [],
                history: histBy[source] ?? [],
                source: source,
                now: now,
                suppressHistory: suppressHistoryForSources.contains(source)
            ))
        }
        return result
    }

    /// Prefer live known → (optional) open history known → live unknown → synthetic neverSampled.
    public static func prefer(
        live: [CapacityWindow],
        history: [CapacityWindow],
        source: String,
        now: Date,
        suppressHistory: Bool = false
    ) -> [CapacityWindow] {
        let liveKnown = live.filter { $0.unknownReason == nil }
        if !liveKnown.isEmpty {
            return liveKnown
        }

        // Failed current attempt: keep the failure reason. Never paint history as live.
        if suppressHistory, !live.isEmpty {
            return live
        }

        let histKnown = history.filter { window in
            guard window.unknownReason == nil else { return false }
            if let reset = window.resetAt, reset <= now { return false }
            return true
        }
        if !histKnown.isEmpty {
            return histKnown
        }

        if !live.isEmpty {
            return live
        }

        let tier: CapacityAcquisitionTier =
            CapacityAcquisition.diskOnlySources.contains(source) ? .onDisk : .tuiProbe
        return [
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: source,
                scope: .weekly,
                observedAt: now,
                sourceTier: tier
            ),
        ]
    }

    /// True when every live window for a source is an acquisition failure
    /// (not bare neverSampled / not a successful sample).
    public static func isFailedAttempt(_ windows: [CapacityWindow]) -> Bool {
        guard !windows.isEmpty else { return false }
        return windows.allSatisfy { window in
            switch window.unknownReason {
            case .parserFailed, .spawnFailed, .probeTimeout, .emptyCapture, .vendorExposesNothing:
                return true
            case .neverSampled, .expired, .disabled, .none:
                return false
            }
        }
    }
}
