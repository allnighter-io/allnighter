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
        TeamCatalog.list(lane: .code).first { $0.builtIn }!
    }
    private var buildSkill: String { SkillCatalog.list(lane: .code).first!.id }

    func testSeedFromBuiltInKeepsRealNameUntilSaved() {
        let d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        XCTAssertEqual(d.name, buildBase.displayName,
                       "selecting a built-in must NOT preemptively rename it to (custom)")
        XCTAssertFalse(d.name.contains("(custom)"))
        XCTAssertFalse(d.rows.isEmpty)
        XCTAssertTrue(d.rows.allSatisfy { $0.modelId != nil }, "rows pre-fill a concrete model")
        XCTAssertTrue(d.isSavable)
    }

    func testSavingAnUnrenamedBuiltInSuffixesCustomAtSaveTime() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer)]
        let id = try d.commit()
        XCTAssertEqual(TeamCatalog.get(id)?.displayName, "\(buildBase.displayName) (custom)",
                       "(custom) is appended only at Save, and only when the user didn't rename it")
    }

    func testNotSavableWithAModellessRow() {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows[0].modelId = nil
        XCTAssertFalse(d.isSavable, "every role needs a named model before Save")
    }

    func testCommitDuplicatesBuiltInToCustomAndLeavesBuiltInUntouched() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer)]

        let id = try d.commit()
        let saved = TeamCatalog.get(id)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.builtIn, false, "the saved team is a custom")
        XCTAssertNotEqual(id, buildBase.id, "a new custom id, not the built-in's")
        XCTAssertEqual(saved?.workerSpecs.count, 1)
        XCTAssertEqual(saved?.workerSpecs.first?.skillId, buildSkill)
        XCTAssertEqual(saved?.workerSpecs.first?.preferredModelId, "model_opus", "saved by name, not Auto")
        XCTAssertTrue(TeamCatalog.list(lane: .code).contains { $0.id == id }, "shows in the lane catalog")
        XCTAssertEqual(TeamCatalog.get(buildBase.id)?.builtIn, true, "the built-in is never mutated")
    }

    func testWrongLaneSkillIsRejectedWithNoOrphanLeftBehind() throws {
        guard let designSkill = SkillCatalog.list(lane: .design).first?.id else {
            throw XCTSkip("no design skills to cross with")
        }
        let before = TeamCatalog.list(lane: .code).count
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows = [.init(id: "r1", skillId: designSkill, modelId: "model_opus", purpose: .answer)]

        XCTAssertThrowsError(try d.commit()) { err in
            guard case CatalogError.skillLaneMismatch = err else {
                return XCTFail("expected skillLaneMismatch, got \(err)")
            }
        }
        XCTAssertEqual(TeamCatalog.list(lane: .code).count, before,
                       "a rejected save must not leave an orphan custom team")
    }

    // MARK: - S01A: save-time worker-prompt forking

    private func customBuildSkills() -> [Skill] {
        SkillCatalog.list(lane: .code).filter { !$0.builtIn }
    }
    private func customBuildTeams() -> [TeamPreset] {
        TeamCatalog.list(lane: .code).filter { !$0.builtIn }
    }

    func testEditingPromptDraftWithoutCommitWritesNothing() {
        let skillsBefore = customBuildSkills().count
        let teamsBefore = customBuildTeams().count
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows[0].promptDraft = "edited but never saved (this is Cancel)"
        // No commit() — equivalent to Cancel.
        XCTAssertEqual(customBuildSkills().count, skillsBefore, "cancel forks no skill")
        XCTAssertEqual(customBuildTeams().count, teamsBefore, "cancel saves no team")
    }

    func testPromptEditForksCustomSkillOnSaveAndRepointsRow() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        let originalSkillId = d.rows[0].skillId
        let originalTemplate = SkillCatalog.get(originalSkillId)?.template
        let originalName = SkillCatalog.get(originalSkillId)?.displayName ?? originalSkillId
        d.rows[0].promptDraft = "You are a tuned product architect. Be terse and ship."
        let skillsBefore = customBuildSkills().count

        let teamId = try d.commit()
        let team = try XCTUnwrap(TeamCatalog.get(teamId))
        let customs = customBuildSkills()
        XCTAssertEqual(customs.count, skillsBefore + 1, "exactly one fork is created")

        let fork = try XCTUnwrap(customs.first { $0.template.contains("tuned product architect") })
        XCTAssertFalse(fork.builtIn)
        XCTAssertEqual(fork.lane, .code, "fork inherits the team lane")
        XCTAssertEqual(fork.displayName, "\(originalName) for \(team.displayName)",
                       "<Skill> for <Team> naming — keyed to the SAVED team name (\"… (custom)\")")
        XCTAssertEqual(team.workerSpecs.first?.skillId, fork.id, "row repointed to the fork")
        XCTAssertEqual(SkillCatalog.get(originalSkillId)?.template, originalTemplate,
                       "the built-in skill is never mutated")
    }

    func testModelOnlyChangeDoesNotFork() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows[0].modelId = "model_grok"   // model only; no promptDraft
        let skillsBefore = customBuildSkills().count
        _ = try d.commit()
        XCTAssertEqual(customBuildSkills().count, skillsBefore, "changing only the model forks no skill")
    }

    func testFailedTeamSaveRollsBackForkedSkill() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        XCTAssertGreaterThan(d.rows.count, 1, "need a second row to force a team-save failure")
        d.rows[0].promptDraft = "tuned prompt that must roll back"
        // Force the team save to fail AFTER the fork: a later row points at no skill.
        d.rows[1].skillId = "nonexistent_skill_xyz"
        let skillsBefore = customBuildSkills().count
        let teamsBefore = customBuildTeams().count

        XCTAssertThrowsError(try d.commit(), "team save must fail on the unknown skill")
        XCTAssertEqual(customBuildSkills().count, skillsBefore,
                       "the forked skill is rolled back — no orphan custom skill")
        XCTAssertEqual(customBuildTeams().count, teamsBefore,
                       "no orphan custom team")
    }

    // MARK: - S03b: type-to-create + named forks

    func testTypeToCreateMakesANamedCustomSkillOnSave() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        // A brand-new skill (no source skillId), named by the user, prompt written.
        d.rows[0] = .init(id: "r_new", skillId: "", modelId: "model_opus",
                          purpose: .answer,
                          promptDraft: "Brand new behavior.", customSkillName: "My Fresh Skill")
        let skillsBefore = customBuildSkills().count

        let teamId = try d.commit()
        let team = try XCTUnwrap(TeamCatalog.get(teamId))
        let customs = customBuildSkills()
        XCTAssertEqual(customs.count, skillsBefore + 1, "one new skill created")
        let made = try XCTUnwrap(customs.first { $0.displayName == "My Fresh Skill" })
        XCTAssertEqual(made.template, "Brand new behavior.")
        XCTAssertEqual(made.lane, .code, "new skill inherits the team lane")
        XCTAssertEqual(team.workerSpecs.first { $0.id == "r_new" }?.skillId, made.id,
                       "row repointed to the new skill")
    }

    func testNamedForkUsesChosenNameNotAuto() throws {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        let sourceId = d.rows[0].skillId
        d.rows[0].promptDraft = "tuned"
        d.rows[0].customSkillName = "Renamed Skill"

        _ = try d.commit()
        let made = try XCTUnwrap(customBuildSkills().first { $0.template == "tuned" })
        XCTAssertEqual(made.displayName, "Renamed Skill",
                       "the chosen name wins over the auto <skill> for <team> name")
        XCTAssertNotEqual(made.id, sourceId, "a new custom skill, not the built-in")
    }

    func testNewSkillRowWithoutNameIsNotSavable() {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.rows[0] = .init(id: "r_new", skillId: "", modelId: "model_opus",
                          purpose: .answer,
                          promptDraft: "has prompt", customSkillName: nil)
        XCTAssertFalse(d.isSavable, "a create-from-scratch row needs a name")
    }

    func testMutatingMixedSourceSaveIsBlocked() {
        var d = TeamDraft(base: buildBase, defaultModelId: "model_opus")
        d.mutating = true
        d.posture = .execute
        if d.rows.count > 1 {
            d.rows[1].modelId = "model_chatgpt"
        }
        XCTAssertThrowsError(try d.commit()) { error in
            guard case CatalogError.teamInvalid(let message) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(message.contains("one CLI"))
        }
    }
}
