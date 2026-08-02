import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Launch strip must hydrate instantly then probe — stale history alone is not truth.
@MainActor
final class CapacityStripModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    private final class CountingProbeExecutor: CapacityProbeExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _callCount
        }
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            lock.lock(); _callCount += 1; lock.unlock()
            return [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    private struct FixtureProbeExecutor: CapacityProbeExecuting {
        let results: [String: [CapacityWindow]]
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            results[request.source] ?? [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    func testLoadLiveProbesAfterHydrate() async throws {
        let executor = CountingProbeExecutor()
        let model = CapacityStripModel()
        model.loadLive(probeExecutor: executor)

        for _ in 0..<200 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertGreaterThan(executor.callCount, 0, "launch must probe tier-3 seats, not only hydrate history")
    }

    func testLoadLiveReplacesStaleClaudeHistoryWithFreshProbe() async throws {
        let clock = Date()
        let resetAt = clock.addingTimeInterval(32 * 3600)
        let staleObserved = clock.addingTimeInterval(-7_200)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let historyRoot = tempRoot.appendingPathComponent("capacity", isDirectory: true)
        let store = CapacityHistoryStore(rootDirectory: historyRoot)
        try store.record([
            CapacityWindow(
                used: 18,
                source: "claude_code",
                scope: .weekly,
                resetAt: resetAt,
                resetPrecision: .exact,
                observedAt: staleObserved,
                sourceTier: .tuiProbe,
                planTier: "Max"
            ),
        ], now: clock)

        let home = tempRoot.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let freshObserved = clock
        let probeExecutor = FixtureProbeExecutor(results: [
            "claude_code": [
                CapacityWindow(
                    used: 96,
                    source: "claude_code",
                    scope: .weekly,
                    resetAt: resetAt,
                    resetPrecision: .exact,
                    observedAt: freshObserved,
                    sourceTier: .tuiProbe,
                    planTier: "Max"
                ),
            ],
        ])

        let model = CapacityStripModel()
        model.loadLive(
            homeRoot: home,
            historyStore: store,
            probeExecutor: probeExecutor,
            autoRefresh: false
        )

        let hydratedWindow = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        let hydratedUsed = try XCTUnwrap(hydratedWindow.usedPercent)
        XCTAssertEqual(hydratedUsed, 18, accuracy: 0.5)

        model.refreshAll(homeRoot: home, historyStore: store, probeExecutor: probeExecutor)

        for _ in 0..<200 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let refreshedWindow = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        let refreshedUsed = try XCTUnwrap(refreshedWindow.usedPercent)
        XCTAssertEqual(refreshedUsed, 96, accuracy: 0.5)
        XCTAssertEqual(refreshedWindow.resetAt, resetAt)
    }

    func testLoadLiveSkipsAutoRefreshWhenDisabled() async throws {
        let executor = CountingProbeExecutor()
        let model = CapacityStripModel()
        model.loadLive(probeExecutor: executor, autoRefresh: false)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(executor.callCount, 0)
        XCTAssertFalse(model.isRefreshingAll)
    }
}
