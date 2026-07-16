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
        XCTAssertEqual(payload.schemaVersion, 3)
        XCTAssertFalse(payload.contractHash.isEmpty)
        XCTAssertEqual(
            payload.nextCommandPlan.command,
            "alln team preflight --team <team-id> --json")
        XCTAssertFalse(payload.workflows.isEmpty)
    }

    func testHelloRoutesDoctorWhenBlocked() {
        let verdict = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [])
        let payload = AgentHello.build(
            verdict: verdict,
            contractHash: "abc",
            binaryVersion: "test"
        )
        XCTAssertEqual(payload.nextCommandPlan.command, "alln doctor --json")
        XCTAssertFalse(payload.canStartTeamRun)
    }

    func testHelloPayloadCommandsResolveAgainstRegistry() {
        let ready = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [
            Model(id: "m1", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both),
        ])
        let blocked = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [])
        for verdict in [ready, blocked] {
            let payload = AgentHello.build(
                verdict: verdict,
                contractHash: ContractRegistry.contractHash(),
                binaryVersion: "test"
            )
            for invocation in AgentHello.commandInvocations(in: payload) {
                XCTAssertNotNil(
                    ContractRegistry.resolveCommandName(from: invocation),
                    "hello references unknown command: \(invocation)")
            }
        }
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
