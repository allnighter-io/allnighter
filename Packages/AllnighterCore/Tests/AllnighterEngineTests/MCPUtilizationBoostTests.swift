import XCTest
@testable import AllnighterCore
@testable import AllnighterCLI

final class MCPUtilizationBoostTests: XCTestCase {
    func testRegistryListsBoostTools() {
        let names = Set(ContractRegistry.milestone1.mcpTools.map(\.name))
        XCTAssertTrue(names.contains("utilization_boost_status"))
        XCTAssertTrue(names.contains("utilization_boost_get"))
        XCTAssertTrue(names.contains("utilization_boost_update"))
        XCTAssertTrue(names.contains("utilization_boost_seed"))
        XCTAssertTrue(names.contains("utilization_observations_clear"))

        let update = ContractRegistry.milestone1.mcpTools.first { $0.name == "utilization_boost_update" }
        XCTAssertEqual(update?.command, "utilization boost set")
        XCTAssertEqual(update?.outputSchema, .boostWindowSettingsJSON)

        let seed = ContractRegistry.milestone1.mcpTools.first { $0.name == "utilization_boost_seed" }
        XCTAssertEqual(seed?.outputSchema, .utilizationSeedEventJSON)
        XCTAssertTrue(seed?.errors.contains("UTILIZATION_AUTH_REQUIRED") == true)
    }

    func testClearObservationsJSON() throws {
        let outcome = MCPUtilizationBoostHandlers.clearObservations(args: [:])
        guard case .success(let json, _) = outcome else {
            return XCTFail("expected success")
        }
        let decoded = try CoreJSON.decode(UtilizationObservationsClearJSON.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.cleared)
    }
}
