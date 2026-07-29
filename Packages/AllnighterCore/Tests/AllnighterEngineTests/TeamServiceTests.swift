import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class TeamServiceTests: XCTestCase {

    private let planMarkdown = "# Plan\nUse an actor."

    /// A tiny build catalog team: one answer worker + the build plan writer.
    private func testTeam() -> TeamPreset {
        TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            agentSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true)
    }

    private func makeService(env: [String: String] = [:], capacity: Int = 2, store: RunStore) -> TeamService {
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: planMarkdown, exitCode: 0)])
        let governorDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gov-\(UUID().uuidString)")
        return TeamService(
            models: [opus], registry: registry, teams: [testTeam()],
            config: ToolConfig(maxConcurrentTeamRuns: capacity, maxTeamRunDepth: 1),
            runStore: store, commandRunner: mock,
            governor: TeamGovernor(directory: governorDir, capacity: capacity),
            environment: env
        )
    }

    private func request(_ q: String) -> TeamRequest {
        TeamRequest(question: q, lane: .code, teamPresetId: "code_test", effort: .low)
    }

    func testRunProducesCompleteResultWithPlan() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        let result = await service.run(request("actor or queue?"), origin: .cli)
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.plan, planMarkdown)
        XCTAssertEqual(result.preset, "code_test")
        XCTAssertEqual(result.origin, .cli)
        XCTAssertGreaterThan(result.invocations, 0)
    }

    func testConflictingTeamAndTypeIsRejected() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        // code_test has no typeTags, so any --type conflicts.
        let result = await service.run(
            TeamRequest(question: "x", lane: .code, teamPresetId: "code_test", type: "landing-page"), origin: .cli)
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.runId.isEmpty)
        XCTAssertTrue(result.note.contains("conflicts with"))
    }

    func testRecursionGuardRefusesWhenInsideTeam() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(env: ["ALLNIGHTER_TEAM_DEPTH": "1"], store: RunStore(rootDirectory: tmp))
        let result = await service.run(request("x"), origin: .mcp)
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.note.contains("nested teams"))
    }

    func testRecallFindsPriorRun() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = RunStore(rootDirectory: tmp)
        let service = makeService(store: store)
        _ = await service.run(request("should the run store be an actor?"), origin: .cli)
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

    func testCatalogTeamsExposesLaneTeams() async {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(store: RunStore(rootDirectory: tmp))
        let build = await service.catalogTeams(lane: .code)
        XCTAssertEqual(build.first?.id, "code_test")
        let design = await service.catalogTeams(lane: .design)
        XCTAssertTrue(design.isEmpty)
    }
}
