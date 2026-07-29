import XCTest
import AllnighterCore

final class PMTurnStatusWaitTests: XCTestCase {
    func testMatchesParkedPilotBoundary() {
        let result = PMTurnStatusWait.wait(target: .parked, timeout: 0, readStatus: { .awaitingPM })
        XCTAssertEqual(result.status, .awaitingPM)
        XCTAssertEqual(result.outcome, .matched)
    }

    func testStopsAtTerminalMismatch() {
        let result = PMTurnStatusWait.wait(target: .parked, timeout: 60, readStatus: { .done })
        XCTAssertEqual(result.status, .done)
        XCTAssertEqual(result.outcome, .terminalMismatch)
    }

    func testTimesOutWithoutBoundary() {
        let result = PMTurnStatusWait.wait(target: .terminal, timeout: 0, readStatus: { .running })
        XCTAssertEqual(result.status, .running)
        XCTAssertEqual(result.outcome, .timedOut)
    }
}
