import XCTest
@testable import AllnighterEngine

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _time: Date

    init(_ time: Date) { _time = time }

    var time: Date {
        lock.withLock { _time }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { _time = _time.addingTimeInterval(interval) }
    }
}

private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _durations: [TimeInterval] = []

    var durations: [TimeInterval] {
        lock.withLock { _durations }
    }

    var count: Int {
        lock.withLock { _durations.count }
    }

    func record(_ duration: TimeInterval) {
        lock.withLock { _durations.append(duration) }
    }
}

private final class IntBox: @unchecked Sendable {
    private let lock = NSLock()
    var value: Int = 0
    func increment() { lock.withLock { value += 1 } }
}

private final class TimeIntervalBox: @unchecked Sendable {
    private let lock = NSLock()
    var value: TimeInterval = .greatestFiniteMagnitude
    func set(_ v: TimeInterval) { lock.withLock { value = v } }
}

final class WakeSafeWaiterTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testSleepGapDetectedOnWake() async throws {
        let clock = TestClock(epoch)
        let sleepLog = SleepLog()
        let deadline = clock.time.addingTimeInterval(4 * 3600)

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            if sleepLog.count == 1 {
                clock.advance(by: 6 * 3600)
            }
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: 0)

        XCTAssertGreaterThanOrEqual(clock.time, deadline, "Clock should be past deadline after simulated sleep")
        XCTAssertEqual(sleepLog.count, 1, "Should return within ONE nap of the advance, got \(sleepLog.count) naps")
        let firstDuration = try XCTUnwrap(sleepLog.durations.first)
        XCTAssertLessThanOrEqual(firstDuration, 60, "Each nap must be bounded by maxNapSeconds (60), got \(firstDuration)")
    }

    func testDeadlineInPastReturnsImmediately() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(-10)

        let sleepLog = SleepLog()
        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: 0)
        XCTAssertEqual(sleepLog.count, 0, "Deadline in past should not nap")
    }

    func testShortDeadlineCompletesInOneNap() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(10)
        let sleepLog = SleepLog()

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            clock.advance(by: duration)
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: 0)

        XCTAssertEqual(sleepLog.count, 1, "Short deadline should complete in one nap")
        let napDuration = try XCTUnwrap(sleepLog.durations.first)
        XCTAssertLessThanOrEqual(napDuration, 10, "Nap should not exceed the 10-second remaining interval")
    }

    func testLongDeadlineUsesMultipleNaps() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(200)
        let sleepLog = SleepLog()

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            clock.advance(by: duration)
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: 0)

        let expectedNaps = Int(ceil(200.0 / 60.0))
        XCTAssertEqual(sleepLog.count, expectedNaps, "A 200s deadline with maxNap=60 should take \(expectedNaps) naps")

        for duration in sleepLog.durations {
            XCTAssertLessThanOrEqual(duration, 60, "Each nap must be bounded by maxNapSeconds")
        }
    }

    func testJitterAppliedOnceNotPerNap() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(300)
        let jitterSeconds: TimeInterval = 60
        let sleepLog = SleepLog()
        let napCount = IntBox()
        let tightestRemaining = TimeIntervalBox()

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            napCount.increment()
            let remaining = deadline.addingTimeInterval(jitterSeconds / 2).timeIntervalSince(clock.time)
            tightestRemaining.set(min(tightestRemaining.value, remaining))
            clock.advance(by: duration)
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: jitterSeconds)

        let totalSlept = sleepLog.durations.reduce(0, +)
        XCTAssertGreaterThan(totalSlept, 300, "Total slept must exceed the un-jittered deadline")
        XCTAssertGreaterThan(napCount.value, 1, "Should use multiple naps")
        for duration in sleepLog.durations {
            XCTAssertLessThanOrEqual(duration, 60, "Each nap bounded by maxNapSeconds")
        }
    }

    func testOvershootNonZeroAfterSleepGap() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(4 * 3600)

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { _ in
            clock.advance(by: 6 * 3600)
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: 0)
        XCTAssertGreaterThan(waiter.lastOvershoot, 0, "Overshoot should be non-zero after simulated sleep gap")
    }

    func testOvershootNearZeroOnNormalWait() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(30)

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            clock.advance(by: duration)
        }

        let waiter = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await waiter.sleep(until: deadline, jitterSeconds: 0)
        XCTAssertEqual(waiter.lastOvershoot, 0, accuracy: 0.001, "Overshoot should be ~zero on normal wait")
    }
}
