import XCTest
@testable import AllnighterCore
@testable import AllnighterCLI

final class MCPBoostWindowTests: XCTestCase {
    func testBoostWindowToolsAreCLIOnlyNotOnMCPCatalog() {
        let names = Set(ContractRegistry.milestone1.mcpTools.map(\.name))
        XCTAssertTrue(names.isDisjoint(with: [
            "boost_window_show",
            "boost_window_set",
            "boost_window_seed",
            "boost_window_observations_clear",
        ]), "Boost window is CLI-only owner-admin (MCP_Tool_Upgrade.md §5D)")
        let m1 = Set(ContractRegistry.milestone1.commands.filter { $0.milestone == .m1 }.map(\.name))
        XCTAssertTrue(m1.contains("boost-window show"))
        XCTAssertTrue(m1.contains("boost-window set"))
    }

    func testClearObservationsJSON() throws {
        let outcome = MCPBoostWindowHandlers.clearObservations(args: [:])
        guard case .success(let json, _) = outcome else {
            return XCTFail("expected success")
        }
        let decoded = try CoreJSON.decode(UtilizationObservationsClearJSON.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.cleared)
    }
}
