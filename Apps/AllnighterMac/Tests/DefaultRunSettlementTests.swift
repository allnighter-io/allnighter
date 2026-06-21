import XCTest
import AllnighterCore
@testable import AllnighterMac

/// RLS-S01 terminal-settlement correctness. A successful terminal `RunService` result
/// must settle the linked thread turn to a terminal state — never `.running`. This is
/// the guard against the dogfood "completed run, stuck spinner" bug, where a success
/// carrying a stale non-terminal `run.status` (e.g. `.finalizing`) mapped straight back
/// to `.running` and was persisted as such.
final class DefaultRunSettlementTests: XCTestCase {

    func testSuccessfulRunNeverSettlesToRunning() {
        // No RunStatus, when carried by a SUCCESS result, may leave the turn running.
        for status in RunStatus.allCases {
            XCTAssertNotEqual(
                ThreadsViewModel.settledStatus(forSuccessfulRun: status), .running,
                "a successful terminal run must never leave the turn .running (run.status = \(status))")
        }
    }

    func testSuccessTerminalMappingsArePreserved() {
        XCTAssertEqual(ThreadsViewModel.settledStatus(forSuccessfulRun: .complete), .done)
        XCTAssertEqual(ThreadsViewModel.settledStatus(forSuccessfulRun: .partial), .done)
        XCTAssertEqual(ThreadsViewModel.settledStatus(forSuccessfulRun: .cancelled), .cancelled)
        XCTAssertEqual(ThreadsViewModel.settledStatus(forSuccessfulRun: .failed), .failed)
        XCTAssertEqual(ThreadsViewModel.settledStatus(forSuccessfulRun: .interrupted), .failed)
    }

    func testNonTerminalRunStatusOnSuccessIsCoercedToDone() {
        // These map to .running in the raw `turnStatus`, but a SUCCESS means the run is
        // over, so they must coerce to .done.
        for status in [RunStatus.draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing] {
            XCTAssertEqual(
                ThreadsViewModel.settledStatus(forSuccessfulRun: status), .done,
                "a non-terminal run.status on a success must coerce to .done (\(status))")
        }
    }
}
