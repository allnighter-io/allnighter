import XCTest
@testable import AllnighterCore

/// AE-S13: `alln commands --json` projects every M1 command with required fields.
final class CommandsManifestTests: XCTestCase {
    func testManifestCountMatchesM1Commands() {
        let registry = ContractRegistry.milestone1
        let m1 = registry.commands.filter { $0.milestone == .m1 }
        let manifest = CommandsManifestJSON.project(registry: registry)
        XCTAssertEqual(manifest.commands.count, m1.count)
        XCTAssertEqual(manifest.contractVersion, registry.contractVersion)
        XCTAssertEqual(manifest.contractHash, ContractRegistry.contractHash(registry))
    }

    func testEveryEntryHasNameAndTrigger() {
        let manifest = CommandsManifestJSON.project()
        XCTAssertFalse(manifest.commands.isEmpty)
        for entry in manifest.commands {
            XCTAssertFalse(entry.name.isEmpty, "empty command name")
            XCTAssertFalse(entry.trigger.isEmpty, "`\(entry.name)` missing trigger")
            // antiExamples may be empty until AE-S15; field must still be present after decode.
            XCTAssertEqual(entry.antiExamples, [])
        }
        XCTAssertTrue(manifest.commands.contains { $0.name == "commands" })
        XCTAssertTrue(manifest.commands.contains { $0.name == "docs" })
    }

    func testCommandsCommandRegistered() {
        let spec = ContractRegistry.milestone1.commands.first { $0.name == "commands" }
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.outputSchema, .commandsManifestJSON)
        XCTAssertTrue(spec?.flags.contains { $0.name == "json" } == true)
    }

    func testManifestRoundTrips() throws {
        let payload = CommandsManifestJSON.project()
        let data = try CoreJSON.encode(payload)
        let decoded = try CoreJSON.decode(CommandsManifestJSON.self, from: data)
        XCTAssertEqual(decoded, payload)
    }
}
