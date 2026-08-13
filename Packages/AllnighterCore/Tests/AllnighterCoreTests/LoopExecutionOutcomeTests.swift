import XCTest
@testable import AllnighterCore
import AgentOSTeam

/// OCL-S07: execution outcome is Allnighter-owned. The seat's report is never evidence.
final class LoopExecutionOutcomeTests: XCTestCase {
    private let lie = "the change is applied and ready for review"

    func testLyingProseIsNotEvidenceWhenProofFails() {
        let run = mutatingRun(
            worker: WorkerRunResult(status: .done, output: lie),
            delta: RepoDelta(changed: false, worktreeDirty: true)
        )
        let proofs = [
            HarnessProofResult(
                command: "swift build",
                exitCode: 1,
                durationMs: 800,
                outputTail: "error: cannot find 'foo' in scope"
            )
        ]
        let outcome = LoopExecutionOutcome.evaluate(run: run, proofResults: proofs)
        XCTAssertEqual(outcome?.status, .failed)
        XCTAssertTrue(outcome?.reasons.contains { $0.contains("swift build") && $0.contains("1") } == true)
        XCTAssertFalse(outcome?.reasons.contains(lie) == true)
        XCTAssertFalse(outcome?.promptBlock().contains(lie) == true)
        XCTAssertTrue(outcome?.promptBlock().contains("status: failed") == true)
        XCTAssertTrue(outcome?.promptBlock().contains("claim, not evidence") == true)
    }

    func testWorkerFailedIsFailedEvenWithSuccessProse() {
        let run = mutatingRun(
            worker: WorkerRunResult(
                status: .failed,
                output: lie,
                errorReason: "incomplete_uncommitted"
            ),
            delta: RepoDelta(changed: false, worktreeDirty: true)
        )
        let outcome = LoopExecutionOutcome.evaluate(run: run)
        XCTAssertEqual(outcome?.status, .failed)
        XCTAssertTrue(outcome?.reasons.contains { $0.contains("incomplete_uncommitted") } == true)
        XCTAssertFalse(outcome?.reasons.contains(lie) == true)
    }

    func testMutatingDoneWithNoRepoEffectIsFailed() {
        let run = mutatingRun(
            worker: WorkerRunResult(status: .done, output: lie),
            delta: RepoDelta(changed: false, worktreeDirty: false)
        )
        let outcome = LoopExecutionOutcome.evaluate(run: run)
        XCTAssertEqual(outcome?.status, .failed)
        XCTAssertTrue(outcome?.reasons.contains { $0.contains("no repo effect") } == true)
        XCTAssertFalse(outcome?.reasons.contains(lie) == true)
    }

    func testDirtyTreeWithoutProofsIsCompletedNotFalseSuccess() {
        let run = mutatingRun(
            worker: WorkerRunResult(status: .done, output: lie),
            delta: RepoDelta(changed: false, worktreeDirty: true)
        )
        let outcome = LoopExecutionOutcome.evaluate(run: run)
        XCTAssertEqual(outcome?.status, .completed)
        XCTAssertTrue(outcome?.reasons.contains("repo had effect") == true)
        XCTAssertTrue(outcome?.reasons.contains("no declared proofs ran") == true)
        XCTAssertFalse(outcome?.reasons.contains(lie) == true)
    }

    func testNilRunIsNotInventedSuccess() {
        XCTAssertNil(LoopExecutionOutcome.evaluate(run: nil))
    }

    func testStandingFailureFailsTheTurn() {
        let run = mutatingRun(
            worker: WorkerRunResult(status: .done, output: lie),
            delta: RepoDelta(changed: true, worktreeDirty: false)
        )
        let outcome = LoopExecutionOutcome.evaluate(
            run: run,
            standingFailed: ["contractDrift"]
        )
        XCTAssertEqual(outcome?.status, .failed)
        XCTAssertTrue(outcome?.reasons.contains { $0.contains("contractDrift") } == true)
    }

    private func mutatingRun(worker: WorkerRunResult, delta: RepoDelta) -> TeamRun {
        TeamRun(
            id: "run_local_exec",
            prompt: "one-line Swift edit",
            status: .complete,
            workers: [Agent(id: "local#0", modelId: "custom_opencode_ollama_qwen3_8b", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "local#0",
                modelId: "custom_opencode_ollama_qwen3_8b",
                role: "answer",
                result: worker
            )],
            createdAt: Date(),
            mutating: true,
            repoDelta: delta
        )
    }
}
