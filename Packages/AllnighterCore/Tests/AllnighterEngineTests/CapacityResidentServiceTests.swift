import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

// MARK: - Shared fakes (CWB-S01a)

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); current += interval; lock.unlock()
    }
}

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
}

private final class FetchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _starts: [(source: String?, at: Date)] = []
    private var _gateOpen = false

    var starts: [(source: String?, at: Date)] {
        lock.lock(); defer { lock.unlock() }
        return _starts
    }

    var startCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _starts.count
    }

    var gateOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return _gateOpen
    }

    func recordStart(source: String?, at now: Date) {
        lock.lock(); _starts.append((source, now)); lock.unlock()
    }

    func openGate() {
        lock.lock(); _gateOpen = true; lock.unlock()
    }

    /// Busy-wait (short sleeps) until the gate opens. Runs inside the detached
    /// generation task, never on the resident actor.
    func waitForGate() async {
        while !gateOpen {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private func knownWindow(source: String, used: Double, at now: Date) -> CapacityWindow {
    CapacityWindow(
        used: used,
        source: source,
        scope: .weekly,
        resetAt: now.addingTimeInterval(3_600),
        resetPrecision: .exact,
        observedAt: now,
        sourceTier: .tuiProbe
    )
}

private func failedWindow(source: String, at now: Date) -> CapacityWindow {
    CapacityWindow.unknown(
        reason: .parserFailed(observedAt: now),
        source: source,
        scope: .weekly,
        observedAt: now,
        sourceTier: .tuiProbe
    )
}

private func snapshot(now: Date, windows: [CapacityWindow]) -> CapacityFetch.Snapshot {
    CapacityFetch.Snapshot(
        now: now,
        windows: windows,
        rows: CapacityBenchProjection.rows(from: windows, now: now)
    )
}

private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 10,
    _ predicate: @escaping @Sendable () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() {
        if Date() > deadline {
            XCTFail("timed out waiting for: \(description)")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - CapacitySingleFlight (CWB-S01a)

final class CapacitySingleFlightTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_753_833_600)

    private func makeResident(
        clock: FakeClock,
        recorder: FetchRecorder,
        killRecorder: KillRecorder? = nil,
        fetch: @escaping CapacityResidentService.Fetch
    ) -> CapacityResidentService {
        CapacityResidentService(
            now: { clock.now() },
            sleep: { interval in
                clock.advance(by: interval)
                await Task.yield()
            },
            makeScope: {
                if let killRecorder {
                    return CapacityProbeScope { pid in killRecorder.record(pid) }
                }
                return CapacityProbeScope()
            },
            fetch: fetch
        )
    }

    /// Six-seat full-bench fetch, optionally gated.
    private func fullBenchFetch(
        clock: FakeClock,
        recorder: FetchRecorder,
        gated: Bool = false
    ) -> CapacityResidentService.Fetch {
        { source, _ in
            recorder.recordStart(source: source, at: clock.now())
            if gated { await recorder.waitForGate() }
            let now = clock.now()
            let windows = CapacityAcquisition.benchSourceOrder.map {
                knownWindow(source: $0, used: 42, at: now)
            }
            return snapshot(now: now, windows: windows)
        }
    }

    func testConcurrentFullRequestsCoalesce() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(
            clock: clock,
            recorder: recorder,
            fetch: fullBenchFetch(clock: clock, recorder: recorder, gated: true)
        )

        let tasks = (0..<4).map { _ in
            Task { await resident.requestRefresh(reason: .userRefresh) }
        }
        try await waitUntil("first generation started") { recorder.startCount == 1 }
        // Give any would-be second generation a chance to start.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(recorder.startCount, 1, "concurrent waiters must coalesce, not start again")

        recorder.openGate()
        let results = await withTaskGroup(of: CapacityFetch.Snapshot.self) { group in
            for task in tasks { group.addTask { await task.value } }
            var collected: [CapacityFetch.Snapshot] = []
            for await result in group { collected.append(result) }
            return collected
        }
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(recorder.startCount, 1, "still one in-flight generation")
        for result in results {
            XCTAssertEqual(result.windows.count, CapacityAcquisition.benchSourceOrder.count)
            XCTAssertEqual(result.now, t0, "coalesced waiters share the generation's settle time")
        }
        let settled = await resident.currentSnapshot()
        XCTAssertEqual(settled?.settledAt, t0)
        XCTAssertEqual(settled?.windows.count, CapacityAcquisition.benchSourceOrder.count)
    }

    func testFullSupersedesTargetedWithScopedTerminate() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let kills = KillRecorder()
        let fakePID: pid_t = 7_100_001

        let resident = makeResident(clock: clock, recorder: recorder, killRecorder: kills) { source, scope in
            recorder.recordStart(source: source, at: clock.now())
            if source == "grok" {
                // Targeted acquire blocks until its scope is terminated.
                scope.track(fakePID)
                while !kills.killed.contains(fakePID) {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                let now = clock.now()
                return snapshot(now: now, windows: [failedWindow(source: "grok", at: now)])
            }
            let now = clock.now()
            let windows = CapacityAcquisition.benchSourceOrder.map {
                knownWindow(source: $0, used: 42, at: now)
            }
            return snapshot(now: now, windows: windows)
        }

        let targetedTask = Task { await resident.requestRefresh(reason: .userRefreshSeat("grok")) }
        try await waitUntil("targeted acquire started") {
            recorder.starts.contains { $0.source == "grok" }
        }

        let fullTask = Task { await resident.requestRefresh(reason: .userRefresh) }
        try await waitUntil("targeted scope terminated") { kills.killed.contains(fakePID) }
        XCTAssertTrue(kills.killed.contains(fakePID), "full bench must scoped-terminate the targeted generation")

        let fullResult = await fullTask.value
        let targetedResult = await targetedTask.value

        XCTAssertEqual(fullResult.windows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertEqual(
            targetedResult.windows, fullResult.windows,
            "superseded waiter is redirected to the newer truth, never the killed partial"
        )
        XCTAssertFalse(
            targetedResult.windows.contains { $0.unknownReason != nil },
            "killed generation's failed windows must never be painted"
        )
        let settled = await resident.currentSnapshot()
        XCTAssertEqual(settled?.windows, fullResult.windows)
    }

    func testTargetedDifferentSeatWaitsForSettleThenStarts() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(clock: clock, recorder: recorder) { source, _ in
            recorder.recordStart(source: source, at: clock.now())
            let now = clock.now()
            guard let source else {
                return snapshot(now: now, windows: [])
            }
            return snapshot(now: now, windows: [knownWindow(source: source, used: 10, at: now)])
        }

        async let grokResult = resident.requestRefresh(reason: .userRefreshSeat("grok"))
        try await waitUntil("grok acquire started") {
            recorder.starts.contains { $0.source == "grok" }
        }
        async let kimiResult = resident.requestRefresh(reason: .userRefreshSeat("kimi"))

        let grok = await grokResult
        let kimi = await kimiResult

        XCTAssertEqual(recorder.startCount, 2, "sequential seat refreshes — never concurrent")
        let grokStart = try XCTUnwrap(recorder.starts.first { $0.source == "grok" }?.at)
        let kimiStart = try XCTUnwrap(recorder.starts.first { $0.source == "kimi" }?.at)
        XCTAssertEqual(
            kimiStart.timeIntervalSince(grokStart), 120, accuracy: 0.5,
            "second seat starts only after the floor (fake clock advanced by injected sleep)"
        )
        XCTAssertEqual(grok.windows.filter { $0.source == "grok" }.count, 1)
        // Kimi's merged snapshot keeps grok's fresh windows (latest attempt wins per seat).
        XCTAssertEqual(kimi.windows.first { $0.source == "grok" }?.usedPercent, 10)
        XCTAssertEqual(kimi.windows.first { $0.source == "kimi" }?.usedPercent, 10)
    }

    func testFloorBetweenAcquireStarts() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(
            clock: clock,
            recorder: recorder,
            fetch: fullBenchFetch(clock: clock, recorder: recorder)
        )

        _ = await resident.requestRefresh(reason: .userRefresh)
        _ = await resident.requestRefresh(reason: .userRefresh)

        XCTAssertEqual(recorder.startCount, 2, "settled generations do not coalesce")
        let first = try XCTUnwrap(recorder.starts.first?.at)
        let second = try XCTUnwrap(recorder.starts.last?.at)
        XCTAssertEqual(
            second.timeIntervalSince(first), 120, accuracy: 0.5,
            "2-minute floor between acquire starts (all reasons)"
        )
    }

    func testPostRunIsTargetedAndWakeIsFull() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(clock: clock, recorder: recorder) { source, _ in
            recorder.recordStart(source: source, at: clock.now())
            let now = clock.now()
            if let source {
                return snapshot(now: now, windows: [knownWindow(source: source, used: 5, at: now)])
            }
            return snapshot(
                now: now,
                windows: CapacityAcquisition.benchSourceOrder.map { knownWindow(source: $0, used: 5, at: now) }
            )
        }

        _ = await resident.requestRefresh(reason: .postRun(source: "codex"))
        _ = await resident.requestRefresh(reason: .wake)

        XCTAssertEqual(recorder.starts.map { $0.source }, ["codex", nil])
        let settled = await resident.currentSnapshot()
        XCTAssertEqual(settled?.windows.count, CapacityAcquisition.benchSourceOrder.count)
    }
}

// MARK: - CapacityPaintGate (CWB-S01a)

final class CapacityPaintGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_753_833_600)

    func testConstantIsThirtyMinutes() {
        XCTAssertEqual(CapacityPaintGate.gateInterval, 30 * 60)
    }

    func testAge29m59sPaints() {
        let windows = [knownWindow(source: "grok", used: 42, at: t0)]
        let painted = CapacityPaintGate.paintedWindows(
            windows, settledAt: t0, now: t0.addingTimeInterval(29 * 60 + 59)
        )
        XCTAssertEqual(painted, windows)
        XCTAssertEqual(painted.first?.usedPercent, 42)
    }

    func testAge30m00sExpiresKnownSeats() {
        let known = knownWindow(source: "grok", used: 42, at: t0)
        let neverSampled = CapacityWindow.unknown(
            reason: .neverSampled,
            source: "kimi",
            scope: .weekly,
            observedAt: t0,
            sourceTier: .tuiProbe
        )
        let painted = CapacityPaintGate.paintedWindows(
            [known, neverSampled], settledAt: t0, now: t0.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(painted.count, 2)
        XCTAssertNil(painted[0].usedPercent, "expired seat must not paint a percentage")
        XCTAssertEqual(painted[0].unknownReason, .expired(observedAt: t0))
        XCTAssertEqual(painted[0].observedAt, t0, "original sample time preserved for age labels")
        XCTAssertEqual(
            painted[1].unknownReason, .neverSampled,
            "already-unknown seats keep their honest reason"
        )
    }

    func testFailedAttemptSeatStaysUnknownWithinGate() {
        let windows = [
            knownWindow(source: "grok", used: 42, at: t0),
            failedWindow(source: "claude_code", at: t0),
        ]
        let painted = CapacityPaintGate.paintedWindows(
            windows, settledAt: t0, now: t0.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(painted[0].usedPercent, 42)
        XCTAssertNil(painted[1].usedPercent, "failed attempt paints unknown, never a number")
        XCTAssertNotNil(painted[1].unknownReason)
    }

    func testResidentFailedAttemptPaintsSeatUnknown() async throws {
        let clock = FakeClock(t0)
        let resident = CapacityResidentService(
            now: { clock.now() },
            sleep: { _ in },
            fetch: { _, _ in
                let now = clock.now()
                var windows = CapacityAcquisition.benchSourceOrder
                    .filter { $0 != "claude_code" }
                    .map { knownWindow(source: $0, used: 42, at: now) }
                windows.append(failedWindow(source: "claude_code", at: now))
                return snapshot(now: now, windows: windows)
            }
        )

        _ = await resident.requestRefresh(reason: .launch)
        let settled = await resident.currentSnapshot()
        let claude = try XCTUnwrap(settled?.windows.first { $0.source == "claude_code" })
        XCTAssertNil(claude.usedPercent, "latest attempt failed → that seat unknown")
        XCTAssertNotNil(claude.unknownReason)
        let grok = try XCTUnwrap(settled?.windows.first { $0.source == "grok" })
        XCTAssertEqual(grok.usedPercent, 42)

        // Within the gate the snapshot still paints the failed seat as unknown;
        // past the gate every known seat expires.
        let within = CapacityPaintGate.paintedWindows(
            settled!.windows, settledAt: settled!.settledAt, now: t0.addingTimeInterval(29 * 60 + 59)
        )
        XCTAssertNotNil(within.first { $0.source == "claude_code" }?.unknownReason)
        let past = CapacityPaintGate.paintedWindows(
            settled!.windows, settledAt: settled!.settledAt, now: t0.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(past.first { $0.source == "grok" }?.unknownReason, .expired(observedAt: t0))
        XCTAssertNotNil(past.first { $0.source == "claude_code" }?.unknownReason)
    }
}
