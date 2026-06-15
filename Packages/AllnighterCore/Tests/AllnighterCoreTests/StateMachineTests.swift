import XCTest
@testable import AllnighterCore

final class StateMachineTests: XCTestCase {

    // MARK: Run state machine

    func testRunHappyPath() {
        let run = CouncilRun(id: "r", prompt: "p", status: .draft, createdAt: Date())
        XCTAssertTrue(run.canTransition(to: .fanningOut))
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .fanningOut, createdAt: Date()).canTransition(to: .answersIn))
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .answersIn, createdAt: Date()).canTransition(to: .synthesizing))
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .synthesizing, createdAt: Date()).canTransition(to: .complete))
    }

    func testRunSynthesisFailureGoesPartial() {
        let run = CouncilRun(id: "r", prompt: "p", status: .synthesizing, createdAt: Date())
        XCTAssertTrue(run.canTransition(to: .partial))
    }

    func testRunCancelAndFailReachableWhileActive() {
        for status in [RunStatus.draft, .fanningOut, .answersIn, .synthesizing, .reviewing, .finalizing] {
            let run = CouncilRun(id: "r", prompt: "p", status: status, createdAt: Date())
            XCTAssertTrue(run.canTransition(to: .cancelled), "\(status) -> cancelled should be legal")
            XCTAssertTrue(run.canTransition(to: .failed), "\(status) -> failed should be legal")
        }
    }

    func testReviewAndFinalizePath() {
        // answers_in -> reviewing -> finalizing -> complete (review-board presets).
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .answersIn, createdAt: Date()).canTransition(to: .reviewing))
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .reviewing, createdAt: Date()).canTransition(to: .finalizing))
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .finalizing, createdAt: Date()).canTransition(to: .complete))
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .finalizing, createdAt: Date()).canTransition(to: .partial))
        // synthesizing can also enter reviewing (synthesis-then-review).
        XCTAssertTrue(CouncilRun(id: "r", prompt: "p", status: .synthesizing, createdAt: Date()).canTransition(to: .reviewing))
        XCTAssertFalse(RunStatus.reviewing.isTerminal)
        XCTAssertFalse(RunStatus.finalizing.isTerminal)
    }

    func testRunIllegalTransitionsRejected() {
        XCTAssertFalse(CouncilRun(id: "r", prompt: "p", status: .draft, createdAt: Date()).canTransition(to: .complete))
        XCTAssertFalse(CouncilRun(id: "r", prompt: "p", status: .answersIn, createdAt: Date()).canTransition(to: .fanningOut))
        XCTAssertFalse(CouncilRun(id: "r", prompt: "p", status: .fanningOut, createdAt: Date()).canTransition(to: .complete))
    }

    func testRunTerminalStatesAreSinks() {
        for status in [RunStatus.complete, .partial, .cancelled, .failed] {
            XCTAssertTrue(status.isTerminal)
            let run = CouncilRun(id: "r", prompt: "p", status: status, createdAt: Date())
            for next in RunStatus.allCases {
                XCTAssertFalse(run.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }

    // MARK: Member state machine

    func testMemberHappyPath() {
        XCTAssertTrue(MemberResponse(seatId: "w#0", workerId: "w", status: .queued).canTransition(to: .running))
        XCTAssertTrue(MemberResponse(seatId: "w#0", workerId: "w", status: .running).canTransition(to: .done))
    }

    func testMemberTimeoutAndFailureFromRunning() {
        let running = MemberResponse(seatId: "w#0", workerId: "w", status: .running)
        XCTAssertTrue(running.canTransition(to: .timedOut))
        XCTAssertTrue(running.canTransition(to: .failed))
        XCTAssertTrue(running.canTransition(to: .cancelled))
    }

    func testManualPasteSkippedCanComplete() {
        let skipped = MemberResponse(seatId: "w#0", workerId: "w", status: .skipped)
        XCTAssertTrue(skipped.canTransition(to: .done))
        XCTAssertTrue(skipped.canTransition(to: .running))
    }

    func testMemberIllegalTransitionsRejected() {
        XCTAssertFalse(MemberResponse(seatId: "w#0", workerId: "w", status: .queued).canTransition(to: .done))
        XCTAssertFalse(MemberResponse(seatId: "w#0", workerId: "w", status: .done).canTransition(to: .running))
    }

    func testMemberTerminalStatesAreSinks() {
        for status in [MemberStatus.done, .failed, .timedOut, .cancelled] {
            XCTAssertTrue(status.isTerminal)
            let member = MemberResponse(seatId: "w#0", workerId: "w", status: status)
            for next in MemberStatus.allCases {
                XCTAssertFalse(member.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }
}
