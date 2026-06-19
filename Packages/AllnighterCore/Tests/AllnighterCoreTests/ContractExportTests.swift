import XCTest
@testable import AllnighterCore

/// The drift gate at test level: the checked-in generated artifacts must match
/// what the registry produces. If this fails, run `alln dev export-contracts`
/// (docs/phases/CLI_Implementation_Contract.md §Generated Artifacts).
final class ContractExportTests: XCTestCase {

    /// Repo root, resolved from this source file:
    /// …/Packages/AllnighterCore/Tests/AllnighterCoreTests/<this>.swift → up 5.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AllnighterCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // AllnighterCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
    }

    func testExportIsDeterministicAndRoundTrips() throws {
        let a = try ContractExport.artifacts()
        let b = try ContractExport.artifacts()
        XCTAssertEqual(a, b, "export is not deterministic")
        XCTAssertEqual(a.map(\.filename), [
            "alln-contract.json", "error-codes.json", "ndjson-events.json", "example-recipes.json",
            "mcp-tools.json", "team-run.schema.json", "doctor-result.schema.json",
            "coordinator-health.schema.json", "pending-item.schema.json", "model-list.schema.json",
            "floor-run.schema.json", "help_alln_cli_spec.md",
        ])
        // The full contract artifact decodes back to the registry.
        let contract = try XCTUnwrap(a.first { $0.filename == "alln-contract.json" })
        let decoded = try CoreJSON.decode(ContractRegistry.self, from: Data(contract.contents.utf8))
        XCTAssertEqual(decoded, .milestone1)
    }

    func testCheckedInArtifactsMatchRegistry() throws {
        let dir = repoRoot.appendingPathComponent(ContractExport.generatedDir)
        for artifact in try ContractExport.artifacts() {
            let url = dir.appendingPathComponent(artifact.filename)
            let onDisk = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(onDisk, artifact.contents,
                           "\(artifact.filename) drifted — run `alln dev export-contracts`")
        }
    }
}
