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
            }
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
            }
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
            }
        )

        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 1)

        health.setHealthy(false)
        await c.stop()
        health.setListener(nil)

        try await c.ensureRunning()
        XCTAssertEqual(launchCount.value, 2)
    }

    func testEnsureRunning_foreignPortOwnerThrows() async throws {
        let c = OpenCodeServeCoordinator(
            healthCheck: { true },
            portListenerPID: { _ in 4242 },
            launchServe: {
                XCTFail("should not spawn")
                throw OpenCodeServeCoordinatorError.opencodeExecutableNotFound
            }
        )

        do {
            try await c.ensureRunning()
            XCTFail("expected foreign port error")
        } catch OpenCodeServeCoordinatorError.portOwnedByForeignProcess(let pid) {
            XCTAssertEqual(pid, 4242)
        }
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
