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
            id: "custom_build_wt_skill", displayName: "WT Skill", lane: .build,
            purpose: .answer, template: "Be skeptical.", builtIn: false,
            createdAt: Date(), updatedAt: Date()
        )
        try SkillCatalog.saveCustom(skill)
        XCTAssertEqual(SkillCatalog.get("custom_build_wt_skill")?.displayName, "WT Skill")
    }

    func testBuiltInSkillShadowRejected() throws {
        let skill = Skill(
            id: "bug_reproducer", displayName: "Shadow", lane: .build,
            purpose: .answer, template: "nope", builtIn: false
        )
        XCTAssertThrowsError(try SkillCatalog.saveCustom(skill)) { error in
            XCTAssertEqual(error as? CatalogError, .idCollision)
        }
    }

    func testDuplicateBuiltInTeamCreatesCustom() throws {
        let copy = try TeamCatalog.duplicateBuiltIn("build_bug_hunt", name: "Mike's Bug Hunt")
        XCTAssertFalse(copy.builtIn)
        XCTAssertTrue(copy.id.hasPrefix("custom_build_"))
        XCTAssertEqual(TeamCatalog.get(copy.id)?.displayName, "Mike's Bug Hunt")
        XCTAssertEqual(BuiltInTeams.team("build_bug_hunt")?.displayName, "Bug Hunt")
    }

    func testWrongLaneSkillRejectedAtTeamSave() throws {
        let skill = try SkillCatalog.duplicateBuiltIn("offer_strategist", name: "Wrong Lane")
        var team = try TeamCatalog.duplicateBuiltIn("build_core", name: "Bad Team")
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
        var team = try TeamCatalog.duplicateBuiltIn("build_core", name: "Uses Custom")
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
        let team = try TeamCatalog.duplicateBuiltIn("build_core", name: "Persisted")
        CatalogRoots.resetTestingOverrides()
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
        XCTAssertNotNil(TeamCatalog.get(team.id))
    }
}
