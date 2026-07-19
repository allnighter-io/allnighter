import XCTest
import AgentOSTeam
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
        for status in [RunStatus.draft, .queued, .running, .fanningOut, .answersIn, .planning, .reviewing, .finalizing] {
            let run = TeamRun(id: "r", prompt: "p", status: status, createdAt: Date())
            XCTAssertTrue(run.canTransition(to: .cancelled), "\(status) -> cancelled should be legal")
            XCTAssertTrue(run.canTransition(to: .failed), "\(status) -> failed should be legal")
        }
    }

    func testOneWorkerQueuedRunningPath() {
        // RLR-L3: queued → running, and a one-worker `running` still advances into
        // the multi-stage synthesis machine (answers_in → planning → done/complete).
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .queued, createdAt: Date()).canTransition(to: .running))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .running, createdAt: Date()).canTransition(to: .answersIn))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .running, createdAt: Date()).canTransition(to: .done))
        XCTAssertTrue(TeamRun(id: "r", prompt: "p", status: .running, createdAt: Date()).canTransition(to: .complete))
        XCTAssertTrue(RunStatus.done.isTerminal)
        XCTAssertTrue(RunStatus.timedOut.isTerminal)
        XCTAssertFalse(RunStatus.queued.isTerminal)
        XCTAssertFalse(RunStatus.running.isTerminal)
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
        for status in [RunStatus.complete, .partial, .done, .timedOut, .cancelled, .failed, .interrupted] {
            XCTAssertTrue(status.isTerminal)
            let run = TeamRun(id: "r", prompt: "p", status: status, createdAt: Date())
            for next in RunStatus.allCases {
                XCTAssertFalse(run.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }

    // MARK: Member state machine

    func testMemberHappyPath() {
        XCTAssertTrue(TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: .queued)).canTransition(to: .running))
        XCTAssertTrue(TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: .running)).canTransition(to: .done))
    }

    func testMemberTimeoutAndFailureFromRunning() {
        let running = TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: .running))
        XCTAssertTrue(running.canTransition(to: .timedOut))
        XCTAssertTrue(running.canTransition(to: .failed))
        XCTAssertTrue(running.canTransition(to: .cancelled))
    }

    func testManualPasteSkippedCanComplete() {
        let skipped = TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: .skipped))
        XCTAssertTrue(skipped.canTransition(to: .done))
        XCTAssertTrue(skipped.canTransition(to: .running))
    }

    func testMemberIllegalTransitionsRejected() {
        XCTAssertFalse(TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: .queued)).canTransition(to: .done))
        XCTAssertFalse(TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: .done)).canTransition(to: .running))
    }

    func testMemberTerminalStatesAreSinks() {
        for status in [WorkerAnswerStatus.done, .failed, .timedOut, .cancelled] {
            XCTAssertTrue(status.isTerminal)
            let member = TeamAnswer(memberId: "w#0", modelId: "w", role: "answer", result: WorkerRunResult(status: status))
            for next in WorkerAnswerStatus.allCases {
                XCTAssertFalse(member.canTransition(to: next), "\(status) is terminal; -> \(next) must be rejected")
            }
        }
    }
}
