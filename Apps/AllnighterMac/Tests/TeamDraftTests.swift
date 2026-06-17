import XCTest
import AllnighterCore
@testable import AllnighterMac

/// S05b.3: the Customize editor's write path. Editing a built-in must duplicate to
/// a custom (never mutate the built-in); a failed save must leave no orphan; a
/// wrong-lane skill must be rejected. Catalog is isolated to a temp dir.
final class TeamDraftTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-cat-\(UUID().uuidString)", isDirectory: true)
        let teams = base.appendingPathComponent("teams", isDirectory: true)
        let skills = base.appendingPathComponent("skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: teams, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        CatalogRoots.overrideForTesting(teams: teams, skills: skills)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        super.tearDown()
    }

    private var buildBase: TeamPreset {
        TeamCatalog.list(lane: .build).first { $0.builtIn }!
    }
    private var buildSkill: String { SkillCatalog.list(lane: .build).first!.id }

    func testSeedFromBuiltInMakesACustomDraft() {
        let d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        XCTAssertTrue(d.name.contains("(custom)"), "a built-in seeds a custom name")
        XCTAssertFalse(d.rows.isEmpty)
        XCTAssertTrue(d.rows.allSatisfy { $0.modelId != nil }, "rows pre-fill a concrete model")
        XCTAssertTrue(d.isSavable)
    }

    func testNotSavableWithAModellessRow() {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows[0].modelId = nil
        XCTAssertFalse(d.isSavable, "every role needs a named model before Save")
    }

    func testCommitDuplicatesBuiltInToCustomAndLeavesBuiltInUntouched() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer, minEffort: .low)]

        let id = try d.commit()
        let saved = TeamCatalog.get(id)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.builtIn, false, "the saved team is a custom")
        XCTAssertNotEqual(id, buildBase.id, "a new custom id, not the built-in's")
        XCTAssertEqual(saved?.workerSpecs.count, 1)
        XCTAssertEqual(saved?.workerSpecs.first?.skillId, buildSkill)
        XCTAssertEqual(saved?.workerSpecs.first?.preferredModelId, "model_opus", "saved by name, not Auto")
        XCTAssertTrue(TeamCatalog.list(lane: .build).contains { $0.id == id }, "shows in the lane catalog")
        XCTAssertEqual(TeamCatalog.get(buildBase.id)?.builtIn, true, "the built-in is never mutated")
    }

    func testWrongLaneSkillIsRejectedWithNoOrphanLeftBehind() throws {
        guard let designSkill = SkillCatalog.list(lane: .design).first?.id else {
            throw XCTSkip("no design skills to cross with")
        }
        let before = TeamCatalog.list(lane: .build).count
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows = [.init(id: "r1", skillId: designSkill, modelId: "model_opus", purpose: .answer, minEffort: .low)]

        XCTAssertThrowsError(try d.commit()) { err in
            guard case CatalogError.skillLaneMismatch = err else {
                return XCTFail("expected skillLaneMismatch, got \(err)")
            }
        }
        XCTAssertEqual(TeamCatalog.list(lane: .build).count, before,
                       "a rejected save must not leave an orphan custom team")
    }
}
