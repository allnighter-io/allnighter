import XCTest
@testable import AllnighterCore

final class StateMachineTests: XCTestCase {

    // MARK: Run state machine

    func testRunHappyPath() {
        let run = TeamRun(id: "r", prompt: "p", status: .draft, createdAt: Date())
        XCTAssertTrue(run.canTransition(to: .fanningOut))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .fanningOut, createdAt: Date()).canTransition(to: .answersIn))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .answersIn, createdAt: Date()).canTransition(to: .planning))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .planning, createdAt: Date()).canTransition(to: .complete))
    }

    func testRunSynthesisFailureGoesPartial() {
        let run = TeamRun(id: "r", prompt: "p", status: .planning, createdAt: Date())
        XCTAssertTrue(run.canTransition(to: .partial))
    }

    func testRunCancelAndFailReachableWhileActive() {
        for status in [RunStatus.draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing] {
            let run = TeamRun(id: "r", prompt: "p", status: status, createdAt: Date())
            XCTAssertTrue(run.canTransition(to: .cancelled), "\(status) -> cancelled should be legal")
            XCTAssertTrue(run.canTransition(to: .failed), "\(status) -> failed should be legal")
        }
    }

    func testReviewAndFinalizePath() {
        // answers_in -> reviewing -> finalizing -> complete (review-board presets).
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .answersIn, createdAt: Date()).canTransition(to: .reviewing))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .reviewing, createdAt: Date()).canTransition(to: .finalizing))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .finalizing, createdAt: Date()).canTransition(to: .complete))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .finalizing, createdAt: Date()).canTransition(to: .partial))
        // planning can also enter reviewing (synthesis-then-review).
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .planning, createdAt: Date()).canTransition(to: .reviewing))
        XCTAssertFalse(RunStatus.reviewing.isTerminal)
        XCTAssertFalse(RunStatus.finalizing.isTerminal)
    }

    func testRunIllegalTransitionsRejected() {
        XCTAssertFalse(TeamRun(id: "r", prompt: "p", status: .draft, createdAt: Date()).canTransition(to: .complete))
        XCTAssertFalse(TeamRun(id: "r", prompt: "p", status: .answersIn, createdAt: Date()).canTransition(to: .fanningOut))
        XCTAssertFalse(TeamRun(id: "r", prompt: "p", status: .fanningOut, createdAt: Date()).canTransition(to: .complete))
    }

    func testRunTerminalStatesAreSinks() {
        for status in [RunStatus.complete, .partial, .cancelled, .failed] {
            XCTAssertTrue(status.isTerminal)
            let run = TeamRun(id: "r", prompt: "p", status: status, createdAt: Date())
            for next in RunStatus.allCases {
                XCTAssertFalse(run.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }

    // MARK: Member state machine

    func testMemberHappyPath() {
        XCTAssertTrue(WorkerAnswer(workerId: "w#0", modelId: "w", status: .queued).canTransition(to: .running))
        XCTAssertTrue(WorkerAnswer(workerId: "w#0", modelId: "w", status: .running).canTransition(to: .done))
    }

    func testMemberTimeoutAndFailureFromRunning() {
        let running = WorkerAnswer(workerId: "w#0", modelId: "w", status: .running)
        XCTAssertTrue(running.canTransition(to: .timedOut))
        XCTAssertTrue(running.canTransition(to: .failed))
        XCTAssertTrue(running.canTransition(to: .cancelled))
    }

    func testManualPasteSkippedCanComplete() {
        let skipped = WorkerAnswer(workerId: "w#0", modelId: "w", status: .skipped)
        XCTAssertTrue(skipped.canTransition(to: .done))
        XCTAssertTrue(skipped.canTransition(to: .running))
    }

    func testMemberIllegalTransitionsRejected() {
        XCTAssertFalse(WorkerAnswer(workerId: "w#0", modelId: "w", status: .queued).canTransition(to: .done))
        XCTAssertFalse(WorkerAnswer(workerId: "w#0", modelId: "w", status: .done).canTransition(to: .running))
    }

    func testMemberTerminalStatesAreSinks() {
        for status in [WorkerAnswerStatus.done, .failed, .timedOut, .cancelled] {
            XCTAssertTrue(status.isTerminal)
            let member = WorkerAnswer(workerId: "w#0", modelId: "w", status: status)
            for next in WorkerAnswerStatus.allCases {
                XCTAssertFalse(member.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }
}
