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

    func testSkillsCodeJSONListsOnlyCodeLane() throws {
        let json = AllnighterCLI.skillsCatalogJSONString(lane: .code)
        let data = try XCTUnwrap(json.data(using: .utf8))
        struct Catalog: Decodable {
            struct Skill: Decodable { let id: String; let lane: String }
            let lane: String?
            let skills: [Skill]
        }
        let catalog = try CoreJSON.decode(Catalog.self, from: data)
        XCTAssertEqual(catalog.lane, "code")
        XCTAssertFalse(catalog.skills.isEmpty)
        XCTAssertTrue(catalog.skills.allSatisfy { $0.lane == "code" })
    }

    func testSkillShowJSONIncludesTemplate() throws {
        let json = AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get("bug_reproducer")))
        XCTAssertTrue(json.contains("smallest reproducible"))
    }

    func testSkillsDuplicateAndEditRoundTrip() throws {
        let skill = try SkillCatalog.duplicateBuiltIn("contrarian_reviewer", name: "WT Code Contrarian")
        var edited = skill
        edited.template = "WT Code Contrarian: challenge assumptions."
        try SkillCatalog.saveCustom(edited)
        let json = AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get(skill.id)))
        XCTAssertTrue(json.contains("WT Code Contrarian"))
    }

    func testTeamsDuplicateProducesCustomJSON() throws {
        let team = try TeamCatalog.duplicateBuiltIn("code_plan", name: "WT Code Team")
        let json = AllnighterCLI.teamShowJSONString(team)
        XCTAssertTrue(json.contains(team.id))
        XCTAssertTrue(json.contains("WT Code Team"))
        XCTAssertTrue(json.contains("\"seatCount\""))
        XCTAssertTrue(json.contains("\"lead\""))
        XCTAssertTrue(json.contains("\"crew\""))
        XCTAssertFalse(json.contains("\"workerSpecs\""), "show is inspect projection, not definition")
        XCTAssertFalse(json.contains("\"workerCount\""), "public workerCount retired")
    }

    func testSkillsNewCreatesCustomSkill() throws {
        let skill = try SkillCatalog.createCustom(
            lane: .code, name: "Fresh Skill", purpose: .answer, template: "Be precise."
        )
        XCTAssertFalse(skill.builtIn)
        XCTAssertTrue(skill.id.hasPrefix("custom_code_"))
    }
}
