import XCTest
@testable import AllnighterCore

/// RLR-S04c — pure contradiction projection (no I/O). Engine wiring is proven
/// in `KillSettlementTests` / status/`ps` surfaces.
final class RunContradictionTests: XCTestCase {

    func testTerminalPlusLiveWorkerIsContradiction() {
        XCTAssertEqual(
            RunContradictionSurface.contradiction(
                isTerminal: true, anyWorkerIdentityAlive: true),
            .terminalWithLiveOwnership)
    }

    func testTerminalPlusAllDeadIsNil() {
        XCTAssertNil(
            RunContradictionSurface.contradiction(
                isTerminal: true, anyWorkerIdentityAlive: false))
    }

    func testNonTerminalIsNilEvenWithLiveWorker() {
        XCTAssertNil(
            RunContradictionSurface.contradiction(
                isTerminal: false, anyWorkerIdentityAlive: true),
            "contradiction is the negative proof over a terminal stamp — never invent on live runs")
    }

    func testZombieReadsDeadSoNoContradiction() {
        // Callers pass zombie-aware identity-alive; a zombie is dead → false.
        XCTAssertNil(
            RunContradictionSurface.contradiction(
                isTerminal: true, anyWorkerIdentityAlive: false),
            "zombie-aware identity-alive treats zombies as dead")
    }

    func testInProcessCoordinatorAliveDoesNotTrip() {
        XCTAssertNil(
            RunContradictionSurface.contradiction(
                isTerminal: true,
                anyWorkerIdentityAlive: false,
                coordinatorIdentityAlive: true,
                coordinatorIsProcessGroupKillable: false),
            "inProcess coordinator is the reader/app — never the surviving work tree")
    }

    func testDetachedCoordinatorAliveTrips() {
        XCTAssertEqual(
            RunContradictionSurface.contradiction(
                isTerminal: true,
                anyWorkerIdentityAlive: false,
                coordinatorIdentityAlive: true,
                coordinatorIsProcessGroupKillable: true),
            .terminalWithLiveOwnership)
    }

    func testRetentionWindowIsFinitePositive() {
        XCTAssertTrue(RunContradictionSurface.ownershipReceiptRetentionSeconds > 0)
        XCTAssertTrue(RunContradictionSurface.ownershipReceiptRetentionSeconds.isFinite)
    }
}
