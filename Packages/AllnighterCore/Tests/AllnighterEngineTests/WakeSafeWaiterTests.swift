import XCTest
import AllnighterCore
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

    func testLoopCoordinator5HourParkSleepGap() async throws {
        let clock = TestClock(epoch)
        let sleepLog = SleepLog()
        let deadline = clock.time.addingTimeInterval(0.2)

        let sleeper = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: { duration in
                sleepLog.record(duration)
                if sleepLog.count == 1 {
                    clock.advance(by: 10)
                }
            }
        )

        let model = Model(id: "test_model", displayName: "Test", modelLabel: "m", driverId: "test_driver", role: .both, enabled: true)
        let registry = DriverRegistry([
            DriverManifest(
                id: "test_driver",
                displayName: "Test Driver",
                kind: .headlessCLI,
                detectCommand: "test --version",
                smokeTestCommand: "test smoke {{model}}",
                smokeTestExpect: "READY",
                invoke: .init(
                    command: "test",
                    args: ["-p", "{{prompt}}"],
                    promptVia: .arg,
                    env: [:],
                    workingDir: nil,
                    timeoutSeconds: 2
                ),
                output: .init()
            )
        ])

        let service = RunService(
            models: [model],
            registry: registry,
            runStore: RunStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-sleep-test-\(UUID().uuidString)")),
            commandRunner: MockCommandRunner(scripts: [:]),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: { [] }
        )

        let coordinator = LoopCoordinator(
            runService: service,
            now: { clock.time },
            sleeper: sleeper
        )

        let config = LoopCoordinator.Config(
            projectRoot: "/tmp/test",
            docPath: "docs/spec.md",
            pmModelId: "test_model",
            devModelId: "test_model",
            maxRounds: 10,
            until: deadline,
            stagnationRoundCap: 3,
            presetId: "test"
        )

        await coordinator.sleepClampedToDeadline(config, seconds: 10)

        XCTAssertGreaterThanOrEqual(clock.time, deadline, "Clock should be past deadline after simulated sleep gap")
        XCTAssertEqual(sleepLog.count, 1, "Should return within ONE nap of the simulated sleep gap. Got \(sleepLog.count) naps — sleepClampedToDeadline must delegate to the wake-safe sleeper.")
        let firstDuration = try XCTUnwrap(sleepLog.durations.first)
        XCTAssertLessThanOrEqual(firstDuration, 0.21, "Each nap must be bounded by the remaining interval (~0.2s), got \(firstDuration)")
        let overshoot = try XCTUnwrap(coordinator.lastSleepOvershoot, "Overshoot should be recorded after simulated sleep gap")
        XCTAssertGreaterThan(overshoot, 0, "Overshoot should be non-zero after simulated sleep gap, got \(overshoot)")
    }

    func testDefaultPendingWakeSleeperSurvivesSleepGap() async throws {
        let clock = TestClock(epoch)
        let sleepLog = SleepLog()
        let deadline = clock.time.addingTimeInterval(4 * 3600)

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            if sleepLog.count == 1 {
                clock.advance(by: 6 * 3600)
            }
        }

        let sleeper = DefaultPendingWakeSleeper(
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await sleeper.sleep(until: deadline, jitterSeconds: 0)

        XCTAssertGreaterThanOrEqual(clock.time, deadline, "Clock should be past deadline after simulated sleep")
        XCTAssertEqual(sleepLog.count, 1, "Should return within ONE nap of the advance, got \(sleepLog.count) naps")
        let firstDuration = try XCTUnwrap(sleepLog.durations.first)
        XCTAssertLessThanOrEqual(firstDuration, 60, "Each nap must be bounded by maxNapSeconds (60), got \(firstDuration)")
    }

    func testDefaultPendingWakeSleeperJitterPreserved() async throws {
        let clock = TestClock(epoch)
        let deadline = clock.time.addingTimeInterval(300)
        let sleepLog = SleepLog()
        let jitterSeconds: TimeInterval = 60

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            clock.advance(by: duration)
        }

        let sleeper = DefaultPendingWakeSleeper(
            now: { clock.time },
            performSleep: sleepClosure
        )

        try await sleeper.sleep(until: deadline, jitterSeconds: jitterSeconds)

        let totalSlept = sleepLog.durations.reduce(0, +)
        XCTAssertGreaterThan(totalSlept, 300, "Total slept must exceed the un-jittered deadline")
        for duration in sleepLog.durations {
            XCTAssertLessThanOrEqual(duration, 60, "Each nap bounded by maxNapSeconds")
        }
    }

    func testVendorBackoffReconcilerDefaultSleeperWakeSafe() async throws {
        let clock = TestClock(epoch)
        let sleepLog = SleepLog()

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            clock.advance(by: duration)
            if sleepLog.count == 1 {
                clock.advance(by: 3600)
            }
        }

        let sleeper = DefaultPendingWakeSleeper(
            now: { clock.time },
            performSleep: sleepClosure
        )

        let model = Model(id: "test_model", displayName: "Test", modelLabel: "m", driverId: "test_driver", role: .both, enabled: true)
        let registry = DriverRegistry([
            DriverManifest(
                id: "test_driver",
                displayName: "Test Driver",
                kind: .headlessCLI,
                detectCommand: "test --version",
                smokeTestCommand: "test smoke {{model}}",
                smokeTestExpect: "READY",
                invoke: .init(
                    command: "test",
                    args: ["-p", "{{prompt}}"],
                    promptVia: .arg,
                    env: [:],
                    workingDir: nil,
                    timeoutSeconds: 2
                ),
                output: .init()
            )
        ])

        let runStoreDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-vbr-test-\(UUID().uuidString)")
        let service = RunService(
            models: [model],
            registry: registry,
            runStore: RunStore(rootDirectory: runStoreDir),
            commandRunner: MockCommandRunner(scripts: [:]),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: { [] }
        )

        let reconciler = VendorBackoffReconciler(
            runStore: RunStore(rootDirectory: runStoreDir),
            runService: service,
            coordinatorId: "test-coord",
            now: { clock.time },
            sleeper: sleeper
        )

        let task = Task {
            await reconciler.run(isCancelled: { Task.isCancelled })
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        _ = await task.value

        XCTAssertFalse(sleepLog.durations.isEmpty, "Scheduler should have called sleeper at least once")
        for duration in sleepLog.durations {
            XCTAssertLessThanOrEqual(duration, 60, "DefaultPendingWakeSleeper nap bounded, got \(duration)")
        }
    }

    func testBoostSeedSchedulerDefaultSleeperWakeSafe() async throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let midnight = Date(timeIntervalSince1970: 1_700_000_000)
        let fourAM = midnight.addingTimeInterval(4 * 3600)

        let clock = TestClock(fourAM)
        let sleepLog = SleepLog()

        let sleepClosure: @Sendable (TimeInterval) async throws -> Void = { duration in
            sleepLog.record(duration)
            clock.advance(by: duration)
            if sleepLog.count == 1 {
                clock.advance(by: 6 * 3600)
            }
        }

        let sleeper = DefaultPendingWakeSleeper(
            now: { clock.time },
            performSleep: sleepClosure
        )

        let settingsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-bss-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        let settingsFile = settingsDir.appendingPathComponent("boost_window_settings.json")
        let seedFile = settingsDir.appendingPathComponent("utilization_seed_events.json")

        var settings = BoostWindowSettings(enabled: true, windowStart: 8 * 60, appliesTo: ["claude_code"])
        settings.normalize()
        let settingsData = try CoreJSON.encode(settings)
        try settingsData.write(to: settingsFile, options: .atomic)

        let model = Model(id: "test_model", displayName: "Test", modelLabel: "m", driverId: "test_driver", role: .both, enabled: true)
        let registry = DriverRegistry([
            DriverManifest(
                id: "test_driver",
                displayName: "Test Driver",
                kind: .headlessCLI,
                detectCommand: "test --version",
                smokeTestCommand: "test smoke {{model}}",
                smokeTestExpect: "READY",
                invoke: .init(
                    command: "test",
                    args: ["-p", "{{prompt}}"],
                    promptVia: .arg,
                    env: [:],
                    workingDir: nil,
                    timeoutSeconds: 2
                ),
                output: .init()
            )
        ])

        let scheduler = BoostSeedScheduler(
            settingsPersistence: BoostWindowSettingsPersistence(fileURL: settingsFile),
            seedLedger: UtilizationSeedLedger(fileURL: seedFile),
            registry: registry,
            models: [model],
            now: { clock.time },
            calendar: utcCalendar,
            sleeper: sleeper
        )

        let task = Task {
            await scheduler.run(isCancelled: { Task.isCancelled })
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        _ = await task.value

        XCTAssertFalse(sleepLog.durations.isEmpty, "Scheduler should have called sleeper at least once")
        for duration in sleepLog.durations {
            XCTAssertLessThanOrEqual(duration, 60, "DefaultPendingWakeSleeper nap bounded, got \(duration)")
        }
    }

    func testLoopCoordinatorShortParkNoSleepGap() async throws {
        let clock = TestClock(epoch)
        let sleepLog = SleepLog()
        let deadline = clock.time.addingTimeInterval(0.5)

        let sleeper = WakeSafeWaiter(
            maxNapSeconds: 60,
            now: { clock.time },
            performSleep: { duration in
                sleepLog.record(duration)
                clock.advance(by: duration)
            }
        )

        let model = Model(id: "test_model", displayName: "Test", modelLabel: "m", driverId: "test_driver", role: .both, enabled: true)
        let registry = DriverRegistry([
            DriverManifest(
                id: "test_driver",
                displayName: "Test Driver",
                kind: .headlessCLI,
                detectCommand: "test --version",
                smokeTestCommand: "test smoke {{model}}",
                smokeTestExpect: "READY",
                invoke: .init(
                    command: "test",
                    args: ["-p", "{{prompt}}"],
                    promptVia: .arg,
                    env: [:],
                    workingDir: nil,
                    timeoutSeconds: 2
                ),
                output: .init()
            )
        ])

        let service = RunService(
            models: [model],
            registry: registry,
            runStore: RunStore(rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-sleep-test-\(UUID().uuidString)")),
            commandRunner: MockCommandRunner(scripts: [:]),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: { [] }
        )

        let coordinator = LoopCoordinator(
            runService: service,
            now: { clock.time },
            sleeper: sleeper
        )

        let config = LoopCoordinator.Config(
            projectRoot: "/tmp/test",
            docPath: "docs/spec.md",
            pmModelId: "test_model",
            devModelId: "test_model",
            maxRounds: 10,
            until: deadline,
            stagnationRoundCap: 3,
            presetId: "test"
        )

        await coordinator.sleepClampedToDeadline(config, seconds: 10)

        XCTAssertGreaterThanOrEqual(clock.time, deadline, "Clock should be at or past deadline")
        XCTAssertEqual(sleepLog.count, 1, "Short park without sleep gap should complete in one nap")
        let overshoot = coordinator.lastSleepOvershoot
        XCTAssertNotNil(overshoot)
        XCTAssertEqual(overshoot!, 0, accuracy: 0.001, "Overshoot should be ~zero on normal (no-gap) wait, got \(overshoot!)")
    }
}
