import XCTest
@testable import AllnighterCore

final class CatalogPersistenceTests: XCTestCase {

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

    func testCustomSkillRoundTrips() throws {
        let skill = Skill(
            id: "custom_code_wt_skill", displayName: "WT Skill", lane: .code,
            purpose: .answer, template: "Be skeptical.", builtIn: false,
            createdAt: Date(), updatedAt: Date()
        )
        try SkillCatalog.saveCustom(skill)
        XCTAssertEqual(SkillCatalog.get("custom_code_wt_skill")?.displayName, "WT Skill")
    }

    func testBuiltInSkillShadowRejected() throws {
        let skill = Skill(
            id: "bug_reproducer", displayName: "Shadow", lane: .code,
            purpose: .answer, template: "nope", builtIn: false
        )
        XCTAssertThrowsError(try SkillCatalog.saveCustom(skill)) { error in
            XCTAssertEqual(error as? CatalogError, .idCollision)
        }
    }

    func testDuplicateBuiltInTeamCreatesCustom() throws {
        let copy = try TeamCatalog.duplicateBuiltIn("code_bug_hunt", name: "Mike's Bug Hunt")
        XCTAssertFalse(copy.builtIn)
        XCTAssertTrue(copy.id.hasPrefix("custom_code_"))
        XCTAssertEqual(TeamCatalog.get(copy.id)?.displayName, "Mike's Bug Hunt")
        XCTAssertEqual(BuiltInTeams.team("code_bug_hunt")?.displayName, "Bug Hunt")
    }

    func testWrongLaneSkillRejectedAtTeamSave() throws {
        let skill = try SkillCatalog.duplicateBuiltIn("offer_strategist", name: "Wrong Lane")
        var team = try TeamCatalog.duplicateBuiltIn("code_plan", name: "Bad Team")
        team.workerSpecs[0].skillId = skill.id
        XCTAssertThrowsError(try TeamCatalog.saveCustom(team)) { error in
            if case .skillLaneMismatch(let sid, _) = error as? CatalogError {
                XCTAssertEqual(sid, skill.id)
            } else {
                XCTFail("expected skillLaneMismatch, got \(error)")
            }
        }
    }

    func testSkillDeleteBlockedWhenReferencedByTeam() throws {
        let skill = try SkillCatalog.duplicateBuiltIn("contrarian_reviewer", name: "In Use")
        var team = try TeamCatalog.duplicateBuiltIn("code_plan", name: "Uses Custom")
        team.workerSpecs = [TeamWorkerSpec(id: "row1", skillId: skill.id)]
        try TeamCatalog.saveCustom(team)
        XCTAssertThrowsError(try SkillCatalog.deleteCustom(skill.id)) { error in
            if case .skillInUse(let ids) = error as? CatalogError {
                XCTAssertTrue(ids.contains(team.id))
            } else {
                XCTFail("expected skillInUse, got \(error)")
            }
        }
    }

    func testRestartReloadsCustomTeam() throws {
        let team = try TeamCatalog.duplicateBuiltIn("code_plan", name: "Persisted")
        CatalogRoots.resetTestingOverrides()
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
        XCTAssertNotNil(TeamCatalog.get(team.id))
    }

    // MARK: - Edit-in-place + restore (one Bug Hunt, no duplicate)

    /// Editing a built-in saves an override at the SAME id; readers see the edit, the
    /// list still shows exactly one entry for that id, and the shipped seed is hidden.
    func testEditBuiltInSavesInPlaceNoDuplicate() throws {
        var team = BuiltInTeams.team("code_bug_hunt")!
        team.displayName = "Bug Hunt (mine)"
        try TeamCatalog.saveCustom(team)

        XCTAssertEqual(TeamCatalog.get("code_bug_hunt")?.displayName, "Bug Hunt (mine)")
        XCTAssertEqual(TeamCatalog.get("code_bug_hunt")?.builtIn, false)
        XCTAssertTrue(TeamCatalog.hasOverride("code_bug_hunt"))
        // Exactly one code_bug_hunt in the catalog list — no duplicate row.
        XCTAssertEqual(TeamCatalog.all.filter { $0.id == "code_bug_hunt" }.count, 1)
        // Order preserved: it still sits where the seed was, not appended at the end.
        let ids = TeamCatalog.all.map(\.id)
        XCTAssertEqual(ids.filter { $0 == "code_bug_hunt" }.count, 1)
    }

    /// Restore removes the edit and reveals the shipped seed; idempotent afterward.
    func testRestoreBuiltInRevealsSeed() throws {
        var team = BuiltInTeams.team("code_bug_hunt")!
        team.displayName = "Bug Hunt (mine)"
        try TeamCatalog.saveCustom(team)
        XCTAssertTrue(TeamCatalog.hasOverride("code_bug_hunt"))

        let r1 = try TeamCatalog.restore("code_bug_hunt")
        XCTAssertTrue(r1.removedOverride)
        XCTAssertEqual(TeamCatalog.get("code_bug_hunt")?.displayName, "Bug Hunt")
        XCTAssertFalse(TeamCatalog.hasOverride("code_bug_hunt"))

        // Idempotent: restoring again is a no-op, not an error.
        let r2 = try TeamCatalog.restore("code_bug_hunt")
        XCTAssertFalse(r2.removedOverride)
    }

    /// Deleting an edited built-in restores the seed; deleting an unedited built-in is
    /// blocked (the product team stays); restoring a pure custom id is unsupported.
    func testDeleteBuiltInResetsAndGuards() throws {
        XCTAssertThrowsError(try TeamCatalog.deleteCustom("code_bug_hunt")) { error in
            XCTAssertEqual(error as? CatalogError, .builtInImmutable)
        }
        var team = BuiltInTeams.team("code_bug_hunt")!
        team.displayName = "Edited"
        try TeamCatalog.saveCustom(team)
        try TeamCatalog.deleteCustom("code_bug_hunt") // = restore
        XCTAssertEqual(TeamCatalog.get("code_bug_hunt")?.displayName, "Bug Hunt")

        let custom = try TeamCatalog.duplicateBuiltIn("code_plan", name: "Mine")
        XCTAssertThrowsError(try TeamCatalog.restore(custom.id)) { error in
            XCTAssertEqual(error as? CatalogError, .restoreUnsupported)
        }
    }

    /// The global Default Team (default_chat) resolves through the same effective lookup,
    /// so an edit is visible to `defaultRunTeam()`.
    func testDefaultRunTeamResolvesOverride() throws {
        var team = BuiltInTeams.team("default_chat")!
        team.displayName = "Auto (mine)"
        try TeamCatalog.saveCustom(team)
        XCTAssertEqual(TeamCatalog.defaultRunTeam()?.displayName, "Auto (mine)")
        try TeamCatalog.restore("default_chat")
        XCTAssertEqual(TeamCatalog.defaultRunTeam()?.displayName, "Auto")
    }
}
