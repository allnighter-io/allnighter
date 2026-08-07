import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

// MARK: - Shared fakes (CWB-S01a)

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var mono: TimeInterval

    init(_ start: Date) {
        current = start
        mono = start.timeIntervalSince1970
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Monotonic seconds — same origin as `now`, but only `advance` moves it.
    func monotonicNow() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return mono
    }

    /// Advance wall + monotonic together (normal time passing).
    func advance(by interval: TimeInterval) {
        lock.lock(); current += interval; mono += interval; lock.unlock()
    }

    /// Advance wall only — a machine sleep / clock jump the monotonic clock
    /// did not see (wake classification input).
    func advanceWall(by interval: TimeInterval) {
        lock.lock(); current += interval; lock.unlock()
    }
}

/// Budgeted fake sleep for scheduler tests: advances the fake clock only while
/// the test-granted budget lasts, then blocks (cancellation-aware) until more
/// budget is added. Prevents the rearmed scheduler loop from free-running the
/// fake clock to infinity in one hot loop.
private final class FakeSleep: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: FakeClock
    private var budget: TimeInterval = 0
    private var _blocked = false

    init(clock: FakeClock) { self.clock = clock }

    /// True while a sleep call is parked waiting for more budget.
    var blocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return _blocked
    }

    func addBudget(_ interval: TimeInterval) {
        lock.lock(); budget += interval; lock.unlock()
    }

    func sleep(_ interval: TimeInterval) async {
        var remaining = interval
        while remaining > 0 {
            if Task.isCancelled { return }
            let step = takeStep(upTo: remaining)
            if step > 0 {
                clock.advance(by: step)
                remaining -= step
            }
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        clearBlocked()
    }

    /// Sync helper — NSLock is unavailable directly in async contexts.
    private func clearBlocked() {
        lock.lock(); _blocked = false; lock.unlock()
    }

    /// Sync helper — NSLock is unavailable directly in async contexts.
    private func takeStep(upTo remaining: TimeInterval) -> TimeInterval {
        lock.lock()
        let step = min(remaining, budget)
        budget -= step
        if step < remaining { _blocked = true }
        lock.unlock()
        return step
    }
}

/// Spy for the App Nap activity controller (CWB-S01b): records every begin
/// reason and end so tests can prove leases balance.
private final class ActivitySpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _begins: [String] = []
    private var _ends = 0

    var begins: [String] {
        lock.lock(); defer { lock.unlock() }
        return _begins
    }

    var endCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _ends
    }

    /// Activities begun but not yet ended — must be 1 while a wait is held and
    /// 0 after every fire / OFF / cancel.
    var outstanding: Int {
        lock.lock(); defer { lock.unlock() }
        return _begins.count - _ends
    }

    var controller: CapacityActivityController {
        CapacityActivityController(
            begin: { reason in
                self.lock.lock(); self._begins.append(reason); self.lock.unlock()
                return reason as NSString
            },
            end: { _ in
                self.lock.lock(); self._ends += 1; self.lock.unlock()
            }
        )
    }
}

/// Records scheduler fire reasons (`.deadline` / `.wake`) in order.
private final class FireRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _fires: [CapacityResidentService.RefreshReason] = []

    var fires: [CapacityResidentService.RefreshReason] {
        lock.lock(); defer { lock.unlock() }
        return _fires
    }

    func record(_ reason: CapacityResidentService.RefreshReason) {
        lock.lock(); _fires.append(reason); lock.unlock()
    }
}

/// Records persisted ON/OFF writes.
private final class PersistRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _writes: [Bool] = []

    var writes: [Bool] {
        lock.lock(); defer { lock.unlock() }
        return _writes
    }

    func record(_ enabled: Bool) {
        lock.lock(); _writes.append(enabled); lock.unlock()
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

    func testLiveExpiryClearsTheScheduleCadence() {
        XCTAssertGreaterThan(
            CapacityPaintGate.liveExpiryInterval,
            CapacityPaintGate.gateInterval,
            "an open strip repaints on a timer; with no margin over the schedule "
            + "cadence a healthy bench blanks for the length of every acquire"
        )
    }

    func testOpenWindowRepaintAgesEachSeatOnItsOwnObservation() {
        let fresh = knownWindow(source: "grok", used: 42, at: t0.addingTimeInterval(50 * 60))
        let stale = knownWindow(source: "codex", used: 17, at: t0)
        let painted = CapacityPaintGate.repaintedForOpenWindow(
            [fresh, stale], now: t0.addingTimeInterval(50 * 60)
        )
        XCTAssertEqual(painted[0].usedPercent, 42, "seat sampled just now stays known")
        XCTAssertNil(painted[1].usedPercent, "a sibling's refresh must not revive a stale seat")
        XCTAssertEqual(painted[1].unknownReason, .expired(observedAt: t0))
        XCTAssertEqual(painted[1].observedAt, t0, "age labels stay honest after expiry")
    }

    func testOpenWindowRepaintKeepsSeatsInsideTheExpiry() {
        let windows = [knownWindow(source: "grok", used: 42, at: t0)]
        let painted = CapacityPaintGate.repaintedForOpenWindow(
            windows, now: t0.addingTimeInterval(CapacityPaintGate.liveExpiryInterval - 1)
        )
        XCTAssertEqual(painted, windows)
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

// MARK: - Scheduler test helpers (CWB-S01b)

/// Resident wired for scheduler tests: fake wall + monotonic clock, budgeted
/// fake sleep, activity spy, fire/persist recorders, and a zero acquire floor
/// (the floor is proven by `CapacitySingleFlightTests`; scheduler tests budget
/// fake time instead).
private func makeSchedulerResident(
    clock: FakeClock,
    fakeSleep: FakeSleep,
    activity: ActivitySpy,
    fires: FireRecorder,
    persisted: PersistRecorder,
    fetch: @escaping CapacityResidentService.Fetch
) -> CapacityResidentService {
    CapacityResidentService(
        now: { clock.now() },
        sleep: { interval in await fakeSleep.sleep(interval) },
        monotonicNow: { clock.monotonicNow() },
        activities: activity.controller,
        acquireFloor: 0,
        persistEnabled: { enabled in persisted.record(enabled) },
        onSchedulerFire: { reason in fires.record(reason) },
        fetch: fetch
    )
}

/// Instant six-seat full-bench fetch.
private func instantFullBenchFetch(
    clock: FakeClock,
    recorder: FetchRecorder
) -> CapacityResidentService.Fetch {
    { source, _ in
        recorder.recordStart(source: source, at: clock.now())
        let now = clock.now()
        let windows = CapacityAcquisition.benchSourceOrder.map {
            knownWindow(source: $0, used: 42, at: now)
        }
        return snapshot(now: now, windows: windows)
    }
}

// MARK: - CapacityResidentDeadline (CWB-S01b)

final class CapacityResidentDeadlineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_753_833_600)

    /// Deadline fires 30m after the last **settle**, never after fire alone:
    /// the fetch takes 5 fake minutes, so the second deadline lands 35m after
    /// the first fire — not 30m.
    func testDeadlineFiresAfterIntervalAndRearmsAfterSettle() async throws {
        let clock = FakeClock(t0)
        let fakeSleep = FakeSleep(clock: clock)
        let recorder = FetchRecorder()
        let activity = ActivitySpy()
        let fires = FireRecorder()
        let persisted = PersistRecorder()
        let resident = makeSchedulerResident(
            clock: clock, fakeSleep: fakeSleep, activity: activity,
            fires: fires, persisted: persisted
        ) { source, _ in
            recorder.recordStart(source: source, at: clock.now())
            clock.advance(by: 5 * 60)   // slow bench: settle lands 5m after start
            let now = clock.now()
            let windows = CapacityAcquisition.benchSourceOrder.map {
                knownWindow(source: $0, used: 42, at: now)
            }
            return snapshot(now: now, windows: windows)
        }

        await resident.setEnabled(true)
        try await waitUntil("silent launch acquire") { recorder.startCount == 1 }

        fakeSleep.addBudget(35 * 60)
        try await waitUntil("first deadline fire") { recorder.startCount == 2 }
        XCTAssertEqual(fires.fires, [.deadline])
        XCTAssertEqual(
            recorder.starts[1].at, t0.addingTimeInterval(35 * 60),
            "deadline = launch settle (t0+5m) + 30m"
        )
        XCTAssertEqual(activity.outstanding, 1, "activity still held across the next wait")

        fakeSleep.addBudget(25 * 60)
        try await waitUntil("second deadline fire") { recorder.startCount == 3 }
        XCTAssertEqual(fires.fires, [.deadline, .deadline])
        XCTAssertEqual(
            recorder.starts[2].at, t0.addingTimeInterval(70 * 60),
            "rearmed from settle (t0+40m) + 30m — rearm-from-fire would give t0+65m"
        )
        XCTAssertEqual(activity.begins.count, 3, "one activity per deadline wait")
        XCTAssertEqual(activity.begins, Array(repeating: "Allnighter capacity deadline wait", count: 3))
        XCTAssertEqual(activity.outstanding, 1)

        await resident.setEnabled(false)
    }

    /// The App Nap activity is held for the whole wait and always ended —
    /// including feature OFF mid-wait.
    func testActivityHeldAcrossWaitAndReleasedOnFeatureOff() async throws {
        let clock = FakeClock(t0)
        let fakeSleep = FakeSleep(clock: clock)
        let recorder = FetchRecorder()
        let activity = ActivitySpy()
        let fires = FireRecorder()
        let persisted = PersistRecorder()
        let resident = makeSchedulerResident(
            clock: clock, fakeSleep: fakeSleep, activity: activity,
            fires: fires, persisted: persisted,
            fetch: instantFullBenchFetch(clock: clock, recorder: recorder)
        )

        await resident.setEnabled(true)
        try await waitUntil("silent launch acquire") { recorder.startCount == 1 }
        try await waitUntil("scheduler waiting with activity held") {
            activity.begins.count == 1 && fakeSleep.blocked
        }
        XCTAssertEqual(activity.begins, ["Allnighter capacity deadline wait"])
        XCTAssertEqual(activity.outstanding, 1, "lease held for the whole wait")

        await resident.setEnabled(false)
        try await waitUntil("activity ended on OFF") { activity.outstanding == 0 }
        XCTAssertEqual(activity.endCount, activity.begins.count, "every begin is ended")

        // OFF: even with plenty of time granted, nothing fires, nothing probes.
        fakeSleep.addBudget(2 * 3600)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertTrue(fires.fires.isEmpty)
        XCTAssertEqual(persisted.writes, [false], "initially-ON resident persists only the OFF flip")
    }
}

// MARK: - CapacityWakeCoalesce (CWB-S01b)

final class CapacityWakeCoalesceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_753_833_600)

    /// Rapid wake signals (NSWorkspace didWake + repeats) collapse into one
    /// `.wake` refresh — never a burst.
    func testRapidWakeSignalsCoalesceToOneRefresh() async throws {
        let clock = FakeClock(t0)
        let fakeSleep = FakeSleep(clock: clock)
        let recorder = FetchRecorder()
        let activity = ActivitySpy()
        let fires = FireRecorder()
        let persisted = PersistRecorder()
        let resident = makeSchedulerResident(
            clock: clock, fakeSleep: fakeSleep, activity: activity,
            fires: fires, persisted: persisted,
            fetch: instantFullBenchFetch(clock: clock, recorder: recorder)
        )

        await resident.setEnabled(true)
        try await waitUntil("silent launch acquire") { recorder.startCount == 1 }
        try await waitUntil("scheduler waiting") { fakeSleep.blocked }

        await resident.notifyWake()
        await resident.notifyWake()
        await resident.notifyWake()

        try await waitUntil("one wake refresh") { fires.fires.count == 1 }
        XCTAssertEqual(fires.fires, [.wake])
        XCTAssertEqual(recorder.startCount, 2, "three signals → exactly one acquire")

        // No burst afterwards: the deadline rearmed from the wake settle.
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(fires.fires, [.wake])
        XCTAssertEqual(recorder.startCount, 2)

        await resident.setEnabled(false)
    }

    /// A large wall-clock jump past the deadline is classified as wake — one
    /// refresh, no catch-up burst — and the next deadline is a normal one.
    func testClockJumpClassifiedAsWakeWithNoCatchUpBurst() async throws {
        let clock = FakeClock(t0)
        let fakeSleep = FakeSleep(clock: clock)
        let recorder = FetchRecorder()
        let activity = ActivitySpy()
        let fires = FireRecorder()
        let persisted = PersistRecorder()
        let resident = makeSchedulerResident(
            clock: clock, fakeSleep: fakeSleep, activity: activity,
            fires: fires, persisted: persisted,
            fetch: instantFullBenchFetch(clock: clock, recorder: recorder)
        )

        await resident.setEnabled(true)
        try await waitUntil("silent launch acquire") { recorder.startCount == 1 }

        // Machine "sleeps" three hours: wall jumps, monotonic does not.
        clock.advanceWall(by: 3 * 3600)
        fakeSleep.addBudget(30 * 60)
        try await waitUntil("wake fire after clock jump") { fires.fires.count == 1 }
        XCTAssertEqual(fires.fires, [.wake], "wall jump past deadline = wake, not deadline")
        XCTAssertEqual(recorder.startCount, 2, "exactly one refresh after resume")

        // No catch-up burst: a small grant only feeds the next (normal) wait.
        fakeSleep.addBudget(2 * 60)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(fires.fires, [.wake])
        XCTAssertEqual(recorder.startCount, 2)

        // The deadline after a wake is an ordinary 30m deadline again.
        fakeSleep.addBudget(28 * 60)
        try await waitUntil("normal deadline after wake") { fires.fires.count == 2 }
        XCTAssertEqual(fires.fires, [.wake, .deadline])
        XCTAssertEqual(recorder.startCount, 3)

        await resident.setEnabled(false)
    }
}

// MARK: - CapacityFeatureOff (CWB-S01b)

final class CapacityFeatureOffTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_753_833_600)

    /// OFF mid-acquire: scoped cancel of the in-flight generation (never a
    /// global kill), then zero probes from every trigger in the vocabulary.
    func testOFFScopedCancelsInFlightAndZeroesProbesFromEveryTrigger() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let kills = KillRecorder()
        let persisted = PersistRecorder()
        let fakePID: pid_t = 7_100_002

        let resident = CapacityResidentService(
            now: { clock.now() },
            sleep: { interval in clock.advance(by: interval); await Task.yield() },
            monotonicNow: { clock.monotonicNow() },
            activities: .disabled,
            makeScope: { CapacityProbeScope { pid in kills.record(pid) } },
            acquireFloor: 0,
            persistEnabled: { enabled in persisted.record(enabled) },
            fetch: { source, scope in
                recorder.recordStart(source: source, at: clock.now())
                scope.track(fakePID)
                // Block until the scoped terminate lands (or the task is cancelled).
                while !kills.killed.contains(fakePID), !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                let now = clock.now()
                return snapshot(now: now, windows: [failedWindow(source: "grok", at: now)])
            }
        )

        let refresh = Task { await resident.requestRefresh(reason: .userRefresh) }
        try await waitUntil("acquire in flight") { recorder.startCount == 1 }

        await resident.setEnabled(false)
        XCTAssertTrue(kills.killed.contains(fakePID), "OFF must scoped-terminate the in-flight generation")
        let isEnabled = await resident.isEnabled
        XCTAssertFalse(isEnabled)
        XCTAssertEqual(persisted.writes, [false])
        let snapshotAfterOff = await resident.currentSnapshot()
        XCTAssertNil(snapshotAfterOff, "OFF drops painted truth — no memo-as-live")

        let cancelledResult = await refresh.value
        XCTAssertTrue(cancelledResult.windows.isEmpty, "waiter on a killed generation gets empty truth, not a partial")

        // Zero probes from every trigger in the vocabulary.
        for reason in [
            CapacityResidentService.RefreshReason.launch,
            .deadline, .wake, .userRefresh,
            .userRefreshSeat("grok"), .postRun(source: "codex"),
        ] {
            let result = await resident.requestRefresh(reason: reason)
            XCTAssertTrue(result.windows.isEmpty, "OFF: \(reason) must return empty truth")
        }
        await resident.notifyWake()
        XCTAssertEqual(recorder.startCount, 1, "OFF: zero probes from every trigger")
    }

    /// OFF drops the snapshot; re-ON wires the scheduler and fires the
    /// immediate silent launch acquire.
    func testOFFDropsSnapshotAndReEnableStartsScheduler() async throws {
        let clock = FakeClock(t0)
        let fakeSleep = FakeSleep(clock: clock)
        let recorder = FetchRecorder()
        let activity = ActivitySpy()
        let fires = FireRecorder()
        let persisted = PersistRecorder()
        let resident = makeSchedulerResident(
            clock: clock, fakeSleep: fakeSleep, activity: activity,
            fires: fires, persisted: persisted,
            fetch: instantFullBenchFetch(clock: clock, recorder: recorder)
        )

        _ = await resident.requestRefresh(reason: .userRefresh)
        let settled = await resident.currentSnapshot()
        XCTAssertNotNil(settled)

        await resident.setEnabled(false)
        let afterOff = await resident.currentSnapshot()
        XCTAssertNil(afterOff, "OFF: snapshot cleared, no memo-as-live")

        await resident.setEnabled(true)
        try await waitUntil("re-ON silent launch acquire") { recorder.startCount == 2 }
        XCTAssertNil(recorder.starts[1].source, "re-ON acquire is the full-bench silent launch")
        XCTAssertEqual(persisted.writes, [false, true])
        // Settle runs inside the generation task; poll the actor for repopulation.
        var repopulated = false
        for _ in 0..<100 where !repopulated {
            repopulated = await resident.currentSnapshot() != nil
            if !repopulated { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        XCTAssertTrue(repopulated, "snapshot repopulated after re-ON silent launch")
        await resident.setEnabled(false)
    }

    /// Startup when ON: `setEnabled(true)` on an already-enabled resident
    /// wires the scheduler if it was never started, and fires one silent
    /// full-bench `.launch` — no persisted write for an unchanged flag.
    func testStartupWhenONWiresSchedulerAndFiresSilentLaunch() async throws {
        let clock = FakeClock(t0)
        let fakeSleep = FakeSleep(clock: clock)
        let recorder = FetchRecorder()
        let activity = ActivitySpy()
        let fires = FireRecorder()
        let persisted = PersistRecorder()
        let resident = makeSchedulerResident(
            clock: clock, fakeSleep: fakeSleep, activity: activity,
            fires: fires, persisted: persisted,
            fetch: instantFullBenchFetch(clock: clock, recorder: recorder)
        )

        XCTAssertEqual(recorder.startCount, 0, "nothing fires before the feature is wired")
        await resident.setEnabled(true)
        try await waitUntil("immediate silent launch") { recorder.startCount == 1 }
        XCTAssertNil(recorder.starts[0].source, "startup acquire is the full-bench silent launch")
        XCTAssertTrue(persisted.writes.isEmpty, "unchanged flag is not re-persisted")

        await resident.setEnabled(false)
    }

    /// Tiny settings file: missing → ON default, round-trip, corrupt backup.
    func testSettingsPersistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-feature-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("capacity_feature.json")
        let persistence = CapacityFeatureSettingsPersistence(fileURL: fileURL)

        XCTAssertTrue(persistence.loadEnabled(), "missing file → ON (shipped default)")
        try persistence.saveEnabled(false)
        XCTAssertFalse(persistence.loadEnabled())
        try persistence.saveEnabled(true)
        XCTAssertTrue(persistence.loadEnabled())

        try Data("not json".utf8).write(to: fileURL)
        XCTAssertTrue(persistence.loadEnabled(), "corrupt file falls back to ON")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path),
            "corrupt file is backed up, never silently discarded"
        )
    }
}


// MARK: - CapacityPostRunGate (CWB-S03)

final class CapacityPostRunGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_753_833_600)

    private func makeResident(
        clock: FakeClock,
        recorder: FetchRecorder,
        enabled: Bool = true
    ) -> CapacityResidentService {
        CapacityResidentService(
            now: { clock.now() },
            sleep: { interval in clock.advance(by: interval); await Task.yield() },
            activities: .disabled,
            acquireFloor: 0,
            initiallyEnabled: enabled,
            fetch: { source, _ in
                recorder.recordStart(source: source, at: clock.now())
                let now = clock.now()
                let windows = CapacityAcquisition.benchSourceOrder.map {
                    knownWindow(source: $0, used: 42, at: now)
                }
                return snapshot(now: now, windows: windows)
            }
        )
    }

    /// Allowed path: feature ON, no acquire in flight, settlement observed in
    /// the Dock app process (caller contract).
    func testPostRunAllowedWhenFeatureOnAndIdle() async {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(clock: clock, recorder: recorder, enabled: true)

        let triggered = await resident.postRunSettled(source: "codex")

        XCTAssertTrue(triggered, "post-run refresh must start when ON and idle")
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.starts.first?.source, "codex")
    }

    /// Cut reason: feature OFF.
    func testPostRunCutWhenFeatureOff() async {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(clock: clock, recorder: recorder, enabled: false)

        let triggered = await resident.postRunSettled(source: "codex")

        XCTAssertFalse(triggered, "post-run refresh must cut when feature OFF")
        XCTAssertEqual(recorder.startCount, 0, "OFF: zero probes from post-run")
    }

    /// Cut reason: an acquire is already in flight (no queue storm).
    func testPostRunCutWhenAcquireInFlight() async throws {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = CapacityResidentService(
            now: { clock.now() },
            sleep: { interval in clock.advance(by: interval); await Task.yield() },
            activities: .disabled,
            acquireFloor: 0,
            initiallyEnabled: true,
            fetch: { source, _ in
                recorder.recordStart(source: source, at: clock.now())
                let now = clock.now()
                if source == nil {
                    // Full bench blocks until the test opens the gate.
                    await recorder.waitForGate()
                }
                let windows = CapacityAcquisition.benchSourceOrder.map {
                    knownWindow(source: $0, used: 42, at: now)
                }
                return snapshot(now: now, windows: windows)
            }
        )

        let inFlight = Task { await resident.requestRefresh(reason: .userRefresh) }
        try await waitUntil("full acquire in flight") { recorder.startCount == 1 }

        let triggered = await resident.postRunSettled(source: "codex")
        XCTAssertFalse(triggered, "post-run refresh must cut when an acquire is already in flight")

        recorder.openGate()
        _ = await inFlight.value
        XCTAssertEqual(recorder.startCount, 1, "cut post-run must not queue a second generation")
    }

    /// Cut reason: settlement observed outside the Dock app process.
    ///
    /// This is enforced by caller discipline, not by a runtime flag:
    /// `postRunSettled(source:)` lives on `CapacityResidentService`, which only
    /// exists in the Dock app, and there is no socket write RPC for CLI-only
    /// settlements. The Mac app's `ThreadsViewModel.runViaRunService` satisfies
    /// the caller contract by calling this only after its in-process
    /// `RunService.run()` observation settles.
    func testPostRunOutsideDockProcessIsCallerContract() async {
        let clock = FakeClock(t0)
        let recorder = FetchRecorder()
        let resident = makeResident(clock: clock, recorder: recorder, enabled: true)

        let triggered = await resident.postRunSettled(source: "codex")

        XCTAssertTrue(triggered, "in-process caller satisfies the Dock-process contract")
        XCTAssertEqual(recorder.startCount, 1)
    }
}
