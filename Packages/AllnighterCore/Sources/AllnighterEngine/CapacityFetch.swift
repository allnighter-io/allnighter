import Foundation
import AllnighterCore

// MARK: - CapacityFetch (CWB-S00)

/// Single live-acquire owner for capacity **display** (Engine).
///
/// - Live PTY only — never hydrates history or disk as painted truth.
/// - `warmPool` reserved for CWB-S01+ (always `nil` in S00).
/// - Mac may keep a process-local memo after successful live fetch (&lt; 30 min).
public enum CapacityFetch {

    /// Process-local memo TTL for Mac strip re-paint within one app session.
    public static let displayMemoTTL: TimeInterval = 30 * 60

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

    private final class MemoStore: @unchecked Sendable {
        private let lock = NSLock()
        private var windows: [CapacityWindow]?
        private var fetchedAt: Date?

        func read(now: Date) -> [CapacityWindow]? {
            lock.lock(); defer { lock.unlock() }
            guard let windows, let fetchedAt else { return nil }
            guard now.timeIntervalSince(fetchedAt) < CapacityFetch.displayMemoTTL else {
                self.windows = nil
                self.fetchedAt = nil
                return nil
            }
            return windows
        }

        func write(_ windows: [CapacityWindow], at now: Date) {
            lock.lock()
            self.windows = windows
            self.fetchedAt = now
            lock.unlock()
        }

        func clear() {
            lock.lock()
            windows = nil
            fetchedAt = nil
            lock.unlock()
        }
    }

    private static let memo = MemoStore()

    /// Launch placeholders — six `neverSampled` rows, no spawn.
    public static func launchPlaceholders(now: Date) -> [CapacityWindow] {
        CapacityAcquisition.windows(homeRoot: placeholderHome, now: now, refresh: false)
    }

    /// Process-local memo when fresh; nil when absent or stale.
    public static func memoIfFresh(now: Date) -> [CapacityWindow]? {
        memo.read(now: now)
    }

    /// Clear memo (tests).
    public static func clearMemo() {
        memo.clear()
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
        updateMemo: Bool = true
    ) -> Snapshot {
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            refreshSource: refreshSource,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout
        )
        try? historyStore.record(windows, now: now)
        if updateMemo, refreshSource == nil {
            memo.write(windows, at: now)
        }
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    /// Mac launch: memo if fresh in this process, else placeholders.
    public static func launchSnapshot(now: Date = Date()) -> Snapshot {
        if let cached = memoIfFresh(now: now) {
            let rows = CapacityBenchProjection.rows(from: cached, now: now)
            return Snapshot(now: now, windows: cached, rows: rows)
        }
        let windows = launchPlaceholders(now: now)
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    private static let placeholderHome = URL(fileURLWithPath: "/var/empty", isDirectory: true)
}
