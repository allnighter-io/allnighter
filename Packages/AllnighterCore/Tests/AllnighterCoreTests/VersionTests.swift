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

    func testVersionJSONRoundTripIncludesFreshnessFields() throws {
        let payload = VersionJSON(
            binaryVersion: "0.9.0-test",
            gitSha: "abc123def456",
            buildTime: "2026-07-20T01:00:00Z"
        )
        XCTAssertEqual(payload.gitSha, "abc123def456")
        XCTAssertEqual(payload.buildTime, "2026-07-20T01:00:00Z")

        let data = try CoreJSON.encode(payload)
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(raw.contains("gitSha"))
        XCTAssertTrue(raw.contains("buildTime"))
        XCTAssertTrue(raw.contains("abc123def456"))

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
