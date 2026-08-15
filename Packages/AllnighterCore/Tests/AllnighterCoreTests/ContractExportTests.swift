import XCTest
@testable import AllnighterCore

/// The drift gate at test level: the checked-in generated artifacts must match
/// what the registry produces. If this fails, run `alln dev export-contracts`
/// (docs/archive/phases/CLI_Implementation_Contract.md §Generated Artifacts).
final class ContractExportTests: XCTestCase {

    /// `Options` has no command context, so its boolean-flag set is global. A
    /// name declared boolean in one m1 command and value-taking in another gets
    /// resolved by `booleanFlagNames` (value-taking wins). This records which
    /// names are in that state so a new collision is a deliberate act, not a
    /// silent parsing change in an unrelated command.
    ///
    /// Regression: `show --answer` (boolean) made `loop resume --answer <text>`
    /// throw `missingRequired("--answer <text>")` with the value supplied.
    func testFlagShapeCollisionsAreKnownAndResolvedTowardValueTaking() {
        let collisions = ContractRegistry.flagNameShapeCollisions()
        XCTAssertEqual(
            collisions, ["answer"],
            "flag-shape collisions changed: \(collisions.sorted()). Give the new flag a "
            + "distinct name, or accept it here and confirm every emitted form puts the "
            + "boolean use last on the command line.")
        // Resolution: a name that takes a value anywhere is never globally boolean,
        // so the value is not silently dropped.
        XCTAssertFalse(ContractRegistry.booleanFlagNames().contains("answer"))
    }


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
            "alln-contract.json", "error-codes.json", "exit-codes.json", "ndjson-events.json", "example-recipes.json",
            "team-run.schema.json", "doctor-result.schema.json",
            "coordinator-health.schema.json", "pending-item.schema.json", "model-list.schema.json",
            "version.schema.json",
            "feedback.schema.json",
            "floor-run.schema.json", "spec-result.schema.json",
            "team-catalog.schema.json", "skill-catalog.schema.json",
            "history.schema.json", "thread-status.schema.json",
            "thread-get.schema.json", "thread-attachment.schema.json",
            "ownership-ps.schema.json", "ownership-kill.schema.json", "ownership-gc.schema.json",
            "menu.schema.json", "menu-show.schema.json",
            "billing.schema.json",
            "help_alln_cli_spec.md",
            "contract.lock.json",
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

    /// Set `ALLNIGHTER_REGENERATE_CONTRACTS=1` to rewrite `docs/generated/alln/`
    /// and the `team_run.json` fixture `contractVersion` (`ContractExport.write`).
    func testRegenerateCheckedInArtifactsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["ALLNIGHTER_REGENERATE_CONTRACTS"] == "1" else {
            throw XCTSkip("set ALLNIGHTER_REGENERATE_CONTRACTS=1 to regenerate")
        }
        _ = try ContractExport.write(from: repoRoot.path)
    }
}
