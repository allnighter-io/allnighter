import XCTest
@testable import AllnighterCore

/// `alln team hello` — the agent bootstrap payload. Coverage carried over from the
/// retired MCPWireConformanceTests (MCP_Retirement.md): `AgentHello.build`'s
/// routing logic is unrelated to the wire protocol it used to live next to.
final class AgentHelloTests: XCTestCase {
    func testHelloRouterShape() {
        let verdict = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [
            Model(id: "m1", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both),
        ])
        let payload = AgentHello.build(
            verdict: verdict,
            contractHash: ContractRegistry.contractHash(),
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

    func testContractHashStableAndDerivedFromCommands() {
        let a = ContractRegistry.contractHash()
        let b = ContractRegistry.contractHash()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }

    func testJSONStringRoundTrips() throws {
        let verdict = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [
            Model(id: "m1", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both),
        ])
        let json = AgentHello.jsonString(verdict: verdict, binaryVersion: "test")
        let decoded = try CoreJSON.decode(AgentHello.Payload.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.contractHash, ContractRegistry.contractHash())
    }
}
