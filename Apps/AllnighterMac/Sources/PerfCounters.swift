import Foundation
import os

/// Lightweight, test-assertable performance counters for the thread streaming hot path.
/// A dictionary bump on the main actor — negligible cost — so PERF tests can PROVE the
/// invariants (no full reload per delta, no thread.json write per delta) with numbers
/// instead of eyeballing smoothness. Pairs with `os_signpost` for Instruments traces.
@MainActor
enum PerfCounters {
    enum Key: String, CaseIterable {
        /// A full-list publish landed — `ThreadStore.list()` decode + MainActor snapshot.
        case threadsReload
        /// A durable `thread.json` write (a streaming checkpoint or settlement).
        case threadJSONWrite
        /// A live streaming delta merged into the published `threads` in memory (no disk).
        case liveDeltaApplied
        /// `requestReload()` was called.
        case reloadRequested
        /// `requestReload()` folded into an already-scheduled flush (coalesced away).
        case reloadCoalesced
        /// Background list finished but a newer generation (live delta / newer reload)
        /// already owns published state — stale snapshot discarded (PERF-S04b).
        case reloadPublishDiscarded
        /// `ThreadStore.list()` ran off the MainActor (PERF-S04b).
        case threadStoreListOffMain
        /// A terminal `run.json` decode via `teamRun(forRunId:)` (cache miss).
        case runJSONDecode
        /// A terminal settlement write FAILED (RLS-S01) — a product failure, surfaced
        /// instead of swallowed, so a completed run never silently stays `running`.
        case settlementError
    }

    private static var counts: [String: Int] = [:]

    static func bump(_ key: Key) { counts[key.rawValue, default: 0] += 1 }
    static func value(_ key: Key) -> Int { counts[key.rawValue] ?? 0 }
    static func reset() { counts.removeAll() }

    /// Instruments signpost handle (used at the call sites that matter for traces).
    static let log = OSLog(subsystem: "com.allnighter.mac", category: "perf")
}
