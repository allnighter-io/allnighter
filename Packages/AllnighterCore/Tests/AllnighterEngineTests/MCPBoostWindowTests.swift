import XCTest
@testable import AllnighterCore
@testable import AllnighterCLI

final class MCPBoostWindowTests: XCTestCase {
    func testRegistryListsBoostTools() {
        let names = Set(ContractRegistry.milestone1.mcpTools.map(\.name))
        XCTAssertEqual(names.intersection([
            "boost_window_show",
            "boost_window_set",
            "boost_window_seed",
            "boost_window_observations_clear",
        ]), [
            "boost_window_show",
            "boost_window_set",
            "boost_window_seed",
            "boost_window_observations_clear",
        ])

        let set = ContractRegistry.milestone1.mcpTools.first { $0.name == "boost_window_set" }
        XCTAssertEqual(set?.command, "boost-window set")
        XCTAssertEqual(set?.outputSchema, .boostWindowSettingsJSON)

        let seed = ContractRegistry.milestone1.mcpTools.first { $0.name == "boost_window_seed" }
        XCTAssertEqual(seed?.outputSchema, .utilizationSeedEventJSON)
        XCTAssertTrue(seed?.errors.contains("UTILIZATION_AUTH_REQUIRED") == true)
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
