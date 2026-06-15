import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ReviewCoordinatorTests: XCTestCase {

    private func completedRun() -> CouncilRun {
        var run = CouncilRun(id: "r", prompt: "Build X", status: .complete,
                             panel: [TestSupport.seat("worker_opus"), TestSupport.seat("worker_grok")],
                             members: [
                                MemberResponse(seatId: "worker_opus#0", workerId: "worker_opus", status: .done, output: "Use an actor."),
                                MemberResponse(seatId: "worker_grok#0", workerId: "worker_grok", status: .done, output: "Use a queue.")
                             ],
                             createdAt: Date())
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(consensus: [AnalysisPoint(statement: "concurrency matters")]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan\nActor."))
        ]
        return run
    }

    private func lens(_ id: String, worker: Worker, manifest: DriverManifest) -> ResolvedLens {
        ResolvedLens(
            lensId: id,
            profile: PromptProfile(id: id, displayName: id, purpose: .reviewLens, template: "Review as \(id)."),
            worker: worker, manifest: manifest,
            inputSelectors: ReviewCoordinator.defaultSelectors(forLens: id)
        )
    }

    func testReviewFanoutProducesReviewStagesInOrder() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "review body", exitCode: 0)])
        let coord = ReviewCoordinator(reduceRunner: ReduceRunner(workerRunner: WorkerRunner(commandRunner: mock)))
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let lenses = ["security_privacy", "code_maintainer", "proof_qa"].map { lens($0, worker: worker, manifest: manifest) }
        let stages = await coord.review(run: completedRun(), workers: [worker], lenses: lenses)

        XCTAssertEqual(stages.count, 3)
        XCTAssertTrue(stages.allSatisfy { $0.purpose == .review && $0.status == .done })
        XCTAssertEqual(stages.map { $0.payload?.review?.lensId }, ["security_privacy", "code_maintainer", "proof_qa"])
    }

    func testFailedLensDoesNotBlockOthers() async {
        // grok times out; claude succeeds.
        let mock = MockCommandRunner(scripts: [
            "claude": .init(stdout: "ok review", exitCode: 0),
            "grok": .init(forcesTimeout: true)
        ])
        let coord = ReviewCoordinator(reduceRunner: ReduceRunner(workerRunner: WorkerRunner(commandRunner: mock)))
        let opus = TestSupport.worker("worker_opus", driverId: "claude_code")
        let grok = TestSupport.worker("worker_grok", driverId: "grok")
        let claudeM = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let grokM = TestSupport.headlessManifest(id: "grok", command: "grok")

        let lenses = [lens("security_privacy", worker: opus, manifest: claudeM), lens("proof_qa", worker: grok, manifest: grokM)]
        let stages = await coord.review(run: completedRun(), workers: [opus, grok], lenses: lenses)

        XCTAssertEqual(stages.count, 2)
        XCTAssertEqual(stages.first { $0.payload?.review?.lensId == "security_privacy" }?.status, .done)
        XCTAssertEqual(stages.first { $0.promptProfileId == "proof_qa" }?.status, .timedOut)
    }

    func testDissentLensGetsMemberAnswers() {
        XCTAssertTrue(ReviewCoordinator.defaultSelectors(forLens: "dissent_preserver").contains(.memberAnswers))
        XCTAssertFalse(ReviewCoordinator.defaultSelectors(forLens: "security_privacy").contains(.memberAnswers))
    }

    func testReviewsRenderInBundleAndStore() throws {
        var run = completedRun()
        run.stages.append(StageOutput(id: "rv", purpose: .review, promptProfileId: "security_privacy", status: .done, payload: .review(ReviewResult(lensId: "security_privacy", markdown: "Token in plaintext."))))
        let bundle = RunMarkdown.bundle(run, workers: [])
        XCTAssertTrue(bundle.contains("## Reviews"))
        XCTAssertTrue(bundle.contains("Token in plaintext."))

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rb2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dir = try RunStore(rootDirectory: tmp).save(run, workers: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("review_security_privacy.md").path))
    }
}
