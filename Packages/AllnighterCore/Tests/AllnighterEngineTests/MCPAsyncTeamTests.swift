import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

private actor MCPAsyncTeamTestGate {
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T { try await body() }
}
private let mcpAsyncTeamTestGate = MCPAsyncTeamTestGate()

final class MCPAsyncTeamTests: XCTestCase {
    private static let planMarkdown = "# Plan\nMCP async ok."

    private static func testTeam() -> TeamPreset {
        TeamPreset(
            id: "build_test", displayName: "Test", lane: .build, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer, minEffort: .low)],
            synthesisPolicyByEffort: [.low: TeamSynthesisPolicy(outputKind: .plan, planWriterSkillId: "plan_writer_build")],
            builtIn: true)
    }

    private static func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    private static func makeRuntime(
        runId: String,
        mock: MockCommandRunner,
        root: URL
    ) -> ToolRuntime {
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let models = [Self.opus()]
        let asyncTeam = AsyncTeamService(
            models: models,
            registry: registry,
            teams: [Self.testTeam()],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs")),
            commandRunner: mock,
            governor: TeamGovernor(directory: root.appendingPathComponent("gov"), capacity: 2),
            idempotency: IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
            idFactory: { runId }
        )
        return ToolRuntime(
            models: models,
            registry: registry,
            teams: [Self.testTeam()],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            asyncTeam: asyncTeam,
            readyModels: models
        )
    }

    func testTeamStartReturnsRunId() async throws {
        try await mcpAsyncTeamTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-async-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: Self.planMarkdown, delay: .milliseconds(250))])
            let runtime = Self.makeRuntime(runId: "mcp-run-1", mock: mock, root: root)
            let outcome = await MCPAsyncTeamHandlers.start(runtime: runtime, args: [
                "prompt": "mcp async",
                "lane": "build",
                "team": "build_test",
                "effort": "low",
                "originAgent": "test-mcp",
                "originConversationId": "conv-mcp",
                "originMessageId": "msg-mcp",
            ], defaultAgent: "mcp")
            guard case .success(let json, _) = outcome else {
                return XCTFail("expected success")
            }
            let response = try CoreJSON.decode(TeamStartResponse.self, from: Data(json.utf8))
            XCTAssertEqual(response.runId, "mcp-run-1")
            XCTAssertGreaterThan(response.nextPollAfterMs, 0)
            let run = try XCTUnwrap(RunStore(rootDirectory: root.appendingPathComponent("Runs")).load(runId: "mcp-run-1"))
            XCTAssertEqual(run.origin, .mcp)
            XCTAssertEqual(run.originAgent, "test-mcp")
            _ = await runtime.asyncTeamService().cancel(runId: "mcp-run-1")
        }
    }

    func testTeamStartPreflightRefusal() async {
        await mcpAsyncTeamTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-async-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: Self.planMarkdown)])
            let runtime = Self.makeRuntime(runId: "mcp-run-2", mock: mock, root: root)
            let outcome = await MCPAsyncTeamHandlers.start(runtime: runtime, args: [
                "prompt": "x", "lane": "build", "team": "missing_team", "effort": "low",
            ], defaultAgent: "mcp")
            guard case .toolError(let envelope) = outcome else {
                return XCTFail("expected tool error")
            }
            XCTAssertEqual(envelope.code, "DEFAULT_TEAM_INVALID")
        }
    }

    func testTeamStatusAndResultLifecycle() async throws {
        try await mcpAsyncTeamTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-async-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: Self.planMarkdown, delay: .milliseconds(250))])
            let runtime = Self.makeRuntime(runId: "mcp-run-3", mock: mock, root: root)
            _ = await MCPAsyncTeamHandlers.start(runtime: runtime, args: [
                "prompt": "poll me", "lane": "build", "team": "build_test", "effort": "low",
            ], defaultAgent: "mcp")
            let statusOutcome = await MCPAsyncTeamHandlers.status(runtime: runtime, args: ["runId": "mcp-run-3"])
            guard case .success(let statusJSON, _) = statusOutcome else {
                return XCTFail("expected status")
            }
            let status = try CoreJSON.decode(TeamStatusResponse.self, from: Data(statusJSON.utf8))
            XCTAssertEqual(status.runId, "mcp-run-3")
            XCTAssertGreaterThan(status.nextPollAfterMs, 0)

            let early = await MCPAsyncTeamHandlers.result(runtime: runtime, args: ["runId": "mcp-run-3"])
            guard case .success(let notReadyJSON, _) = early else {
                return XCTFail("expected not-ready envelope")
            }
            let nr = try CoreJSON.decode(TeamResultNotReady.self, from: Data(notReadyJSON.utf8))
            XCTAssertEqual(nr.error.code, "RESULT_NOT_READY")

            for _ in 0..<50 {
                if case .success(let json, _) = await MCPAsyncTeamHandlers.result(runtime: runtime, args: ["runId": "mcp-run-3"]),
                   (try? CoreJSON.decode(TeamRunJSON.self, from: Data(json.utf8))) != nil {
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let final = await MCPAsyncTeamHandlers.result(runtime: runtime, args: ["runId": "mcp-run-3"])
            guard case .success(let finalJSON, _) = final else {
                return XCTFail("expected final result")
            }
            let trj = try CoreJSON.decode(TeamRunJSON.self, from: Data(finalJSON.utf8))
            XCTAssertEqual(trj.teamRun.id, "mcp-run-3")
        }
    }

    func testTeamCancel() async throws {
        try await mcpAsyncTeamTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-async-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: Self.planMarkdown, delay: .seconds(2))])
            let runtime = Self.makeRuntime(runId: "mcp-run-4", mock: mock, root: root)
            _ = await MCPAsyncTeamHandlers.start(runtime: runtime, args: [
                "prompt": "cancel me", "lane": "build", "team": "build_test", "effort": "low",
            ], defaultAgent: "mcp")
            let outcome = await MCPAsyncTeamHandlers.cancel(runtime: runtime, args: ["runId": "mcp-run-4"])
            guard case .success(let json, _) = outcome else {
                return XCTFail("expected cancel success")
            }
            let response = try CoreJSON.decode(TeamCancelResponse.self, from: Data(json.utf8))
            XCTAssertEqual(response.status, .cancelled)
            let run = try XCTUnwrap(RunStore(rootDirectory: root.appendingPathComponent("Runs")).load(runId: "mcp-run-4"))
            XCTAssertEqual(run.status, .cancelled)
        }
    }
}
