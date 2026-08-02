import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Founder law 2026-08-02: Mac strip never paints history % — only live acquire.
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

    func testUntrustedPlaceholdersHaveNoPercentages() {
        let windows = CapacityStripModel.untrustedPlaceholders(now: Date())
        XCTAssertEqual(windows.count, CapacityAcquisition.benchSourceOrder.count)
        for window in windows {
            XCTAssertNotNil(window.unknownReason)
            XCTAssertNil(window.usedPercent)
            XCTAssertNil(window.remainingPercent)
        }
    }

    func testLoadLiveNeverPaintsStaleHistoryPercentages() async throws {
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

        let model = CapacityStripModel()
        model.loadLive(
            homeRoot: home,
            historyStore: store,
            probeExecutor: CountingProbeExecutor(),
            autoRefresh: false
        )

        let claude = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        XCTAssertNil(claude.usedPercent, "launch must not paint last-known 82% remaining")
        XCTAssertEqual(claude.unknownReason, .neverSampled)
    }

    func testLoadLiveAlwaysRefreshesOffMainPath() async throws {
        let executor = CountingProbeExecutor()
        let model = CapacityStripModel()
        model.loadLive(probeExecutor: executor)

        XCTAssertTrue(model.isRefreshingAll || executor.callCount > 0 || model.windows.allSatisfy { $0.unknownReason != nil })

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertGreaterThan(executor.callCount, 0, "launch must probe live — never trust history alone")
        XCTAssertFalse(model.isRefreshingAll)
    }

    func testRefreshAllReplacesWithLiveProbeNotHistory() async throws {
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
        model.loadLive(
            homeRoot: home,
            historyStore: store,
            probeExecutor: probeExecutor,
            autoRefresh: false
        )
        model.refreshAll(homeRoot: home, historyStore: store, probeExecutor: probeExecutor)

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let refreshed = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        let used = try XCTUnwrap(refreshed.usedPercent)
        XCTAssertEqual(used, 96, accuracy: 0.5)
        XCTAssertNotEqual(used, 18, "must not fall back to history 18% used / 82% rem")
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

        let home = tempRoot.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let model = CapacityStripModel()
        model.refreshAll(
            homeRoot: home,
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

    func testLoadLiveSkipsAutoRefreshWhenDisabled() async throws {
        let executor = CountingProbeExecutor()
        let model = CapacityStripModel()
        model.loadLive(probeExecutor: executor, autoRefresh: false)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(executor.callCount, 0)
        XCTAssertFalse(model.isRefreshingAll)
    }
}
