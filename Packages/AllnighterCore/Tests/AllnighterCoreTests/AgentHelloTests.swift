import XCTest
@testable import AllnighterCore

/// `alln team hello` — the agent bootstrap payload. Coverage carried over from the
/// retired MCPWireConformanceTests (MCP_Retirement.md): `AgentHello.build`'s
/// routing logic is unrelated to the wire protocol it used to live next to.
final class AgentHelloTests: XCTestCase {

    /// Explicit ready verdict — `evaluate` with a fake `Model(id: "m1"…)` does not
    /// staff BuiltInTeams, so canStartTeamRun stays false (doctor path).
    private var readyVerdict: AgentReadiness.Verdict {
        AgentReadiness.Verdict(
            canStartTeamRun: true,
            readyTeams: BuiltInTeams.all.map {
                ReadyTeam(lane: $0.lane.rawValue, team: $0.id, displayName: $0.displayName)
            },
            blockedReason: nil,
            nextAction: AgentNextAction.startTeamRun()
        )
    }

    func testHelloRouterShape() {
        let payload = AgentHello.build(
            verdict: readyVerdict,
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
        let blocked = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [])
        for verdict in [readyVerdict, blocked] {
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
        let json = AgentHello.jsonString(verdict: readyVerdict, binaryVersion: "test")
        let decoded = try CoreJSON.decode(AgentHello.Payload.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.contractHash, ContractRegistry.contractHash())
        XCTAssertTrue(decoded.canStartTeamRun)
        XCTAssertEqual(
            decoded.nextCommandPlan.command,
            "alln team preflight --team <team-id> --json")
    }
}
