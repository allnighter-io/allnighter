import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DispatcherTests: XCTestCase {

    private func runWithFinalSpec() -> CouncilRun {
        var run = CouncilRun(id: "r", prompt: "Build X", status: .complete,
                             panel: [TestSupport.seat("worker_opus")],
                             members: [MemberResponse(seatId: "worker_opus#0", workerId: "worker_opus", status: .done, output: "a")],
                             createdAt: Date())
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(consensus: [AnalysisPoint(statement: "actor")]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan")),
            StageOutput(id: "f", purpose: .finalSpec, status: .done, payload: .finalSpec(FinalSpecPayload(markdown: "# Final Spec\nDo it.", reviewDecisions: [ReviewDecision(lensId: "security_privacy", decision: .adopted, reason: "ok")], hasProofCommands: true)))
        ]
        return run
    }

    func testBriefPrefersFinalSpec() {
        let brief = BriefBuilder.build(run: runWithFinalSpec(), executionWorkerId: "worker_opus", workingDirectory: "/tmp")
        XCTAssertEqual(brief?.sourceArtifact, .finalSpec)
        XCTAssertFalse(brief?.isLessReviewed ?? true)
        XCTAssertNotNil(brief?.decisions)
        XCTAssertTrue(brief?.judgmentSummary.contains("actor") ?? false)
    }

    func testBriefFallsBackToMasterPlanLessReviewed() {
        var run = runWithFinalSpec()
        run.stages.removeAll { $0.purpose == .finalSpec }
        let brief = BriefBuilder.build(run: run, executionWorkerId: "worker_opus", workingDirectory: "/tmp")
        XCTAssertEqual(brief?.sourceArtifact, .masterPlan)
        XCTAssertTrue(brief?.isLessReviewed ?? false)
        XCTAssertNil(brief?.decisions)
    }

    func testRevealOnlyWritesArtifactsWithoutInvoking() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("disp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        // A command runner that would error if invoked — proves reveal didn't call it.
        let mock = MockCommandRunner(scripts: ["claude": .init(launchError: "should not run")])
        let dispatcher = Dispatcher(workerRunner: WorkerRunner(commandRunner: mock))
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let brief = BriefBuilder.build(run: runWithFinalSpec(), executionWorkerId: worker.id, workingDirectory: NSTemporaryDirectory())!

        let stage = await dispatcher.dispatch(brief: brief, worker: worker, manifest: manifest, healthy: true, revealOnly: true, dispatchIndex: 1, artifactsDir: tmp)
        XCTAssertEqual(stage.payload?.executionReturn?.status, .reveal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("implementation_brief.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("execution_prompt_worker_opus_01.md").path))
    }

    func testHealthyDispatchInvokesAndCapturesTranscript() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("disp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "Implemented. swift test passed.", exitCode: 0)])
        let dispatcher = Dispatcher(workerRunner: WorkerRunner(commandRunner: mock))
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        // Working dir must exist + be writable.
        let workDir = NSTemporaryDirectory()
        let brief = BriefBuilder.build(run: runWithFinalSpec(), executionWorkerId: worker.id, workingDirectory: workDir)!

        let stage = await dispatcher.dispatch(brief: brief, worker: worker, manifest: manifest, healthy: true, revealOnly: false, dispatchIndex: 1, artifactsDir: tmp)
        XCTAssertEqual(stage.purpose, .dispatch)
        XCTAssertEqual(stage.payload?.executionReturn?.status, .done)
        XCTAssertTrue(stage.payload?.executionReturn?.transcriptExcerpt?.contains("Implemented") ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dispatch_01/transcript.txt").path))
    }

    func testInvalidWorkingDirRevealsWithReason() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("disp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let dispatcher = Dispatcher(workerRunner: WorkerRunner(commandRunner: mock))
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let brief = BriefBuilder.build(run: runWithFinalSpec(), executionWorkerId: worker.id, workingDirectory: "/no/such/dir/here")!

        let stage = await dispatcher.dispatch(brief: brief, worker: worker, manifest: manifest, healthy: true, revealOnly: false, dispatchIndex: 1, artifactsDir: tmp)
        XCTAssertEqual(stage.payload?.executionReturn?.status, .reveal)
        XCTAssertTrue(stage.payload?.executionReturn?.transcriptExcerpt?.contains("working directory") ?? false)
    }
}
