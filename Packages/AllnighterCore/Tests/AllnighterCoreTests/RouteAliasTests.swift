import XCTest
@testable import AllnighterCore

/// AE-S14: `route` / `resolve` are first-class aliases of `team hello --for`.
final class RouteAliasTests: XCTestCase {
    func testRouteAndResolveAreRegisteredM1Commands() {
        let m1 = Set(ContractRegistry.milestone1.commands.filter { $0.milestone == .m1 }.map(\.name))
        XCTAssertTrue(m1.contains("route"))
        XCTAssertTrue(m1.contains("resolve"))
        XCTAssertTrue(m1.contains("team hello"))
    }

    func testRouteAndResolveShareForFlag() {
        for name in ["route", "resolve", "team hello"] {
            guard let spec = ContractRegistry.milestone1.commands.first(where: { $0.name == name }) else {
                return XCTFail("missing \(name)")
            }
            XCTAssertTrue(spec.flags.contains { $0.name == "for" && $0.takesValue })
            XCTAssertTrue(spec.summary.contains("USE THIS FIRST"), "\(name) must be trigger-shaped")
            XCTAssertTrue(spec.summary.contains("Sonnet 5"), "\(name) must carry a worked example")
        }
    }

    func testTeamHelloSummaryIsTriggerShaped() {
        let spec = ContractRegistry.milestone1.commands.first { $0.name == "team hello" }
        XCTAssertNotNil(spec)
        XCTAssertTrue(spec!.summary.contains("USE THIS FIRST"))
        XCTAssertTrue(spec!.summary.contains("ask Sonnet 5"))
        XCTAssertFalse(spec!.summary.hasPrefix("Agent bootstrap"))
        XCTAssertFalse(spec!.summary.hasPrefix("Intent phrase"))
    }

    func testModelNotFoundPointsAtResolver() {
        let spec = ContractRegistry.milestone1.errorSpec(for: "MODEL_NOT_FOUND")
        XCTAssertNotNil(spec)
        XCTAssertTrue(spec!.agentAction.contains("alln route --for"))
    }

    func testEmptyModelsCounselPointsAtRoute() {
        let (_, actions) = AgentFrontDoor.emptyModelsCounsel(benchOnly: true, driverId: nil, catalogCount: 0)
        XCTAssertEqual(actions.first?.command, AgentFrontDoor.routeFirst.command)
    }
}
