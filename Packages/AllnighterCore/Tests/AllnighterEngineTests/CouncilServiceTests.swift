import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class CouncilServiceTests: XCTestCase {

    private let combined = """
    ```json
    {"consensus":[{"statement":"actor","sourceSeatIds":["worker_opus#0"]}],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":[],"failedSeats":[]}
    ```
    ===PLAN===
    # Master Plan
    Use an actor.
    """

    private func makeService(env: [String: String] = [:], capacity: Int = 2, store: RunStore) -> CouncilService {
        let opus = Worker(id: "worker_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let preset = PanelPreset(id: "preset_fast", displayName: "Fast", seats: [PanelSeatSpec(workerId: "worker_opus")],
                                 synthesis: SynthesisConfig(judgeWorkerId: "worker_opus", analysisProfileId: SynthesisInstructions.analysisID, planProfileId: SynthesisInstructions.planID))
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: combined, exitCode: 0)])
        let governorDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gov-\(UUID().uuidString)")
        return CouncilService(
            workers: [opus], registry: registry, presets: [preset],
            config: ToolConfig(exposedPresetIds: ["preset_fast"], defaultPresetId: "preset_fast", maxConcurrentCouncils: capacity, maxCouncilDepth: 1),
            runStore: store, commandRunner: mock,
            governor: CouncilGovernor(directory: governorDir, capacity: capacity),
            environment: env
        )
    }

    func testRunProducesCompleteResultWithPlanAndAnalysis() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        let result = await service.run(CouncilRequest(question: "actor or queue?"), origin: .cli)
        XCTAssertEqual(result.status, .complete)
        XCTAssertNotNil(result.masterPlan)
        XCTAssertNotNil(result.analysis)
        XCTAssertEqual(result.origin, .cli)
        XCTAssertGreaterThan(result.callsSpent, 0)
    }

    func testRecursionGuardRefusesWhenInsideCouncil() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(env: ["ALLNIGHTER_COUNCIL_DEPTH": "1"], store: RunStore(rootDirectory: tmp))
        let result = await service.run(CouncilRequest(question: "x"), origin: .mcp)
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.estimateNote.contains("nested councils"))
    }

    func testRecallFindsPriorRun() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = RunStore(rootDirectory: tmp)
        let service = makeService(store: store)
        _ = await service.run(CouncilRequest(question: "should the run store be an actor?"), origin: .cli)
        let hits = await service.recall(query: "run store")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits.first?.prompt.contains("run store") ?? false)
        XCTAssertFalse(hits.first?.masterPlanExcerpt.isEmpty ?? true)
    }

    func testGovernorCapsConcurrency() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gov-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let gov = CouncilGovernor(directory: dir, capacity: 1)
        let a = gov.acquire()
        XCTAssertNotNil(a)
        let b = gov.acquire()
        XCTAssertNil(b, "second acquire should be refused at capacity 1")
    }

    func testPresetSummariesIncludeCallPlan() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        let summaries = await service.presetSummaries()
        XCTAssertEqual(summaries.first?.id, "preset_fast")
        XCTAssertGreaterThan(summaries.first?.callPlan.estimatedCalls ?? 0, 0)
    }
}
