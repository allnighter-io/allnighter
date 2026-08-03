import XCTest
@testable import AllnighterCore
@testable import AllnighterMac
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

    // MARK: - CWB-S00a: strip cancel/supersede terminates acquisition scope

    func testRefreshAllSupersedeTerminatesPriorScope() async throws {
        let model = CapacityStripModel()
        let recorder = KillRecorder()
        let scope = CapacityProbeScope { pid in recorder.record(pid) }
        let blocker = BlockingScopeExecutor(fakePID: 7_000_001, mode: .untilKilled(recorder))

        model.refreshAll(probeExecutor: blocker, probeScope: scope)
        for _ in 0..<200 where !blocker.executed {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(blocker.executed, "first acquire must start")

        // Supersede with a fast full refresh.
        model.refreshAll(probeExecutor: CountingProbeExecutor(), probeScope: CapacityProbeScope())

        for _ in 0..<200 where !recorder.killed.contains(7_000_001) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(
            recorder.killed.contains(7_000_001),
            "superseding full refresh must terminate the prior scope"
        )
        XCTAssertTrue(scope.trackedPIDs.isEmpty, "terminated scope must drain its tracked set")

        for _ in 0..<200 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(model.isRefreshingAll, "new refresh must settle")
    }

    func testRefreshAllSupersedesTargetedScope() async throws {
        let model = CapacityStripModel()
        let recorder = KillRecorder()
        let scope = CapacityProbeScope { pid in recorder.record(pid) }
        let blocker = BlockingScopeExecutor(
            fakePID: 7_000_002,
            mode: .untilKilled(recorder, source: "claude_code")
        )

        model.refreshSource("claude_code", probeExecutor: blocker, probeScope: scope)
        for _ in 0..<200 where !blocker.executed {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(blocker.executed, "targeted acquire must start")
        XCTAssertTrue(model.isRefreshing("claude_code"))

        // Full refresh supersedes the targeted one.
        model.refreshAll(probeExecutor: CountingProbeExecutor(), probeScope: CapacityProbeScope())

        for _ in 0..<200 where !recorder.killed.contains(7_000_002) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(
            recorder.killed.contains(7_000_002),
            "full refresh must terminate the targeted scope"
        )

        for _ in 0..<200 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(model.isRefreshingAll)
        XCTAssertFalse(model.isRefreshing("claude_code"), "targeted spinner must stop")
    }
}

// MARK: - CWB-S00a test helpers

private final class KillRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _killed: [pid_t] = []

    var killed: [pid_t] {
        lock.lock(); defer { lock.unlock() }
        return _killed
    }

    func record(_ pid: pid_t) {
        lock.lock(); _killed.append(pid); lock.unlock()
    }

    func waitForKill(of pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock(); let hit = _killed.contains(pid); lock.unlock()
            if hit { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        lock.lock(); defer { lock.unlock() }
        return _killed.contains(pid)
    }
}

private final class BlockingScopeExecutor: CapacityProbeExecuting, @unchecked Sendable {
    enum Mode {
        case untilKilled(KillRecorder, source: String? = nil)
    }

    let fakePID: pid_t
    let mode: Mode
    private let lock = NSLock()
    private var _executed = false

    var executed: Bool {
        lock.lock(); defer { lock.unlock() }
        return _executed
    }

    init(fakePID: pid_t, mode: Mode) {
        self.fakePID = fakePID
        self.mode = mode
    }

    func waitUntilExecuted(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if executed { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return executed
    }

    func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
        lock.lock(); _executed = true; lock.unlock()
        request.scope?.track(fakePID)
        switch mode {
        case .untilKilled(let recorder, let sourceFilter):
            if let sourceFilter, request.source != sourceFilter { break }
            _ = recorder.waitForKill(of: fakePID, timeout: 15)
        }
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
