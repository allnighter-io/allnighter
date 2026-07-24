import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

final class SynthesisTests: XCTestCase {

    private func sampleRun() -> TeamRun {
        TeamRun(
            id: "run1",
            prompt: "Team accounts or analytics first?",
            status: .answersIn,
            workers: [TestSupport.seat("model_opus"), TestSupport.seat("model_grok"), TestSupport.seat("model_gemini")],
            workerAnswers: [
                TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "answer", result: WorkerRunResult(status: .done, output: "Team accounts first.")),
                TeamAnswer(memberId: "model_grok#0", modelId: "model_grok", role: "answer", result: WorkerRunResult(status: .done, output: "Accounts, then analytics.")),
                TeamAnswer(memberId: "model_gemini#0", modelId: "model_gemini", role: "answer", result: WorkerRunResult(status: .timedOut, errorKind: .timedOut, errorReason: "no output for 120s"))
            ],
            createdAt: Date()
        )
    }

    private func models() -> [Model] {
        [
            Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both),
            Model(id: "model_grok", displayName: "Grok Build", modelLabel: "Grok Build", driverId: "grok"),
            Model(id: "model_gemini", displayName: "Gemini Flash", modelLabel: "gemini", driverId: "gemini")
        ]
    }

    private func opus() -> Model { models()[0] }

    private let combinedOutput = """
    ```json
    {"consensus":[{"statement":"Accounts first","sourceWorkerIds":["model_opus#0"],"strength":"strong"}],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":["migration"],"failedWorkers":[{"workerId":"model_gemini#0","reason":"no output for 120s"}]}
    ```
    ===PLAN===
    # Plan

    ## The Plan
    Do accounts.
    """

    func testAnalysisPromptIncludesAnswersAndMissingNote() {
        let prompt = SynthesisPromptBuilder.analysisPrompt(
            run: sampleRun(), models: models(), instructions: SynthesisInstructions.analysisText
        )
        XCTAssertTrue(prompt.contains("Opus 5"))
        XCTAssertTrue(prompt.contains("Team accounts first."))
        XCTAssertTrue(prompt.contains("[model model_opus]"))
        XCTAssertTrue(prompt.contains("Team completeness"))
        XCTAssertTrue(prompt.contains("no output for 120s"))
    }

    func testCombinedProducesAnalysisAndPlanStages() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: combinedOutput, exitCode: 0)])
        let synth = PlanWriter(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), planWriter: opus(), manifest: manifest, models: models(),
            config: TestSupport.config(planWriter: "model_opus", depth: .combined)
        )
        XCTAssertEqual(stages.count, 2)
        let analysis = stages.first { $0.purpose == .analysis }
        let plan = stages.first { $0.purpose == .plan }
        XCTAssertEqual(analysis?.status, .done)
        XCTAssertEqual(analysis?.payload?.analysis?.consensus.first?.statement, "Accounts first")
        XCTAssertEqual(plan?.status, .done)
        XCTAssertTrue(plan?.payload?.markdown?.contains("## The Plan") ?? false)
        XCTAssertEqual(plan?.promptProfileId, SynthesisInstructions.planID)
    }

    func testCombinedRecoversPlanWhenAnalysisJSONMissing() async {
        // No JSON block, but a plan after the sentinel — never lose the plan.
        let output = "garble garble\n===PLAN===\n# Plan\nShip it."
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: output, exitCode: 0)])
        let synth = PlanWriter(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), planWriter: opus(), manifest: manifest, models: models(),
            config: TestSupport.config(planWriter: "model_opus", depth: .combined)
        )
        XCTAssertEqual(stages.first { $0.purpose == .analysis }?.status, .failed)
        XCTAssertEqual(stages.first { $0.purpose == .plan }?.status, .done)
    }

    func testSeparatePathRunsTwoReduces() async {
        // Analysis call returns JSON; plan call returns markdown.
        let analysisJSON = "```json\n{\"consensus\":[],\"contradictions\":[],\"partialCoverage\":[],\"uniqueInsights\":[],\"blindSpots\":[],\"failedWorkers\":[]}\n```"
        // Same command for both; the mock returns the same script — craft one
        // that satisfies analysis (JSON) and a plan extraction is non-empty.
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: analysisJSON, exitCode: 0)])
        let synth = PlanWriter(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), planWriter: opus(), manifest: manifest, models: models(),
            config: TestSupport.config(planWriter: "model_opus", depth: .separate)
        )
        XCTAssertEqual(stages.count, 2)
        XCTAssertEqual(stages.first { $0.purpose == .analysis }?.status, .done)
        // The plan reduce got the JSON text as "markdown" — non-empty, so done.
        XCTAssertEqual(stages.first { $0.purpose == .plan }?.status, .done)
    }

    func testPlanWriterFailureIsReported() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stderr: "boom", exitCode: 1)])
        let synth = PlanWriter(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), planWriter: opus(), manifest: manifest, models: models(),
            config: TestSupport.config(planWriter: "model_opus", depth: .combined)
        )
        XCTAssertTrue(stages.allSatisfy { $0.status == .failed })
    }

    func testBundleContainsPromptMembersAnalysisAndPlan() {
        var run = sampleRun()
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(PlanAnalysis(consensus: [AnalysisPoint(statement: "Accounts first")]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan\nShip accounts."))
        ]
        run.status = .complete
        let bundle = RunMarkdown.bundle(run, models: models())
        XCTAssertTrue(bundle.contains("Team accounts or analytics first?"))
        XCTAssertTrue(bundle.contains("Team Analysis"))
        XCTAssertTrue(bundle.contains("Plan"))
        XCTAssertTrue(bundle.contains("Opus 5"))
        XCTAssertTrue(bundle.contains("timed_out"))
    }

    func testRunStoreWritesArtifacts() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var run = sampleRun()
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(PlanAnalysis(blindSpots: ["x"]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Plan\nShip."))
        ]
        run.status = .complete
        let store = RunStore(rootDirectory: tmp)
        let dir = try store.save(run, models: models())

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("run.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bundle.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("analysis.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("master_plan.md").path))
        XCTAssertEqual(store.list().count, 1)
    }
}
