import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// MCP `pair_relay` / `pair_relay_status` / `pair_relay_resume` (docs/phases/
/// PM_Relay.md §6 R-S06). Mirrors `MCPPairHandlersTests`: validation/not-found
/// paths (which never spawn a worker) plus the registry-advertisement proof that
/// all three tools stayed separate through the 61→30-style consolidation lens.
final class MCPRelayHandlersTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-mcp-relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - relay (start)

    func testRelayMissingDocReturnsToolError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(runtime: runtime, args: ["project": "prj_test", "pmWorker": "a", "devWorker": "b"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testRelayMissingProjectReturnsToolError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(runtime: runtime, args: ["doc": "docs/spec.md", "pmWorker": "a", "devWorker": "b"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testRelayMissingPmWorkerReturnsToolError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(runtime: runtime, args: ["doc": "docs/spec.md", "project": "prj_test", "devWorker": "b"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testRelayMissingDevWorkerReturnsToolError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(runtime: runtime, args: ["doc": "docs/spec.md", "project": "prj_test", "pmWorker": "a"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testRelayUnknownProjectReturnsToolError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(runtime: runtime, args: [
            "doc": "docs/spec.md", "project": "prj_does_not_exist_zz", "pmWorker": "a", "devWorker": "b",
        ])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "PROJECT_NOT_FOUND")
    }

    func testRelayInvalidMaxRoundsReturnsUsageError() async throws {
        let projectStore = ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
        let repoDir = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        let project = try projectStore.add(path: repoDir.path, name: nil)

        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(
            runtime: runtime,
            args: ["doc": "docs/spec.md", "project": project.id, "pmWorker": "a", "devWorker": "b", "maxRounds": "0"],
            projectStore: projectStore
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    /// `--pm-read-only` fail-closed pre-flight (PM_Relay.md §4.2): `pmReadOnly: true`
    /// with a pm-worker on a driver `RelayReadOnlyEnforcer` has no confirmed mechanism
    /// for (grok — Grok Build CLI's docs name no headless read-only/plan flag) must
    /// refuse to start the relay at all — never a relay that silently runs un-enforced.
    /// Uses the REAL bundled default catalog (`ToolRuntime()`, matching every other test
    /// in this file) so this proves the actual driver ids the shipped app resolves, not
    /// a synthetic fixture.
    func testRelayPmReadOnlyOnUnsupportedDriverReturnsReadonlyUnsupportedBeforeStartingAnyRelay() async throws {
        let projectStore = ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
        let repoDir = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        let project = try projectStore.add(path: repoDir.path, name: nil)

        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.relay(
            runtime: runtime,
            args: [
                "doc": "docs/spec.md", "project": project.id,
                "pmWorker": "model_grok", "devWorker": "model_grok", "pmReadOnly": true,
            ],
            projectStore: projectStore
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error, not a started relay") }
        XCTAssertEqual(env.code, "RELAY_PM_READONLY_UNSUPPORTED")
        XCTAssertTrue(env.message.contains("grok"))
        XCTAssertTrue(env.message.contains("claude_code"), "must name a driver that CAN enforce it")
    }

    // MARK: - status

    func testStatusMissingRelayReturnsUsageError() {
        let outcome = MCPRelayHandlers.status(args: [:])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testStatusUnknownRelayReturnsNotFound() {
        let outcome = MCPRelayHandlers.status(args: ["relay": "relay_does_not_exist_zz"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "RELAY_NOT_FOUND")
    }

    func testStatusKnownRelayReturnsProjectedEnvelope() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_mcp_status", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(state)

        let outcome = MCPRelayHandlers.status(args: ["relay": "relay_mcp_status"], stateStore: stateStore)
        guard case .success(let encoded, let summary) = outcome else { return XCTFail("expected success") }
        let json = try CoreJSON.decode(RelayJSON.self, from: Data(encoded.utf8))
        XCTAssertEqual(json.relayId, "relay_mcp_status")
        XCTAssertEqual(json.status, "running")
        XCTAssertFalse(summary.isEmpty)
    }

    // MARK: - status (orphan reconciliation — works-test hazard #1)

    func testStatusReconcilesDeadOwnerRunningRelayToStopped() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_mcp_orphan_status", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(state)
        let ownerURL = stateStore.rootDirectory.appendingPathComponent("relay_mcp_orphan_status", isDirectory: true)
            .appendingPathComponent("owner.pid")
        try Data("2000000".utf8).write(to: ownerURL)

        // `threadProjector: nil` — this test only cares about the durable RelayState
        // transition; RelayThreadProjectionTests covers the thread side separately, and a
        // real default projector would touch the machine's actual Application Support
        // ThreadStore, which no test should ever do.
        let outcome = MCPRelayHandlers.status(args: ["relay": "relay_mcp_orphan_status"], stateStore: stateStore, threadProjector: nil)
        guard case .success(let encoded, _) = outcome else { return XCTFail("expected success") }
        let json = try CoreJSON.decode(RelayJSON.self, from: Data(encoded.utf8))
        XCTAssertEqual(json.status, "stopped")
        XCTAssertEqual(json.stoppedReason, RelayState.orphanReconciledReason)

        // Durable — a second read sees the same result.
        XCTAssertEqual(stateStore.load(id: "relay_mcp_orphan_status")?.status, .stopped)
    }

    // MARK: - resume

    func testResumeMissingRelayReturnsUsageError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.resume(runtime: runtime, args: ["answer": "76"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testResumeMissingAnswerReturnsUsageError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.resume(runtime: runtime, args: ["relay": "relay_1"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testResumeUnknownRelayReturnsNotFound() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.resume(runtime: runtime, args: ["relay": "relay_does_not_exist_zz", "answer": "76"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "RELAY_NOT_FOUND")
    }

    func testResumeNonEscalatedRelayReturnsInvalidState() async throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let running = RelayState(
            id: "relay_mcp_running", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(running)
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.resume(
            runtime: runtime, args: ["relay": "relay_mcp_running", "answer": "76"], stateStore: stateStore
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "RELAY_INVALID_STATE")
    }

    /// Works-test hazard #1: "escalated-only was too narrow" — a `.running` relay whose
    /// owner process died mid-round must pass the resumability gate (unlike a genuinely
    /// still-running relay, per `testResumeNonEscalatedRelayReturnsInvalidState` above). An
    /// invalid `maxRounds` short-circuits AFTER that gate but BEFORE dispatch, so a
    /// `CLI_USAGE_ERROR` here (rather than `RELAY_INVALID_STATE`) proves the gate passed.
    func testResumeAcceptsOrphanedRunningRelayPastInvalidStateGate() async throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let running = RelayState(
            id: "relay_mcp_orphaned", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(running)
        let ownerURL = stateStore.rootDirectory.appendingPathComponent("relay_mcp_orphaned", isDirectory: true)
            .appendingPathComponent("owner.pid")
        try Data("2000000".utf8).write(to: ownerURL)

        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.resume(
            runtime: runtime, args: ["relay": "relay_mcp_orphaned", "answer": "76", "maxRounds": "-1"], stateStore: stateStore
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testResumeInvalidMaxRoundsReturnsUsageErrorBeforeDispatch() async throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let escalated = RelayState(
            id: "relay_mcp_escalated", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .escalated, createdAt: Date(),
            note: "76 or 77?"
        )
        try stateStore.save(escalated)
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.resume(
            runtime: runtime, args: ["relay": "relay_mcp_escalated", "answer": "76", "maxRounds": "-1"], stateStore: stateStore
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    // MARK: - pairRelay (action dispatcher)

    func testPairRelayMissingActionReturnsUsageError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.pairRelay(runtime: runtime, args: ["relay": "relay_1"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testPairRelayUnknownActionReturnsUsageError() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.pairRelay(runtime: runtime, args: ["action": "launch"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR")
    }

    func testPairRelayActionStatusDispatchesToStatus() async {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let state = RelayState(
            id: "relay_dispatch_status", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try? stateStore.save(state)
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.pairRelay(
            runtime: runtime, args: ["action": "status", "relay": "relay_dispatch_status"], stateStore: stateStore
        )
        guard case .success(let encoded, _) = outcome else { return XCTFail("expected success") }
        let json = try? CoreJSON.decode(RelayJSON.self, from: Data(encoded.utf8))
        XCTAssertEqual(json?.relayId, "relay_dispatch_status")
    }

    func testPairRelayActionStatusUnknownRelayReturnsNotFound() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.pairRelay(runtime: runtime, args: ["action": "status", "relay": "relay_ghost"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "RELAY_NOT_FOUND")
    }

    func testPairRelayActionResumeDispatchesToResume() async {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let running = RelayState(
            id: "relay_dispatch_resume", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try? stateStore.save(running)
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.pairRelay(
            runtime: runtime, args: ["action": "resume", "relay": "relay_dispatch_resume", "answer": "76"], stateStore: stateStore
        )
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "RELAY_INVALID_STATE", "dispatched into resume's own validation, not a generic usage error")
    }

    func testPairRelayActionStartValidatesRequiredFields() async {
        let runtime = ToolRuntime()
        let outcome = await MCPRelayHandlers.pairRelay(runtime: runtime, args: ["action": "start", "project": "prj_test"])
        guard case .toolError(let env) = outcome else { return XCTFail("expected tool error") }
        XCTAssertEqual(env.code, "CLI_USAGE_ERROR", "dispatched into start's own validation, not a generic usage error")
    }

    // MARK: - Registry advertisement (parity + consolidation-lens proof)

    /// One tool, not three: the MCP tool-count cap (§3 of the tool-upgrade doc)
    /// only had 2 slots of headroom (30 → ≤32); three separate relay tools would
    /// have landed at 33, over cap. Folding status/resume into `action` costs
    /// exactly one slot — the same dispatch shape `teams_edit` already uses.
    func testRegistryAdvertisesOneConsolidatedRelayTool() {
        let names = Set(ContractRegistry.milestone1.mcpTools.map(\.name))
        XCTAssertTrue(names.contains("pair_relay"))
        XCTAssertFalse(names.contains("pair_relay_status"), "status folded into pair_relay(action:status)")
        XCTAssertFalse(names.contains("pair_relay_resume"), "resume folded into pair_relay(action:resume)")
    }

    func testRelayToolDeclaresCommandIdempotencyAndErrors() {
        let byName = Dictionary(uniqueKeysWithValues: ContractRegistry.milestone1.mcpTools.map { ($0.name, $0) })
        let tool = byName["pair_relay"]
        XCTAssertEqual(tool?.command, "pair relay")
        XCTAssertEqual(tool?.idempotency, .notIdempotent, "action:start is never idempotent, so the tool as a whole cannot claim to be")
        XCTAssertEqual(tool?.outputSchema, .relayJSON)
        let errors = Set(tool?.errors ?? [])
        for code in ["PROJECT_NOT_FOUND", "RELAY_NOT_FOUND", "RELAY_INVALID_STATE", "CLI_USAGE_ERROR"] {
            XCTAssertTrue(errors.contains(code), "pair_relay should declare \(code)")
        }
    }
}
