import XCTest
@testable import AllnighterCore

/// AE-S13 / AE-S15: `alln commands --json` projects every M1 command with
/// trigger + example + anti-example (description authoring standard).
final class CommandsManifestTests: XCTestCase {
    func testManifestCountMatchesM1Commands() {
        let registry = ContractRegistry.milestone1
        let m1 = registry.commands.filter { $0.milestone == .m1 }
        let manifest = CommandsManifestJSON.project(registry: registry)
        XCTAssertEqual(manifest.commands.count, m1.count)
        XCTAssertEqual(manifest.contractVersion, registry.contractVersion)
        XCTAssertEqual(manifest.contractHash, ContractRegistry.contractHash(registry))
    }

    func testEveryEntryHasTriggerExampleAndAntiExample() {
        let manifest = CommandsManifestJSON.project()
        XCTAssertFalse(manifest.commands.isEmpty)
        var missing: [String] = []
        for entry in manifest.commands {
            if entry.name.isEmpty || entry.trigger.isEmpty || entry.example.isEmpty || entry.antiExample.isEmpty {
                missing.append(entry.name.isEmpty ? "<empty-name>" : entry.name)
            }
            XCTAssertFalse(entry.antiExamples.isEmpty, "`\(entry.name)` antiExamples must be non-empty")
            XCTAssertEqual(entry.antiExamples.first, entry.antiExample)
            XCTAssertTrue(entry.example.hasPrefix("alln "), "`\(entry.name)` example must be a runnable alln invocation")
        }
        XCTAssertTrue(missing.isEmpty, "M1 commands missing trigger/example/antiExample: \(missing)")
        XCTAssertTrue(manifest.commands.contains { $0.name == "commands" })
        XCTAssertTrue(manifest.commands.contains { $0.name == "docs" })
        XCTAssertTrue(manifest.commands.contains { $0.name == "route" })
    }

    func testRouteExampleIsAuthoredNotDerived() {
        let entry = CommandsManifestJSON.project().commands.first { $0.name == "route" }
        XCTAssertEqual(entry?.example, "alln route --for \"ask Sonnet 5 a question\" --json")
        XCTAssertTrue(entry?.antiExample.contains("Do NOT") == true)
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
