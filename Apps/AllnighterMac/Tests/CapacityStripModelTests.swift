import XCTest
@testable import AllnighterCore
import AllnighterEngine

@MainActor
final class CapacityStripModelTests: XCTestCase {

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

    override func tearDown() {
        CapacityFetch.clearMemo()
        super.tearDown()
    }

    func testLoadLiveShowsPlaceholdersNotHistory() async throws {
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

        let executor = CountingProbeExecutor()
        let model = CapacityStripModel()
        model.loadLive(historyStore: store, probeExecutor: executor)

        XCTAssertTrue(model.needsLiveRefresh)
        XCTAssertEqual(executor.callCount, 0, "launch must not probe")
        let claude = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        XCTAssertEqual(claude.unknownReason, .neverSampled)
        XCTAssertNil(claude.usedPercent, "must not paint history on launch")
    }

    func testLoadLiveDoesNotProbe() {
        let executor = CountingProbeExecutor()
        let model = CapacityStripModel()
        model.loadLive(probeExecutor: executor)
        XCTAssertEqual(executor.callCount, 0)
        XCTAssertFalse(model.isRefreshingAll)
        XCTAssertTrue(model.needsLiveRefresh)
    }

    func testRefreshAllReplacesWithLiveProbe() async throws {
        let clock = Date()
        let resetAt = clock.addingTimeInterval(32 * 3600)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let historyRoot = tempRoot.appendingPathComponent("capacity", isDirectory: true)
        let store = CapacityHistoryStore(rootDirectory: historyRoot)

        let probeExecutor = FixtureProbeExecutor(results: [
            "claude_code": [
                CapacityWindow(
                    used: 96,
                    source: "claude_code",
                    scope: .weekly,
                    resetAt: resetAt,
                    resetPrecision: .exact,
                    observedAt: clock,
                    sourceTier: .tuiProbe,
                    planTier: "Max"
                ),
            ],
        ])

        let model = CapacityStripModel()
        model.loadLive(historyStore: store, probeExecutor: probeExecutor)
        model.refreshAll(historyStore: store, probeExecutor: probeExecutor)

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let refreshed = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        let used = try XCTUnwrap(refreshed.usedPercent)
        XCTAssertEqual(used, 96, accuracy: 0.5)
        XCTAssertFalse(model.needsLiveRefresh)
    }

    func testFailedLiveProbeDoesNotHydrateHistory() async throws {
        let clock = Date()
        let resetAt = clock.addingTimeInterval(32 * 3600)

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
                observedAt: clock.addingTimeInterval(-7_200),
                sourceTier: .tuiProbe,
                planTier: "Max"
            ),
        ], now: clock)

        let model = CapacityStripModel()
        model.refreshAll(
            historyStore: store,
            probeExecutor: CountingProbeExecutor()
        )

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let claude = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        XCTAssertNil(claude.usedPercent, "failed probe must show unknown, never history %")
        XCTAssertNotNil(claude.unknownReason)
    }

    func testCapacityFetchMatchesSixRowBench() {
        let clock = Date()
        let bench = CapacityFetch.launchSnapshot(now: clock)
        XCTAssertEqual(bench.rows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertEqual(bench.now, clock)
    }
}
