import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class TeamServiceTests: XCTestCase {

    private let combined = """
    ```json
    {"consensus":[{"statement":"actor","sourceWorkerIds":["model_opus#0"]}],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":[],"failedWorkers":[]}
    ```
    ===PLAN===
    # Plan
    Use an actor.
    """

    private func makeService(env: [String: String] = [:], capacity: Int = 2, store: RunStore) -> TeamService {
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let preset = TeamPreset(id: "preset_fast", displayName: "Fast", workerSpecs: [WorkerSpec(modelId: "model_opus")],
                                 synthesis: SynthesisConfig(planWriterModelId: "model_opus", analysisProfileId: SynthesisInstructions.analysisID, planProfileId: SynthesisInstructions.planID))
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: combined, exitCode: 0)])
        let governorDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gov-\(UUID().uuidString)")
        return TeamService(
            models: [opus], registry: registry, presets: [preset],
            config: ToolConfig(exposedPresetIds: ["preset_fast"], defaultPresetId: "preset_fast", maxConcurrentTeamRuns: capacity, maxTeamRunDepth: 1),
            runStore: store, commandRunner: mock,
            governor: TeamGovernor(directory: governorDir, capacity: capacity),
            environment: env
        )
    }

    func testRunProducesCompleteResultWithPlanAndAnalysis() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        let result = await service.run(TeamRequest(question: "actor or queue?"), origin: .cli)
        XCTAssertEqual(result.status, .complete)
        XCTAssertNotNil(result.plan)
        XCTAssertNotNil(result.analysis)
        XCTAssertEqual(result.origin, .cli)
        XCTAssertGreaterThan(result.invocations, 0)
    }

    func testRecursionGuardRefusesWhenInsideCouncil() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(env: ["ALLNIGHTER_TEAM_DEPTH": "1"], store: RunStore(rootDirectory: tmp))
        let result = await service.run(TeamRequest(question: "x"), origin: .mcp)
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.note.contains("nested councils"))
    }

    func testRecallFindsPriorRun() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = RunStore(rootDirectory: tmp)
        let service = makeService(store: store)
        _ = await service.run(TeamRequest(question: "should the run store be an actor?"), origin: .cli)
        let hits = await service.recall(query: "run store")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits.first?.prompt.contains("run store") ?? false)
        XCTAssertFalse(hits.first?.planExcerpt.isEmpty ?? true)
    }

    func testGovernorCapsConcurrency() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gov-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let gov = TeamGovernor(directory: dir, capacity: 1)
        let a = gov.acquire()
        XCTAssertNotNil(a)
        let b = gov.acquire()
        XCTAssertNil(b, "second acquire should be refused at capacity 1")
    }

    func testPresetSummariesIncludeShape() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        let summaries = await service.presetSummaries()
        XCTAssertEqual(summaries.first?.id, "preset_fast")
        XCTAssertTrue(summaries.first?.shape.contains("worker") ?? false)
    }
}
