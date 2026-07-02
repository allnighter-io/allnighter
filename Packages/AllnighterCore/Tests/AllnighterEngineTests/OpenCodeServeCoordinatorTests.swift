import XCTest
@testable import AllnighterEngine

final class OpenCodeServeCoordinatorTests: XCTestCase {
    func testIsHealthy_whenInjectedTrue_returnsTrue() async {
        let c = OpenCodeServeCoordinator(healthCheck: { true })
        let healthy = await c.isHealthy()
        XCTAssertTrue(healthy)
    }

    func testIsHealthy_whenInjectedFalse_returnsFalse() async {
        let c = OpenCodeServeCoordinator(healthCheck: { false })
        let healthy = await c.isHealthy()
        XCTAssertFalse(healthy)
    }

    func testEnsureRunning_whenAlreadyHealthy_doesNotSpawn() async throws {
        let launchCount = LaunchCountBox()
        let c = OpenCodeServeCoordinator(
            healthCheck: { true },
            portListenerPID: { _ in nil },
            launchServe: {
                launchCount.increment()
                throw OpenCodeServeCoordinatorError.opencodeExecutableNotFound
            },
            state: SpawnState()
        )
        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 0)
    }

    func testEnsureRunning_spawnFailurePropagatesWithoutLongTimeout() async throws {
        let c = OpenCodeServeCoordinator(
            healthCheck: { false },
            portListenerPID: { _ in nil },
            launchServe: {
                throw OpenCodeServeCoordinatorError.opencodeExecutableNotFound
            },
            state: SpawnState()
        )

        do {
            try await c.ensureRunning()
            XCTFail("expected throw")
        } catch OpenCodeServeCoordinatorError.opencodeExecutableNotFound {
        }

        let start = ContinuousClock.now
        do {
            try await c.ensureRunning()
            XCTFail("expected throw")
        } catch OpenCodeServeCoordinatorError.opencodeExecutableNotFound {
        }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    func testEnsureRunning_childExitAllowsRespawn() async throws {
        let health = HealthBox()
        let launchCount = LaunchCountBox()

        let c = OpenCodeServeCoordinator(
            healthCheck: { health.isHealthy() },
            portListenerPID: { _ in health.listener() },
            launchServe: {
                launchCount.increment()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                process.arguments = ["30"]
                try process.run()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let drain = PipeDrain(stdout: stdoutPipe, stderr: stderrPipe)
                drain.start()
                health.setListener(process.processIdentifier)
                health.setHealthy(true)
                return LaunchedServe(process: process, pid: process.processIdentifier, stderrDrain: drain)
            },
            state: SpawnState()
        )

        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 1)

        health.setHealthy(false)
        await c.stop()
        health.setListener(nil)

        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 2)
    }

    func testEnsureRunning_reclaimsForeignPortListener() async throws {
        let health = HealthBox()
        let launchCount = LaunchCountBox()
        var foreignKilled = false

        let c = OpenCodeServeCoordinator(
            healthCheck: { health.isHealthy() },
            portListenerPID: { _ in health.listener() },
            launchServe: {
                launchCount.increment()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                process.arguments = ["30"]
                try process.run()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let drain = PipeDrain(stdout: stdoutPipe, stderr: stderrPipe)
                drain.start()
                health.setListener(process.processIdentifier)
                health.setHealthy(true)
                return LaunchedServe(process: process, pid: process.processIdentifier, stderrDrain: drain)
            },
            state: SpawnState()
        )

        let foreign = Process()
        foreign.executableURL = URL(fileURLWithPath: "/bin/sleep")
        foreign.arguments = ["60"]
        try foreign.run()
        health.setListener(foreign.processIdentifier)
        health.setHealthy(true)

        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 1)
        foreignKilled = !RunStore.processAlive(foreign.processIdentifier)
        XCTAssertTrue(foreignKilled)
        await c.stop()
    }

    func testEnsureRunning_reapsIdleChild() async throws {
        setenv("ALLNIGHTER_OPENCODE_SERVE_IDLE_SECONDS", "1", 1)
        defer { unsetenv("ALLNIGHTER_OPENCODE_SERVE_IDLE_SECONDS") }

        let health = HealthBox()
        let launchCount = LaunchCountBox()

        let c = OpenCodeServeCoordinator(
            healthCheck: { health.isHealthy() },
            portListenerPID: { _ in health.listener() },
            launchServe: {
                launchCount.increment()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                process.arguments = ["30"]
                try process.run()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let drain = PipeDrain(stdout: stdoutPipe, stderr: stderrPipe)
                drain.start()
                health.setListener(process.processIdentifier)
                health.setHealthy(true)
                return LaunchedServe(process: process, pid: process.processIdentifier, stderrDrain: drain)
            },
            state: SpawnState()
        )

        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 1)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        health.setHealthy(false)
        health.setListener(nil)
        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 2)
        await c.stop()
    }

    func testEnsureRunning_live_opencode() async throws {
        throw XCTSkip("Live opencode serve from XCTest can SIGSEGV; use founder manual smoke")
    }
}

private final class LaunchCountBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class HealthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var healthy = false
    private var listenerPID: Int32?

    func setHealthy(_ value: Bool) {
        lock.lock()
        healthy = value
        lock.unlock()
    }

    func setListener(_ pid: Int32?) {
        lock.lock()
        listenerPID = pid
        lock.unlock()
    }

    func isHealthy() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return healthy
    }

    func listener() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return listenerPID
    }
}
