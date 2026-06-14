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
        for status in [RunStatus.draft, .fanningOut, .answersIn, .synthesizing] {
            let run = CouncilRun(id: "r", prompt: "p", status: status, createdAt: Date())
            XCTAssertTrue(run.canTransition(to: .cancelled), "\(status) -> cancelled should be legal")
            XCTAssertTrue(run.canTransition(to: .failed), "\(status) -> failed should be legal")
        }
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
        XCTAssertTrue(MemberResponse(workerId: "w", status: .queued).canTransition(to: .running))
        XCTAssertTrue(MemberResponse(workerId: "w", status: .running).canTransition(to: .done))
    }

    func testMemberTimeoutAndFailureFromRunning() {
        let running = MemberResponse(workerId: "w", status: .running)
        XCTAssertTrue(running.canTransition(to: .timedOut))
        XCTAssertTrue(running.canTransition(to: .failed))
        XCTAssertTrue(running.canTransition(to: .cancelled))
    }

    func testManualPasteSkippedCanComplete() {
        let skipped = MemberResponse(workerId: "w", status: .skipped)
        XCTAssertTrue(skipped.canTransition(to: .done))
        XCTAssertTrue(skipped.canTransition(to: .running))
    }

    func testMemberIllegalTransitionsRejected() {
        XCTAssertFalse(MemberResponse(workerId: "w", status: .queued).canTransition(to: .done))
        XCTAssertFalse(MemberResponse(workerId: "w", status: .done).canTransition(to: .running))
    }

    func testMemberTerminalStatesAreSinks() {
        for status in [MemberStatus.done, .failed, .timedOut, .cancelled] {
            XCTAssertTrue(status.isTerminal)
            let member = MemberResponse(workerId: "w", status: status)
            for next in MemberStatus.allCases {
                XCTAssertFalse(member.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }
}
