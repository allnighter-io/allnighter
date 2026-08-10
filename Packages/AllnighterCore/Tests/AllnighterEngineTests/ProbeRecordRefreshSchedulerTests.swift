import XCTest
@testable import AllnighterEngine
@testable import AllnighterCore

final class ProbeRecordRefreshSchedulerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

    private func staleRecord(id: String = "claude_code") -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: id,
            status: .ready(version: "1"),
            lastProbeAt: t0.addingTimeInterval(-ProbeFreshnessGate.gateInterval - 1))
    }

    private func freshRecord(id: String = "claude_code") -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: id,
            status: .ready(version: "1"),
            lastProbeAt: t0.addingTimeInterval(-60))
    }

    private func scheduler(
        records: @escaping @Sendable () -> [ToolProbeRecord] = { [] },
        parked: @escaping @Sendable () -> Set<String> = { [] },
        smoke: @escaping @Sendable () async -> Void = {},
        sleeper: any PendingWakeSleeper = ImmediateSleeper()
    ) -> ProbeRecordRefreshScheduler {
        ProbeRecordRefreshScheduler(
            recordLoader: records,
            parkedLoader: parked,
            smoke: smoke,
            now: { [t0] in t0 },
            sleeper: sleeper
        )
    }

    // MARK: - shouldSmoke

    func testShouldSmokeTrueWhenRecordsEmpty() {
        let s = scheduler()
        XCTAssertTrue(s.shouldSmoke(records: [], now: t0, parked: []))
    }

    func testShouldSmokeTrueWhenStale() {
        let s = scheduler()
        XCTAssertTrue(s.shouldSmoke(records: [staleRecord()], now: t0, parked: []))
    }

    func testShouldSmokeFalseWhenAllFresh() {
        let s = scheduler()
        XCTAssertFalse(s.shouldSmoke(records: [freshRecord()], now: t0, parked: []))
    }

    func testShouldSmokeFalseWhenOnlyParkedRecordStale() {
        let s = scheduler()
        let records = [staleRecord(id: "parked_cli"), freshRecord(id: "claude_code")]
        XCTAssertFalse(s.shouldSmoke(records: records, now: t0, parked: ["parked_cli"]))
    }

    func testShouldSmokeTrueWhenAllNonParkedIsEmpty() {
        let s = scheduler()
        let records = [freshRecord(id: "parked_cli")]
        XCTAssertTrue(s.shouldSmoke(records: records, now: t0, parked: ["parked_cli"]))
    }

    func testShouldSmokeBoundaryAtGateInterval() {
        let exact = t0.addingTimeInterval(-ProbeFreshnessGate.gateInterval)
        let records = [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: exact)]
        let s = scheduler()
        XCTAssertTrue(s.shouldSmoke(records: records, now: t0, parked: []))
    }

    func testShouldSmokeBoundaryOneSecondInside() {
        let inside = t0.addingTimeInterval(-ProbeFreshnessGate.gateInterval + 1)
        let records = [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: inside)]
        let s = scheduler()
        XCTAssertFalse(s.shouldSmoke(records: records, now: t0, parked: []))
    }

    func testShouldSmokeTrueWhenMixedStaleAndFresh() {
        let s = scheduler()
        let records = [staleRecord(id: "claude_code"), freshRecord(id: "codex")]
        XCTAssertTrue(s.shouldSmoke(records: records, now: t0, parked: []))
    }

    // MARK: - run loop

    func testRunInvokesSmokeWhenRecordsStale() async {
        let smokeCount = Counter()
        let rec = staleRecord()
        let s = scheduler(
            records: { [rec] },
            smoke: { smokeCount.increment() }
        )
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 4 }
        XCTAssertGreaterThan(smokeCount.value, 0, "smoke must be called when records are stale")
    }

    func testRunDoesNotInvokeSmokeWhenRecordsFresh() async {
        let smokeCount = Counter()
        let rec = freshRecord()
        let s = scheduler(
            records: { [rec] },
            smoke: { smokeCount.increment() }
        )
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 4 }
        XCTAssertEqual(smokeCount.value, 0, "smoke must not be called when records are fresh")
    }

    func testCancelStopsLoop() async {
        let s = scheduler()
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 4 }
        // 5 ticks: 4 checks + 1 that triggers the > 4 exit
        XCTAssertEqual(ticks.value, 5)
    }

    func testSmokeIsInjectedNeverLiveVendor() async {
        let smokeCount = Counter()
        let rec = staleRecord()
        let s = scheduler(
            records: { [rec] },
            smoke: { smokeCount.increment() }
        )
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 3 }
        XCTAssertGreaterThan(smokeCount.value, 0)
    }

    // MARK: - ProbeFreshnessGate contract

    func testGateIntervalIs30Minutes() {
        XCTAssertEqual(ProbeFreshnessGate.gateInterval, 30 * 60)
    }
}

// MARK: - Helpers

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private struct ImmediateSleeper: PendingWakeSleeper {
    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {}
}
