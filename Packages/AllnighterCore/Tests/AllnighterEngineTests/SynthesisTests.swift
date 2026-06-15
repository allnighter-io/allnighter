import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class SynthesisTests: XCTestCase {

    private func sampleRun() -> CouncilRun {
        CouncilRun(
            id: "run1",
            prompt: "Team accounts or analytics first?",
            status: .answersIn,
            panel: [TestSupport.seat("worker_opus"), TestSupport.seat("worker_grok"), TestSupport.seat("worker_gemini")],
            members: [
                MemberResponse(seatId: "worker_opus#0", workerId: "worker_opus", status: .done, output: "Team accounts first."),
                MemberResponse(seatId: "worker_grok#0", workerId: "worker_grok", status: .done, output: "Accounts, then analytics."),
                MemberResponse(seatId: "worker_gemini#0", workerId: "worker_gemini", status: .timedOut, errorKind: .timedOut, errorReason: "no output for 120s")
            ],
            createdAt: Date()
        )
    }

    private func workers() -> [Worker] {
        [
            Worker(id: "worker_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both),
            Worker(id: "worker_grok", displayName: "Grok Build", modelLabel: "Grok Build", driverId: "grok"),
            Worker(id: "worker_gemini", displayName: "Gemini Flash", modelLabel: "gemini", driverId: "gemini")
        ]
    }

    private func opus() -> Worker { workers()[0] }

    private let combinedOutput = """
    ```json
    {"consensus":[{"statement":"Accounts first","sourceSeatIds":["worker_opus#0"],"strength":"strong"}],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":["migration"],"failedSeats":[{"seatId":"worker_gemini#0","reason":"no output for 120s"}]}
    ```
    ===PLAN===
    # Master Plan

    ## The Plan
    Do accounts.
    """

    func testAnalysisPromptIncludesAnswersAndMissingNote() {
        let prompt = SynthesisPromptBuilder.analysisPrompt(
            run: sampleRun(), workers: workers(), instructions: SynthesisInstructions.analysisText
        )
        XCTAssertTrue(prompt.contains("Opus 4.8"))
        XCTAssertTrue(prompt.contains("Team accounts first."))
        XCTAssertTrue(prompt.contains("worker_opus#0"))
        XCTAssertTrue(prompt.contains("Panel completeness"))
        XCTAssertTrue(prompt.contains("no output for 120s"))
    }

    func testCombinedProducesAnalysisAndPlanStages() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: combinedOutput, exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), judge: opus(), manifest: manifest, workers: workers(),
            config: TestSupport.config(judge: "worker_opus", depth: .combined)
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
        let output = "garble garble\n===PLAN===\n# Master Plan\nShip it."
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: output, exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), judge: opus(), manifest: manifest, workers: workers(),
            config: TestSupport.config(judge: "worker_opus", depth: .combined)
        )
        XCTAssertEqual(stages.first { $0.purpose == .analysis }?.status, .failed)
        XCTAssertEqual(stages.first { $0.purpose == .plan }?.status, .done)
    }

    func testSeparatePathRunsTwoReduces() async {
        // Analysis call returns JSON; plan call returns markdown.
        let analysisJSON = "```json\n{\"consensus\":[],\"contradictions\":[],\"partialCoverage\":[],\"uniqueInsights\":[],\"blindSpots\":[],\"failedSeats\":[]}\n```"
        // Same command for both; the mock returns the same script — craft one
        // that satisfies analysis (JSON) and a plan extraction is non-empty.
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: analysisJSON, exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), judge: opus(), manifest: manifest, workers: workers(),
            config: TestSupport.config(judge: "worker_opus", depth: .separate)
        )
        XCTAssertEqual(stages.count, 2)
        XCTAssertEqual(stages.first { $0.purpose == .analysis }?.status, .done)
        // The plan reduce got the JSON text as "markdown" — non-empty, so done.
        XCTAssertEqual(stages.first { $0.purpose == .plan }?.status, .done)
    }

    func testSynthesizerFailureIsReported() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stderr: "boom", exitCode: 1)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), judge: opus(), manifest: manifest, workers: workers(),
            config: TestSupport.config(judge: "worker_opus", depth: .combined)
        )
        XCTAssertTrue(stages.allSatisfy { $0.status == .failed })
    }

    func testBundleContainsPromptMembersAnalysisAndPlan() {
        var run = sampleRun()
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(consensus: [AnalysisPoint(statement: "Accounts first")]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Master Plan\nShip accounts."))
        ]
        run.status = .complete
        let bundle = RunMarkdown.bundle(run, workers: workers())
        XCTAssertTrue(bundle.contains("Team accounts or analytics first?"))
        XCTAssertTrue(bundle.contains("Council Analysis"))
        XCTAssertTrue(bundle.contains("Master Plan"))
        XCTAssertTrue(bundle.contains("Opus 4.8"))
        XCTAssertTrue(bundle.contains("timed_out"))
    }

    func testRunStoreWritesArtifacts() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("allnighter-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var run = sampleRun()
        run.stages = [
            StageOutput(id: "a", purpose: .analysis, status: .done, payload: .analysis(JudgeAnalysis(blindSpots: ["x"]))),
            StageOutput(id: "p", purpose: .plan, status: .done, payload: .plan(markdown: "# Master Plan\nShip."))
        ]
        run.status = .complete
        let store = RunStore(rootDirectory: tmp)
        let dir = try store.save(run, workers: workers())

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("run.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bundle.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("analysis.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("master_plan.md").path))
        XCTAssertEqual(store.list().count, 1)
    }
}
