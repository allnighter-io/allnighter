import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ReturnReviewTests: XCTestCase {

    private func dispatchedRun(returnStatus: ExecutionStatus) -> TeamRun {
        var run = TeamRun(id: "r", prompt: "Build X", status: .complete,
                             workers: [TestSupport.seat("model_opus")],
                             workerAnswers: [WorkerAnswer(workerId: "model_opus#0", modelId: "model_opus", status: .done, output: "a", durationMs: 1000)],
                             createdAt: Date())
        run.stages = [
            StageOutput(id: "p", purpose: .plan, producedByWorkerId: "model_opus", status: .done, payload: .plan(markdown: "# Plan")),
            StageOutput(id: "f", purpose: .finalSpec, producedByWorkerId: "model_opus", status: .done, payload: .finalSpec(FinalSpecPayload(markdown: "## Acceptance criteria\n- Compiles\n- Tests pass"))),
            StageOutput(id: "d", purpose: .dispatch, producedByWorkerId: "model_grok", status: returnStatus == .done ? .done : .failed,
                        payload: .dispatch(ExecutionReturn(id: "er", executionWorkerId: "model_grok", workingDirectory: "/tmp", dispatchIndex: 1, status: returnStatus, transcriptExcerpt: "did the work")))
        ]
        return run
    }

    func testExtractAcceptanceCriteria() {
        let spec = "## Scope\nx\n## Acceptance criteria\n- Compiles\n- Tests pass\n## Risks\ny"
        XCTAssertEqual(AcceptanceCriteria.extract(from: spec), ["Compiles", "Tests pass"])
    }

    func testReturnReviewParsesRecommendation() async {
        let output = "The work looks complete.\n===ROUTING===\n```json\n{\"action\":\"pick\",\"reasoning\":\"met all criteria\"}\n```"
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: output, exitCode: 0)])
        let reviewer = ReturnReviewer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let run = dispatchedRun(returnStatus: .done)
        let ret = run.latestStage(.dispatch)!.payload!.executionReturn!

        let stage = await reviewer.review(run: run, executionReturn: ret, reviewer: worker, manifest: manifest, profile: BuiltInProfiles.returnReview)
        XCTAssertEqual(stage.purpose, .returnReview)
        XCTAssertEqual(stage.payload?.returnReview?.recommendation?.action, .pick)
    }

    func testFailedReturnDefaultsToRerunRecommendation() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "It crashed. No routing block.", exitCode: 0)])
        let reviewer = ReturnReviewer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let run = dispatchedRun(returnStatus: .failed)
        let ret = run.latestStage(.dispatch)!.payload!.executionReturn!

        let stage = await reviewer.review(run: run, executionReturn: ret, reviewer: worker, manifest: manifest, profile: BuiltInProfiles.returnReview)
        XCTAssertEqual(stage.payload?.returnReview?.recommendation?.action, .rerun)
    }

    func testScorecardAggregatesHistory() {
        let runs = [dispatchedRun(returnStatus: .done), dispatchedRun(returnStatus: .failed)]
        let cards = ScorecardBuilder.build(from: runs)
        let opus = cards.first(where: { $0.workerId == "model_opus" })
        let grok = cards.first(where: { $0.workerId == "model_grok" })
        XCTAssertEqual(opus?.panelAnswerRate, 1.0)             // answered both times as a seat
        XCTAssertEqual(opus?.judgeSuccessRate, 1.0)            // produced a usable plan both times
        XCTAssertEqual(grok?.executionSuccessRate, 0.5)        // 1 of 2 dispatches done
        XCTAssertFalse(opus?.hasEnoughData ?? true)            // only 2 runs -> insufficient
    }
}
