import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

private actor MCPPendingTestGate {
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T { try await body() }
}
private let mcpPendingTestGate = MCPPendingTestGate()

private let mcpPendingTestModels = [
    Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both),
]

private func mcpPendingTestRuntime(root: URL) -> ToolRuntime {
    let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
    let asyncTeam = AsyncTeamService(
        models: mcpPendingTestModels,
        registry: registry,
        teams: TeamCatalog.all,
        config: ToolConfig(),
        runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs"))
    )
    return ToolRuntime(
        models: mcpPendingTestModels,
        registry: registry,
        teams: TeamCatalog.all,
        config: ToolConfig(),
        invocations: [:],
        asyncTeam: asyncTeam,
        readyModels: mcpPendingTestModels
    )
}

final class MCPPendingTests: XCTestCase {
    func testToolListIncludesPendingHandlers() {
        let names = Set(ContractRegistry.milestone1.mcpTools.map(\.name))
        XCTAssertTrue(names.contains("pending_list"))
        XCTAssertTrue(names.contains("pending_show"))
        XCTAssertTrue(names.contains("pending_run"))
        let pendingRun = ContractRegistry.milestone1.mcpTools.first { $0.name == "pending_run" }
        XCTAssertEqual(pendingRun?.idempotency, .notIdempotent)
        XCTAssertEqual(pendingRun?.outputSchema, .pendingItemJSON)
    }

    func testPendingListReturnsPendingListJSONShape() async throws {
        try await mcpPendingTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-pending-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = PendingStore(rootDirectory: root)
            let runtime = mcpPendingTestRuntime(root: root)
            let service = MCPPendingHandlers.makeService(runtime, store: store)
            _ = try service.add(.init(prompt: "Listed via MCP", workerToken: "claude", submit: true, origin: .mcp))

            guard case .success(let json, _) = MCPPendingHandlers.list(runtime: runtime, args: [:], store: store) else {
                return XCTFail("expected list success")
            }
            let list = try CoreJSON.decode(PendingListJSON.self, from: Data(json.utf8))
            XCTAssertEqual(list.contractVersion, ContractRegistry.contractVersion)
            XCTAssertEqual(list.items.count, 1)
            XCTAssertEqual(list.items.first?.pendingItem.kind, .workerChat)
            XCTAssertTrue(list.items.first?.attempts.isEmpty ?? false)
        }
    }

    func testPendingShowReturnsItemJSONAndNotFoundEnvelope() async throws {
        try await mcpPendingTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-pending-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = PendingStore(rootDirectory: root)
            let runtime = mcpPendingTestRuntime(root: root)
            let service = MCPPendingHandlers.makeService(runtime, store: store)
            let item = try service.add(.init(prompt: "Show me", workerToken: "claude", submit: true))

            guard case .success(let json, _) = MCPPendingHandlers.show(runtime: runtime, args: ["pendingId": item.id], store: store) else {
                return XCTFail("expected show success")
            }
            let shown = try CoreJSON.decode(PendingItemJSON.self, from: Data(json.utf8))
            XCTAssertEqual(shown.pendingItem.id, item.id)

            guard case .toolError(let envelope) = MCPPendingHandlers.show(runtime: runtime, args: ["pendingId": "missing"], store: store) else {
                return XCTFail("expected not found")
            }
            XCTAssertEqual(envelope.code, "RUN_NOT_FOUND")
        }
    }

    func testPendingRunWorkerChatSettlesDone() async throws {
        try await mcpPendingTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-pending-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = PendingStore(rootDirectory: root)
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "Review complete.", exitCode: 0)])
            let runtime = mcpPendingTestRuntime(root: root)
            let service = MCPPendingHandlers.makeService(runtime, store: store)
            let item = try service.add(.init(prompt: "Run via MCP", workerToken: "claude", submit: true, origin: .mcp))

            guard case .success(let json, _) = await MCPPendingHandlers.run(
                runtime: runtime,
                args: ["pendingId": item.id, "originAgent": "openclaw-test"],
                store: store,
                commandRunner: mock
            ) else {
                return XCTFail("expected run success")
            }
            let payload = try CoreJSON.decode(PendingItemJSON.self, from: Data(json.utf8))
            XCTAssertEqual(payload.pendingItem.status, .done)
            XCTAssertEqual(payload.attempts.last?.status, "done")
            XCTAssertNotNil(payload.attempts.last?.transcriptRef)
            XCTAssertFalse(json.contains("Review complete."))
        }
    }

    func testPendingRunCapacityFailureReturnsPendingResume() async throws {
        try await mcpPendingTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-pending-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = PendingStore(rootDirectory: root)
            let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"limited","retry_after":120}}"#
            let mock = MockCommandRunner(scripts: ["claude": .init(stderr: stderr, exitCode: 1)])
            let runtime = mcpPendingTestRuntime(root: root)
            let service = MCPPendingHandlers.makeService(runtime, store: store)
            let item = try service.add(.init(prompt: "Cooling", workerToken: "claude", submit: true))

            guard case .success(let json, _) = await MCPPendingHandlers.run(
                runtime: runtime,
                args: ["pendingId": item.id],
                store: store,
                commandRunner: mock
            ) else {
                return XCTFail("expected settled pending item")
            }
            let payload = try CoreJSON.decode(PendingItemJSON.self, from: Data(json.utf8))
            XCTAssertEqual(payload.pendingItem.status, .pending)
            XCTAssertEqual(payload.attempts.last?.status, "blocked")
            XCTAssertEqual(payload.capacityObservation?.kind, "accountRateLimit")
            XCTAssertNotNil(payload.pendingItem.nextWakeAt)
            XCTAssertNotNil(payload.attempts.last?.transcriptRef)
        }
    }

    func testPendingRunUnsupportedKindMatchesCLI() async throws {
        try await mcpPendingTestGate.run {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-pending-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = PendingStore(rootDirectory: root)
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "nope", exitCode: 0)])
            let runtime = mcpPendingTestRuntime(root: root)
            let service = MCPPendingHandlers.makeService(runtime, store: store)
            let item = try service.add(.init(prompt: "Follow", kind: .followUp, workerToken: "claude", submit: true))

            guard case .toolError(let envelope) = await MCPPendingHandlers.run(
                runtime: runtime,
                args: ["pendingId": item.id],
                store: store,
                commandRunner: mock
            ) else {
                return XCTFail("expected unsupported kind error")
            }
            XCTAssertEqual(envelope.code, "CLI_USAGE_ERROR")
            XCTAssertTrue(envelope.message.contains("followUp"))
        }
    }
}
