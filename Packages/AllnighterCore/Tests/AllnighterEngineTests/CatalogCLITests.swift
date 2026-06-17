import XCTest
import AllnighterCore
@testable import AllnighterCLI

final class CatalogCLITests: XCTestCase {

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
}
