import XCTest
@testable import AllnighterCore

final class VersionTests: XCTestCase {
    func testVersionJSONIncludesBinaryAndContractHash() throws {
        let payload = VersionJSON(binaryVersion: "0.1.0-test")
        XCTAssertEqual(payload.binaryVersion, "0.1.0-test")
        XCTAssertEqual(payload.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(payload.contractHash, ContractRegistry.contractHash())

        let data = try CoreJSON.encode(payload)
        let decoded = try CoreJSON.decode(VersionJSON.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testVersionCommandRegisteredInContract() {
        XCTAssertNotNil(ContractRegistry.milestone1.commands.first { $0.name == "version" })
        XCTAssertEqual(
            ContractRegistry.milestone1.commands.first { $0.name == "version" }?.outputSchema,
            .versionJSON)
    }
}
