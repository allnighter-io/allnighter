import XCTest
import AllnighterCore
@testable import AllnighterMac

/// Bug list #8: distinct failure causes never collapse into one "timed out" label, and a
/// preserved partial answer is surfaced.
final class WorkerFailurePresenterTests: XCTestCase {

    private func capacity(_ kind: CapacityObservationKind, source: String) -> CapacityObservation {
        CapacityObservation(kind: kind, source: source, sourceConfidence: .messageFallback,
                            rawSnippet: "", observedAt: Date())
    }

    func testTimeoutKeepsItsReason() {
        let c = WorkerFailurePresenter.cause(status: .timedOut, errorKind: .timedOut,
                                             errorReason: "no output for 300s", capacity: nil)
        XCTAssertEqual(c, "no output for 300s")
    }

    func testEmptyOutputIsDistinctFromTimeout() {
        let c = WorkerFailurePresenter.cause(status: .failed, errorKind: .emptyOutput,
                                             errorReason: nil, capacity: nil)
        XCTAssertEqual(c, "No output (exited cleanly, empty)")
    }

    func testWrongCliClassified() {
        let c = WorkerFailurePresenter.cause(status: .failed, errorKind: .missingCLI,
                                             errorReason: "claude not found", capacity: nil)
        XCTAssertEqual(c, "CLI not installed / wrong CLI")
    }

    func testCapacityWinsOverGenericTimeout() {
        // A worker that "timed out" but the CLI reported auth is an AUTH failure, not a timeout.
        let c = WorkerFailurePresenter.cause(
            status: .timedOut, errorKind: .timedOut, errorReason: "no output for 300s",
            capacity: capacity(.authRequired, source: "codex"))
        XCTAssertEqual(c, "Auth required — sign in to codex")
    }

    func testRateLimitClassified() {
        let c = WorkerFailurePresenter.cause(
            status: .failed, errorKind: .nonzeroExit, errorReason: "exit 1",
            capacity: capacity(.accountRateLimit, source: "claude_code"))
        XCTAssertEqual(c, "Rate limited — claude_code")
    }

    func testDoneHasNoCause() {
        XCTAssertNil(WorkerFailurePresenter.cause(status: .done, errorKind: nil, errorReason: nil, capacity: nil))
    }

    func testPartialOutputDetected() {
        XCTAssertTrue(WorkerFailurePresenter.hasPartialOutput("half an answer"))
        XCTAssertFalse(WorkerFailurePresenter.hasPartialOutput("   "))
        XCTAssertFalse(WorkerFailurePresenter.hasPartialOutput(nil))
    }
}
