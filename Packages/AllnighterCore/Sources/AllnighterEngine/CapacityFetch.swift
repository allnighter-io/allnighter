import Foundation
import AllnighterCore

// MARK: - CapacityFetch (CWB-S00)

/// Single live-acquire owner for capacity **display** (Engine).
///
/// - Live PTY only — never hydrates history or disk as painted truth.
/// - `warmPool` reserved for CWB-S01+ (always `nil` in S00).
/// - Freshness is owned by `CapacityResidentService` (CWB-S01a) — the S00
///   process-local display memo is retired; there is no second clock here.
public enum CapacityFetch {

    public struct Snapshot: Sendable, Equatable {
        public let now: Date
        public let windows: [CapacityWindow]
        public let rows: [CapacityBenchRow]

        public init(now: Date, windows: [CapacityWindow], rows: [CapacityBenchRow]) {
            self.now = now
            self.windows = windows
            self.rows = rows
        }
    }

    /// Launch placeholders — six `neverSampled` rows, no spawn.
    public static func launchPlaceholders(now: Date) -> [CapacityWindow] {
        CapacityAcquisition.windows(homeRoot: placeholderHome, now: now, refresh: false)
    }

    /// Live PTY acquire for all seats or one `--source` seat. Records history for
    /// analytics but **never** hydrates history into the returned windows.
    public static func liveSnapshot(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date = Date(),
        refreshSource: String? = nil,
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout,
        probeScope: CapacityProbeScope? = nil
    ) -> Snapshot {
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            refreshSource: refreshSource,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout,
            probeScope: probeScope
        )
        try? historyStore.record(windows, now: now)
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    /// Mac launch: six never-sampled placeholders. Fresh truth lives in the
    /// resident (`CapacityResidentService.currentSnapshot()`), not here.
    public static func launchSnapshot(now: Date = Date()) -> Snapshot {
        let windows = launchPlaceholders(now: now)
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    private static let placeholderHome = URL(fileURLWithPath: "/var/empty", isDirectory: true)
}
