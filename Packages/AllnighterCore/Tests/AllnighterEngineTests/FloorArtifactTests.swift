import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// F-S01 Works Test (WT-FLOOR01): every worker return is preserved as an
/// inspectable artifact. Successful workers get `.answer.md`; EVERY worker —
/// including the failed one — gets `.metadata.json`; the failed worker stays
/// visible. The Floor projection carries matching artifact refs.
final class FloorArtifactTests: XCTestCase {
    private var tmp: URL!
    private var store: RunStore!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-floor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = RunStore(rootDirectory: tmp)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeRun() -> TeamRun {
        let workers = [
            Worker(id: "model_a#0", modelId: "model_a", instanceIndex: 0, skillId: "signal_source_reader",
                   skillName: "Source Reader", resolvedWorkerPromptSnapshot: "PROMPT", purpose: .answer),
            Worker(id: "model_b#0", modelId: "model_b", instanceIndex: 0, skillId: "signal_skeptic",
                   skillName: "Skeptic", purpose: .review),
            Worker(id: "model_c#0", modelId: "model_c", instanceIndex: 0, skillId: "signal_project_fit",
                   skillName: "Project Fit", purpose: .answer)
        ]
        let answers = [
            WorkerAnswer(workerId: "model_a#0", modelId: "model_a", status: .done, output: "answer A", finishedAt: now),
            WorkerAnswer(workerId: "model_b#0", modelId: "model_b", status: .done, output: "review B", finishedAt: now),
            WorkerAnswer(workerId: "model_c#0", modelId: "model_c", status: .failed, errorReason: "auth expired", finishedAt: now)
        ]
        return TeamRun(id: "floorart1", prompt: "p", status: .complete, origin: .cli,
                       presetId: "signal_post_to_project", workers: workers, workerAnswers: answers,
                       createdAt: now, lane: .signal, outputKind: .insight, posture: .scout)
    }

    func testWorkerArtifactsWrittenOnSave() throws {
        _ = try store.save(makeRun(), models: [])
        let workers = tmp.appendingPathComponent("run_floorart1/workers")
        func exists(_ p: String) -> Bool { FileManager.default.fileExists(atPath: workers.appendingPathComponent(p).path) }

        // Successful workers have answer markdown; the failed one does not.
        XCTAssertTrue(exists("model_a_0.answer.md"))
        XCTAssertTrue(exists("model_b_0.answer.md"))
        XCTAssertFalse(exists("model_c_0.answer.md"))
        // EVERY worker has metadata, including the failed worker (failure stays visible).
        XCTAssertTrue(exists("model_a_0.metadata.json"))
        XCTAssertTrue(exists("model_b_0.metadata.json"))
        XCTAssertTrue(exists("model_c_0.metadata.json"))
        // The local-only prompt snapshot is preserved where present.
        XCTAssertTrue(exists("model_a_0.prompt.md"))
        XCTAssertFalse(exists("model_b_0.prompt.md"))

        let answerA = try String(contentsOf: workers.appendingPathComponent("model_a_0.answer.md"), encoding: .utf8)
        XCTAssertEqual(answerA, "answer A")
        let metaC = try String(contentsOf: workers.appendingPathComponent("model_c_0.metadata.json"), encoding: .utf8)
        XCTAssertTrue(metaC.contains("\"status\" : \"failed\""))
        XCTAssertTrue(metaC.contains("auth expired"))
    }

    func testStageArtifactsWrittenOnSave() throws {
        var r = makeRun()
        r.stages = [StageOutput(id: "stage_plan", purpose: .plan, status: .done,
                                payload: .plan(markdown: "# Insight\nNo move today."))]
        _ = try store.save(r, models: [])
        let stages = tmp.appendingPathComponent("run_floorart1/stages")
        let md = stages.appendingPathComponent("stage_plan.plan.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: md.path))
        XCTAssertEqual(try String(contentsOf: md, encoding: .utf8), "# Insight\nNo move today.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stages.appendingPathComponent("stage_plan.metadata.json").path))
    }

    func testSignalInsightPersistedToReturnJSON() throws {
        let block = """
        No move today.

        ```signal-insight
        {"title":"t","summary":"s","whatHappened":"w","whyItMatters":"m","whyThisProject":"p",
         "window":"uncertain","freshness":{"observedAt":"2026-06-18T00:00:00Z","status":"uncertain"},
         "skepticPass":{"verdict":"reject","reason":"stale"},"receipts":[]}
        ```
        """
        var r = makeRun()
        r.stages = [StageOutput(id: "stage_plan", purpose: .plan, status: .done, payload: .plan(markdown: block))]
        _ = try store.save(r, models: [])
        let insightJSON = tmp.appendingPathComponent("run_floorart1/return/insight.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: insightJSON.path))
        let decoded = try CoreJSON.decode(SignalInsight.self, from: Data(contentsOf: insightJSON))
        XCTAssertEqual(decoded.skepticPass.verdict, .reject)
    }

    func testFloorProjectionCarriesMatchingArtifactRefs() {
        let floor = FloorProjector.project(makeRun())
        let laneA = floor.workerLanes.first { $0.workerId == "model_a#0" }
        let laneC = floor.workerLanes.first { $0.workerId == "model_c#0" }

        XCTAssertEqual(laneA?.artifactRefs.contains { $0.kind == .workerAnswer && $0.relativePath == "workers/model_a_0.answer.md" }, true)
        XCTAssertEqual(laneA?.promptArtifactRef?.localOnly, true)
        // Failed worker: metadata ref but NO answer ref.
        XCTAssertEqual(laneC?.artifactRefs.contains { $0.kind == .workerAnswer }, false)
        XCTAssertEqual(laneC?.artifactRefs.contains { $0.kind == .workerMetadata }, true)
        // Flattened artifacts include the bundle and are all run-relative.
        XCTAssertTrue(floor.artifacts.contains { $0.kind == .bundle })
        XCTAssertTrue(floor.artifacts.allSatisfy { !$0.relativePath.hasPrefix("/") })
    }
}
