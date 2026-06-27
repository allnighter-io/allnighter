import XCTest
@testable import AllnighterCore

/// T7 / T7.7 — MCP wire conformance on the live registry surface.
final class MCPWireConformanceTests: XCTestCase {
    private let tools = ContractRegistry.milestone1.mcpTools

    func testProtocolConstants() {
        XCTAssertEqual(MCPWire.protocolVersion, "2025-06-18")
        XCTAssertEqual(MCPWire.serverVersion, "1.0")
    }

    func testToolCountRatchet() {
        // T1 (≤32) applies after Slice 1 atomic cut. Until then, legacy surface must not grow.
        XCTAssertLessThanOrEqual(tools.count, 61, "Pre-cut surface is 61 tools — Slice 1 lands ≤30")
    }

    func testWireDefinitionsHaveTitleAndInputSchema() {
        let defs = MCPWire.toolDefinitions(from: tools)
        XCTAssertEqual(defs.count, tools.count)
        for def in defs {
            XCTAssertFalse((def["name"] as? String ?? "").isEmpty)
            XCTAssertFalse((def["title"] as? String ?? "").isEmpty)
            XCTAssertEqual((def["inputSchema"] as? [String: Any])?["type"] as? String, "object")
            XCTAssertNil(def["outputSchema"], "wire outputSchema forbidden until T7.7 (§6.7)")
        }
    }

    func testCursorCompatInputSchemas() {
        let issues = MCPWire.wireValidationIssues(tools: tools)
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    func testContractHashStable() {
        let a = MCPWire.contractHash(tools: tools)
        let b = MCPWire.contractHash(tools: tools)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }

    func testHelloRouterShape() {
        let verdict = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [
            Model(id: "m1", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both),
        ])
        let payload = AgentHello.build(
            verdict: verdict,
            contractHash: MCPWire.contractHash(tools: tools),
            binaryVersion: "test"
        )
        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertFalse(payload.contractHash.isEmpty)
        XCTAssertEqual(payload.nextToolPlan.tool, "team_start")
        XCTAssertEqual(payload.nextToolPlan.args["dryRun"], "true")
        XCTAssertFalse(payload.workflows.isEmpty)
    }

    func testHelloRoutesDoctorWhenBlocked() {
        let verdict = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [])
        let payload = AgentHello.build(
            verdict: verdict,
            contractHash: "abc",
            binaryVersion: "test"
        )
        XCTAssertEqual(payload.nextToolPlan.tool, "doctor")
        XCTAssertFalse(payload.canStartTeamRun)
    }

    func testToolErrorStructuredContentIsObject() {
        let structured = MCPWire.toolErrorStructuredContent(code: "CLI_USAGE_ERROR", message: "bad args")
        XCTAssertTrue(structured["error"] is [String: Any] || structured["error"] is NSDictionary)
    }
}
