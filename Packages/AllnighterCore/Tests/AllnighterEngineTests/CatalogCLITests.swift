import XCTest
import AllnighterCore
@testable import AllnighterCLI

final class CatalogCLITests: XCTestCase {

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

    func testSkillsBuildJSONListsOnlyBuildLane() throws {
        let json = AllnighterCLI.skillsCatalogJSONString(lane: .build)
        let data = try XCTUnwrap(json.data(using: .utf8))
        struct Catalog: Decodable {
            struct Skill: Decodable { let id: String; let lane: String }
            let lane: String?
            let skills: [Skill]
        }
        let catalog = try CoreJSON.decode(Catalog.self, from: data)
        XCTAssertEqual(catalog.lane, "build")
        XCTAssertFalse(catalog.skills.isEmpty)
        XCTAssertTrue(catalog.skills.allSatisfy { $0.lane == "build" })
    }

    func testSkillShowJSONIncludesTemplate() throws {
        let json = AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get("bug_reproducer")))
        XCTAssertTrue(json.contains("smallest reproducible"))
    }

    func testSkillsDuplicateAndEditRoundTrip() throws {
        let skill = try SkillCatalog.duplicateBuiltIn("contrarian_reviewer", name: "WT Build Contrarian")
        var edited = skill
        edited.template = "WT Build Contrarian: challenge assumptions."
        try SkillCatalog.saveCustom(edited)
        let json = AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get(skill.id)))
        XCTAssertTrue(json.contains("WT Build Contrarian"))
    }

    func testTeamsDuplicateProducesCustomJSON() throws {
        let team = try TeamCatalog.duplicateBuiltIn("build_core", name: "WT Build Team")
        let json = AllnighterCLI.teamShowJSONString(team)
        XCTAssertTrue(json.contains(team.id))
        XCTAssertTrue(json.contains("WT Build Team"))
    }

    func testSkillsNewCreatesCustomSkill() throws {
        let skill = try SkillCatalog.createCustom(
            lane: .build, name: "Fresh Skill", purpose: .answer, template: "Be precise."
        )
        XCTAssertFalse(skill.builtIn)
        XCTAssertTrue(skill.id.hasPrefix("custom_build_"))
    }
}
