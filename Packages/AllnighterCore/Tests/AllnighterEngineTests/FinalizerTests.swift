import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class FinalizerTests: XCTestCase {

    private func run(withReview: Bool) -> CouncilRun {
        var run = CouncilRun(id: "r", prompt: "Build X", status: .complete,
                             panel: [TestSupport.seat("worker_opus")],
                             members: [MemberResponse(seatId: "worker_opus#0", workerId: "worker_opus", status: .done, output: "Use an actor.")],
                             createdAt: Date())
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(contradictions: [Contradiction(topic: "store", positions: [], recommendedResolution: "actor")]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan\nActor."))
        ]
        if withReview {
            run.stages.append(StageOutput(id: "rv", purpose: .review, promptProfileId: "security_privacy", status: .done, payload: .review(ReviewResult(lensId: "security_privacy", markdown: "Token in plaintext."))))
        }
        return run
    }

    private func finalizerWorker() -> Worker { TestSupport.worker("worker_opus", driverId: "claude_code", role: .both) }
    private var profile: PromptProfile { BuiltInProfiles.finalSpec }

    private let goodOutput = """
    ## Final Spec
    Build the store as an actor.

    ## Works Test and proof wall
    ```
    swift test
    ```

    ===DECISIONS===
    ```json
    {"reviewDecisions":[{"lensId":"security_privacy","decision":"adopted","reason":"valid"}],"contradictionDecisions":[{"topic":"store","resolution":"actor","reason":"safer"}],"insightDecisions":[]}
    ```
    """

    func testFinalizerProducesStructuredDecisionsAndProofFlag() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: goodOutput, exitCode: 0)])
        let fin = Finalizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stage = await fin.finalize(run: run(withReview: true), finalizer: finalizerWorker(), manifest: manifest, workers: [finalizerWorker()], profile: profile)
        XCTAssertEqual(stage.purpose, .finalSpec)
        XCTAssertEqual(stage.status, .done)
        let payload = stage.payload?.finalSpec
        XCTAssertEqual(payload?.reviewDecisions.first?.decision, .adopted)
        XCTAssertEqual(payload?.contradictionDecisions.first?.topic, "store")
        XCTAssertTrue(payload?.decisionsStructured ?? false)
        XCTAssertTrue(payload?.hasProofCommands ?? false)
        XCTAssertTrue(payload?.reviewBoardRan ?? false)
        XCTAssertFalse(stage.payload?.markdown?.contains("DECISIONS") ?? true)
    }

    func testFinalizerDegradesWhenDecisionsUnparseable() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "## Final Spec\nJust prose, no decisions block.", exitCode: 0)])
        let fin = Finalizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stage = await fin.finalize(run: run(withReview: false), finalizer: finalizerWorker(), manifest: manifest, workers: [finalizerWorker()], profile: profile)
        XCTAssertEqual(stage.status, .done)               // never fail a usable spec
        XCTAssertFalse(stage.payload?.finalSpec?.decisionsStructured ?? true)
        XCTAssertFalse(stage.payload?.finalSpec?.reviewBoardRan ?? true)  // zero-review path
        XCTAssertFalse(stage.payload?.finalSpec?.hasProofCommands ?? true)
    }
}
