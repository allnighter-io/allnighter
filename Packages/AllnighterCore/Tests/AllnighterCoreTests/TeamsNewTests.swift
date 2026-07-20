import XCTest
@testable import AllnighterCore

/// `teams new <id> --file` creates a novel custom team.
final class TeamsNewTests: XCTestCase {

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

    func testTeamsNewCreatesCallerChosenId() throws {
        let novel = try novelBugHuntManifest(id: "custom_code_novel_hunt")
        let created = try TeamCatalog.createNew(novel)
        XCTAssertEqual(created.id, "custom_code_novel_hunt")
        XCTAssertFalse(created.builtIn)
        XCTAssertEqual(TeamCatalog.get(created.id)?.displayName, novel.displayName)
        XCTAssertEqual(created.catalogSeatCount, novel.catalogSeatCount)
    }

    func testTeamsNewRejectsExistingId() throws {
        let first = try novelBugHuntManifest(id: "custom_code_collision")
        _ = try TeamCatalog.createNew(first)
        XCTAssertThrowsError(try TeamCatalog.createNew(first)) { error in
            XCTAssertEqual(error as? CatalogError, .idCollision)
        }
    }

    func testTeamsNewRejectsBuiltInIdCollision() throws {
        var shadow = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        shadow.displayName = "Shadow"
        XCTAssertThrowsError(try TeamCatalog.createNew(shadow)) { error in
            XCTAssertEqual(error as? CatalogError, .idCollision)
        }
        XCTAssertEqual(TeamCatalog.get("code_bug_hunt")?.displayName, "Bug Hunt")
        XCTAssertFalse(TeamCatalog.hasOverride("code_bug_hunt"))
    }

    func testTeamsNewRejectsInvalidId() throws {
        var bad = try novelBugHuntManifest(id: "custom_code_ok")
        bad.id = "BAD ID!"
        XCTAssertThrowsError(try TeamCatalog.createNew(bad)) { error in
            XCTAssertEqual(error as? CatalogError, .idInvalid)
        }
    }

    func testTeamsNewRegistryCommandExistsWithoutCreateAlias() {
        let names = Set(ContractRegistry.milestone1.commands.map(\.name))
        XCTAssertTrue(names.contains("teams new"))
        XCTAssertFalse(names.contains("teams create"))
        let neu = try! XCTUnwrap(ContractRegistry.milestone1.commands.first { $0.name == "teams new" })
        XCTAssertTrue(neu.flags.contains { $0.name == "file" && $0.takesValue })
        XCTAssertTrue(neu.summary.contains("TeamPreset") || neu.summary.lowercased().contains("novel"))
        XCTAssertFalse(neu.menuAction, "teams new stays off the short actions strip")
    }

    private func novelBugHuntManifest(id: TeamID) throws -> TeamPreset {
        let seed = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        var copy = seed.duplicated(newId: id, newName: "Novel Bug Hunt")
        copy.description = "Novel custom Bug Hunt"
        return copy
    }
}
