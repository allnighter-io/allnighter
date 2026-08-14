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

    func testVersionJSONCarriesPersonHatch() throws {
        let payload = VersionJSON(binaryVersion: "0.1.0-test")
        XCTAssertEqual(payload.tellHuman, SupportHatch.tellHuman)
        XCTAssertTrue(payload.tellHuman.contains(AskAIPrompt.supportEmail))

        let data = try CoreJSON.encode(payload)
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(raw.contains("tellHuman"))
        XCTAssertTrue(raw.contains(AskAIPrompt.supportEmail))

        let decoded = try CoreJSON.decode(VersionJSON.self, from: data)
        XCTAssertEqual(decoded.tellHuman, SupportHatch.tellHuman)
    }

    func testVersionJSONDecodesMissingTellHumanAsHatch() throws {
        let payload = VersionJSON(binaryVersion: "0.1.0-test")
        var obj = try JSONSerialization.jsonObject(with: try CoreJSON.encode(payload)) as! [String: Any]
        obj.removeValue(forKey: "tellHuman")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try CoreJSON.decode(VersionJSON.self, from: stripped)
        XCTAssertEqual(decoded.tellHuman, SupportHatch.tellHuman)
    }

    func testHumanLineIsIdentityPlusHatchWithoutContractDump() {
        let payload = VersionJSON(binaryVersion: "1.1.12", contractHash: "abc123", gitSha: "deadbeef")
        let plain = payload.humanLine(color: false)
        XCTAssertEqual(plain, "alln 1.1.12\n\(SupportHatch.tellHuman)")
        XCTAssertFalse(plain.contains("contract"))
        XCTAssertFalse(plain.contains("hash"))
        XCTAssertFalse(plain.contains("deadbeef"))

        let painted = payload.humanLine(color: true, environment: ["TERM": "xterm-256color", "TERM_PROGRAM": "iTerm.app"])
        XCTAssertTrue(painted.contains("\u{1B}[1;38;2;255;166;48m"))
        XCTAssertTrue(painted.contains(SupportHatch.tellHuman))
    }
}
