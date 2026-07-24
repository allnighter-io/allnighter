import XCTest
@testable import AllnighterCLI
@testable import AllnighterEngine

final class RunCLIStreamAdapterTests: XCTestCase {
    func testStreamAdapterSuccessReturnsZero() {
        XCTAssertEqual(RunCLI.streamOutcome(for: nil), .success)
    }

    func testStreamAdapterRunFailureRetainsTypedCodeAndNonzeroExit() {
        let outcome = RunCLI.streamOutcome(
            for: .teamResolution("selected Team is unavailable", code: "TEAM_NOT_FOUND")
        )

        XCTAssertEqual(outcome.exitCode, 1)
        XCTAssertEqual(outcome.errorCode, "TEAM_NOT_FOUND")
        XCTAssertEqual(outcome.message, "selected Team is unavailable")
    }

    func testStreamJournalFailureIsTerminalAndNonzero() {
        let outcome = RunCLI.streamJournalFailure(RemoteRunEventJournalError.missingRunId(eventId: "event"))

        XCTAssertEqual(outcome.exitCode, 1)
        XCTAssertEqual(outcome.errorCode, "STREAM_JOURNAL_FAILED")
    }
}
