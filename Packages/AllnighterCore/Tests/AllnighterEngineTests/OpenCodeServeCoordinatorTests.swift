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
        let c = OpenCodeServeCoordinator(healthCheck: { true })
        try await c.ensureRunning()
    }

    func testEnsureRunning_live_opencode() async throws {
        throw XCTSkip("Live opencode serve from XCTest can SIGSEGV; use founder manual smoke")
    }
}