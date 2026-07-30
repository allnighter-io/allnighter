import Foundation

/// Live-or-last-known merge for the capacity strip (CAP-HF-00).
///
/// Pure: no IO, no clock reads beyond the caller's `now` for open-window filter.
/// Live known samples always win. Unknown live (neverSampled / probe failure)
/// falls back to open history with **original** `observedAt` — never re-stamped.
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
    public static func apply(
        live: [CapacityWindow],
        history: [CapacityWindow],
        now: Date,
        benchOrder: [String] = CapacityAcquisition.benchSourceOrder
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
                now: now
            ))
        }
        return result
    }

    /// Prefer live known → open history known → live unknown → synthetic neverSampled.
    public static func prefer(
        live: [CapacityWindow],
        history: [CapacityWindow],
        source: String,
        now: Date
    ) -> [CapacityWindow] {
        let liveKnown = live.filter { $0.unknownReason == nil }
        if !liveKnown.isEmpty {
            return liveKnown
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

        return [
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: source,
                scope: .weekly,
                observedAt: now,
                sourceTier: CapacityAcquisition.tier3DisklessSources.contains(source)
                    ? .tuiProbe
                    : .onDisk
            ),
        ]
    }
}
