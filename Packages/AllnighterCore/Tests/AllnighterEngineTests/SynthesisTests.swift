import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class SynthesisTests: XCTestCase {

    private func sampleRun() -> CouncilRun {
        CouncilRun(
            id: "run1",
            prompt: "Team accounts or analytics first?",
            status: .answersIn,
            panel: ["worker_opus", "worker_grok", "worker_gemini"],
            members: [
                MemberResponse(workerId: "worker_opus", status: .done, output: "Team accounts first."),
                MemberResponse(workerId: "worker_grok", status: .done, output: "Accounts, then analytics."),
                MemberResponse(workerId: "worker_gemini", status: .timedOut, errorKind: .timedOut, errorReason: "no output for 120s")
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

    func testPromptIncludesAnswersAndMissingNote() {
        let prompt = SynthesisPromptBuilder.build(
            run: sampleRun(),
            workers: workers(),
            instructions: SynthesisInstructions.defaultText
        )
        XCTAssertTrue(prompt.contains("Opus 4.8"))
        XCTAssertTrue(prompt.contains("Team accounts first."))
        XCTAssertTrue(prompt.contains("Grok Build"))
        // The failed worker is disclosed, not silently dropped.
        XCTAssertTrue(prompt.contains("Panel completeness"))
        XCTAssertTrue(prompt.contains("Gemini Flash"))
        XCTAssertTrue(prompt.contains("no output for 120s"))
    }

    func testSynthesizerProducesMasterPlan() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Master Plan\n\n## The Plan\nDo accounts.", exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let opus = workers()[0]

        let result = await synth.synthesize(run: sampleRun(), synthesizer: opus, manifest: manifest, workers: workers())
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.synthesizerWorkerId, "worker_opus")
        XCTAssertTrue(result.masterPlanMarkdown?.contains("Master Plan") ?? false)
    }

    func testSynthesizerFailureIsReported() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stderr: "boom", exitCode: 1)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let result = await synth.synthesize(run: sampleRun(), synthesizer: workers()[0], manifest: manifest, workers: workers())
        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.masterPlanMarkdown)
    }

    func testBundleContainsPromptMembersAndPlan() {
        var run = sampleRun()
        run.synthesis = Synthesis(
            synthesizerWorkerId: "worker_opus",
            instructions: SynthesisInstructions.defaultID,
            masterPlanMarkdown: "# Master Plan\nShip accounts.",
            status: .complete
        )
        let bundle = RunMarkdown.bundle(run, workers: workers())
        XCTAssertTrue(bundle.contains("Team accounts or analytics first?"))
        XCTAssertTrue(bundle.contains("Master Plan"))
        XCTAssertTrue(bundle.contains("Opus 4.8"))
        XCTAssertTrue(bundle.contains("timed_out"))
    }

    func testRunStoreWritesArtifacts() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("allnighter-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var run = sampleRun()
        run.synthesis = Synthesis(
            synthesizerWorkerId: "worker_opus",
            instructions: SynthesisInstructions.defaultID,
            masterPlanMarkdown: "# Master Plan\nShip.",
            status: .complete
        )
        let store = RunStore(rootDirectory: tmp)
        let dir = try store.save(run, workers: workers())

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("run.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bundle.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("master_plan.md").path))
        XCTAssertEqual(store.list().count, 1)
    }
}
