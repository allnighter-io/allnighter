import XCTest
@testable import AllnighterCore

/// S01 — unified built-in catalogs; retired prompt libraries must not return.
final class CatalogUnifiedTests: XCTestCase {

    func testTeamCatalogExposesBuiltInTeams() {
        XCTAssertEqual(TeamCatalog.all.count, BuiltInTeams.all.count)
        XCTAssertEqual(TeamCatalog.get("build_bug_hunt")?.displayName, "Bug Hunt")
        XCTAssertEqual(TeamCatalog.list(lane: .build).count, BuiltInTeams.teams(in: .build).count)
        XCTAssertEqual(TeamCatalog.defaultTeam(for: .design)?.id, "design_core")
    }

    func testSkillCatalogListAndGetMatchBuiltIns() {
        XCTAssertFalse(SkillCatalog.list(lane: .design).isEmpty)
        XCTAssertEqual(SkillCatalog.get("bug_reproducer")?.lane, .build)
        XCTAssertEqual(SkillCatalog.get("minimal")?.lane, .design)
    }

    func testDesignPanelSkillsFoldedIntoCatalog() {
        for id in SkillCatalog.defaultDesignPanelSkillIDs {
            let skill = SkillCatalog.get(id)
            XCTAssertNotNil(skill, "missing design panel skill \(id)")
            XCTAssertEqual(skill?.lane, .design)
            XCTAssertFalse(SkillCatalog.designDirection(for: id).isEmpty)
            XCTAssertEqual(SkillCatalog.displayName(for: id), skill?.displayName)
        }
    }

    func testRetiredPromptLibrariesAreRemovedFromSources() {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engineSources = repoRoot
            .appendingPathComponent("Packages/AllnighterCore/Sources/AllnighterEngine")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: engineSources.path)) ?? []
        XCTAssertFalse(names.contains("SkillLibrary.swift"))
        XCTAssertFalse(names.contains("DesignPersonaLibrary.swift"))
    }
}
