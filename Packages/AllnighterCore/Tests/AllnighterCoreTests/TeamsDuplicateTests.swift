import XCTest
@testable import AllnighterCore

/// `teams duplicate --id` plus generated-id, collision, restore, Bug Hunt path.
final class TeamsDuplicateTests: XCTestCase {

    private var teamsRoot: URL!
    private var skillsRoot: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        teamsRoot = base.appendingPathComponent("teams", isDirectory: true)
        skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        try? FileManager.default.removeItem(at: teamsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testTeamsDuplicateDeterministicId() throws {
        let copy = try TeamCatalog.duplicateBuiltIn(
            "code_bug_hunt",
            name: "My Bug Hunt",
            customId: "custom_code_my_bug_hunt"
        )
        XCTAssertEqual(copy.id, "custom_code_my_bug_hunt")
        XCTAssertEqual(copy.displayName, "My Bug Hunt")
        XCTAssertFalse(copy.builtIn)
        XCTAssertEqual(TeamCatalog.get(copy.id)?.workerSpecs.count, BuiltInTeams.team("code_bug_hunt")?.workerSpecs.count)
    }

    func testTeamsDuplicateOmittingIdKeepsGeneratedBehavior() throws {
        let copy = try TeamCatalog.duplicateBuiltIn("code_bug_hunt", name: "Generated Hunt")
        XCTAssertTrue(copy.id.hasPrefix("custom_code_"))
        XCTAssertNotEqual(copy.id, "code_bug_hunt")
        XCTAssertEqual(TeamCatalog.get(copy.id)?.displayName, "Generated Hunt")
    }

    func testTeamsDuplicateRejectsIdCollision() throws {
        _ = try TeamCatalog.duplicateBuiltIn(
            "code_bug_hunt", name: "First", customId: "custom_code_taken")
        XCTAssertThrowsError(
            try TeamCatalog.duplicateBuiltIn(
                "code_bug_hunt", name: "Second", customId: "custom_code_taken")
        ) { error in
            XCTAssertEqual(error as? CatalogError, .idCollision)
        }
    }

    func testTeamsDuplicateRejectsBuiltInTargetId() throws {
        XCTAssertThrowsError(
            try TeamCatalog.duplicateBuiltIn(
                "code_bug_hunt", name: "Nope", customId: "code_plan")
        ) { error in
            XCTAssertEqual(error as? CatalogError, .idCollision)
        }
    }

    func testTeamsDuplicateRejectsInvalidCustomId() throws {
        XCTAssertThrowsError(
            try TeamCatalog.duplicateBuiltIn(
                "code_bug_hunt", name: "Bad", customId: "NOT_VALID")
        ) { error in
            XCTAssertEqual(error as? CatalogError, .idInvalid)
        }
    }

    func testTeamsDuplicateColdAgentBugHuntThenEditPath() throws {
        let chosen = "custom_code_cold_bug_hunt"
        let copy = try TeamCatalog.duplicateBuiltIn(
            "code_bug_hunt", name: "Cold Bug Hunt", customId: chosen)
        XCTAssertEqual(copy.id, chosen)

        var edited = try XCTUnwrap(TeamCatalog.get(chosen))
        edited.displayName = "Cold Bug Hunt (edited)"
        try TeamCatalog.saveCustom(edited)
        XCTAssertEqual(TeamCatalog.get(chosen)?.displayName, "Cold Bug Hunt (edited)")

        XCTAssertEqual(BuiltInTeams.team("code_bug_hunt")?.displayName, "Bug Hunt")
        var override = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        override.displayName = "Bug Hunt (mine)"
        try TeamCatalog.saveCustom(override)
        XCTAssertTrue(TeamCatalog.hasOverride("code_bug_hunt"))
        let restored = try TeamCatalog.restore("code_bug_hunt")
        XCTAssertTrue(restored.removedOverride)
        XCTAssertEqual(TeamCatalog.get("code_bug_hunt")?.displayName, "Bug Hunt")
        XCTAssertEqual(TeamCatalog.get(chosen)?.displayName, "Cold Bug Hunt (edited)")
    }

    func testTeamsDuplicateRegistryDeclaresIdFlag() {
        let dup = try! XCTUnwrap(
            ContractRegistry.milestone1.commands.first { $0.name == "teams duplicate" })
        XCTAssertTrue(dup.flags.contains { $0.name == "id" && $0.takesValue })
        XCTAssertTrue(dup.summary.lowercased().contains("bug hunt") || dup.summary.contains("--id"))
        XCTAssertEqual(dup.outputSchema, .teamPreset)
        XCTAssertTrue(dup.summary.lowercased().contains("edit"))
        XCTAssertFalse(dup.summary.contains("definition → edit"))
    }

    func testTeamsAuthoringCommandsDeclareTeamPresetOutputSchema() {
        let reg = ContractRegistry.milestone1
        for name in ["teams definition", "teams duplicate", "teams new", "teams edit"] {
            let cmd = try! XCTUnwrap(reg.commands.first { $0.name == name })
            XCTAssertEqual(cmd.outputSchema, .teamPreset, name)
        }
        let show = try! XCTUnwrap(reg.commands.first { $0.name == "teams show" })
        XCTAssertEqual(show.outputSchema, .teamShowJSON)
        let setDefault = try! XCTUnwrap(reg.commands.first { $0.name == "teams set-default" })
        XCTAssertEqual(setDefault.outputSchema, .teamShowJSON)
    }
}
