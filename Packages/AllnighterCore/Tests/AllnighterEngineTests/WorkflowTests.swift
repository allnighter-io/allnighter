import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class WorkflowTests: XCTestCase {

    private func config() -> SynthesisConfig {
        SynthesisConfig(analysisProfileId: SynthesisInstructions.analysisID, planProfileId: SynthesisInstructions.planID)
    }

    private func reviewStage() -> WorkflowStage {
        WorkflowStage(
            id: "review", kind: .fanout, displayName: "Review", purpose: .review,
            inputSelectors: [.founderPrompt, .judgeAnalysis, .draftPlan],
            bindings: [StageBinding(id: "b1", promptProfileId: "security_privacy", workerId: "worker_opus")]
        )
    }

    private func finalStage() -> WorkflowStage {
        WorkflowStage(
            id: "final", kind: .reduce, displayName: "Final", purpose: .finalSpec,
            inputSelectors: [.founderPrompt, .memberAnswers, .judgeAnalysis, .draftPlan, .reviews],
            bindings: [StageBinding(id: "b2", promptProfileId: "final_spec_v1", workerId: "worker_opus")]
        )
    }

    // MARK: - Validation

    func testValidPresetOrderPasses() throws {
        let preset = WorkflowPreset(id: "p", displayName: "p", seats: [PanelSeatSpec(workerId: "worker_opus")], synthesis: config(), stages: [reviewStage(), finalStage()])
        XCTAssertNoThrow(try preset.validate())
    }

    func testReviewAfterFinalIsRejected() {
        let preset = WorkflowPreset(id: "p", displayName: "p", seats: [PanelSeatSpec(workerId: "worker_opus")], synthesis: config(), stages: [finalStage(), reviewStage()])
        XCTAssertThrowsError(try preset.validate())
    }

    func testMultipleFinalStagesRejected() {
        let preset = WorkflowPreset(id: "p", displayName: "p", seats: [PanelSeatSpec(workerId: "worker_opus")], synthesis: config(), stages: [finalStage(), finalStage()])
        XCTAssertThrowsError(try preset.validate())
    }

    func testAnalysisStageNotConfigurable() {
        let bad = WorkflowStage(id: "x", kind: .reduce, displayName: "x", purpose: .analysis, inputSelectors: [], bindings: [])
        let preset = WorkflowPreset(id: "p", displayName: "p", seats: [], synthesis: config(), stages: [bad])
        XCTAssertThrowsError(try preset.validate())
    }

    // MARK: - Profile registry

    func testProfileRegistryHasJudgeLensAndFinalProfiles() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = PromptProfileStore(rootDirectory: tmp)
        XCTAssertNotNil(store.profile(id: SynthesisInstructions.analysisID))
        XCTAssertNotNil(store.profile(id: "security_privacy"))
        XCTAssertNotNil(store.profile(id: "coverage_audit"))
        XCTAssertNotNil(store.profile(id: "final_spec_v1"))
        XCTAssertEqual(store.profiles(purpose: .reviewLens).count, 9)
        // Anti-echo baked into lenses.
        XCTAssertTrue(store.profile(id: "security_privacy")?.template.contains("Do not restate") ?? false)
    }

    // MARK: - Stage input assembly

    func testInputBuilderAssemblesSelectedSections() {
        var run = CouncilRun(id: "r", prompt: "Build X", status: .complete,
                             panel: [TestSupport.seat("worker_opus")],
                             members: [MemberResponse(seatId: "worker_opus#0", workerId: "worker_opus", status: .done, output: "Use an actor.")],
                             createdAt: Date())
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(consensus: [AnalysisPoint(statement: "actor")]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan\nDo it."))
        ]
        let workers = [Worker(id: "worker_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)]
        let prompt = StageInputBuilder.assemble(
            instructions: "REVIEW THIS", selectors: [.founderPrompt, .judgeAnalysis, .draftPlan, .memberAnswers],
            run: run, workers: workers
        )
        XCTAssertTrue(prompt.contains("REVIEW THIS"))
        XCTAssertTrue(prompt.contains("Build X"))
        XCTAssertTrue(prompt.contains("Judge analysis"))
        XCTAssertTrue(prompt.contains("Draft master plan"))
        XCTAssertTrue(prompt.contains("Use an actor."))
    }

    // MARK: - reuseKey

    func testReuseKeyStableForSameInputsAndChangesOnEdit() {
        let a = ReuseKey.compute(promptProfileId: "p1", customInstruction: nil, profileVersion: 1, resolvedInput: "abc", workerId: "w", modelLabel: "m")
        let same = ReuseKey.compute(promptProfileId: "p1", customInstruction: nil, profileVersion: 1, resolvedInput: "abc", workerId: "w", modelLabel: "m")
        let changedInput = ReuseKey.compute(promptProfileId: "p1", customInstruction: nil, profileVersion: 1, resolvedInput: "abcd", workerId: "w", modelLabel: "m")
        XCTAssertEqual(a, same)
        XCTAssertNotEqual(a, changedInput)
    }

    // MARK: - ReduceRunner

    func testReduceRunnerProducesReviewStage() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "Concern: tokens in plaintext.", exitCode: 0)])
        let runner = ReduceRunner(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")

        let stage = await runner.runMarkdown(
            purpose: .review, worker: worker, manifest: manifest,
            prompt: "review this", promptProfileId: "security_privacy"
        ) { .plan(markdown: $0) }
        XCTAssertEqual(stage.purpose, .review)
        XCTAssertEqual(stage.status, .done)
        XCTAssertEqual(stage.producedByWorkerId, "worker_opus")
    }

    func testWorkflowPresetStoreValidatesOnSave() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = WorkflowPresetStore(rootDirectory: tmp)
        let good = WorkflowPreset(id: "g", displayName: "g", seats: [PanelSeatSpec(workerId: "worker_opus")], synthesis: config(), stages: [reviewStage(), finalStage()])
        XCTAssertNoThrow(try store.save(good))
        XCTAssertEqual(store.load().count, 1)
        let bad = WorkflowPreset(id: "b", displayName: "b", seats: [], synthesis: config(), stages: [finalStage(), reviewStage()])
        XCTAssertThrowsError(try store.save(bad))
    }
}
