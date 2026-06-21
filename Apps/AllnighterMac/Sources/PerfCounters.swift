import Foundation
import os

/// Lightweight, test-assertable performance counters for the thread streaming hot path.
/// A dictionary bump on the main actor — negligible cost — so PERF tests can PROVE the
/// invariants (no full reload per delta, no thread.json write per delta) with numbers
/// instead of eyeballing smoothness. Pairs with `os_signpost` for Instruments traces.
@MainActor
enum PerfCounters {
    enum Key: String, CaseIterable {
        /// `reload()` actually ran — a full `ThreadStore.list()` decode + publish.
        case threadsReload
        /// A durable `thread.json` write (a streaming checkpoint or settlement).
        case threadJSONWrite
        /// A live streaming delta merged into the published `threads` in memory (no disk).
        case liveDeltaApplied
        /// `requestReload()` was called.
        case reloadRequested
        /// `requestReload()` folded into an already-scheduled flush (coalesced away).
        case reloadCoalesced
    }

    private static var counts: [String: Int] = [:]

    static func bump(_ key: Key) { counts[key.rawValue, default: 0] += 1 }
    static func value(_ key: Key) -> Int { counts[key.rawValue] ?? 0 }
    static func reset() { counts.removeAll() }

    /// Instruments signpost handle (used at the call sites that matter for traces).
    static let log = OSLog(subsystem: "com.allnighter.mac", category: "perf")
}
