import XCTest
import AllnighterCore
@testable import AllnighterMac

/// The Customize editor's write path. Editing a built-in saves the user's version IN
/// PLACE at the same id (an override) — never a duplicate — and the shipped seed stays
/// available via Restore. A failed save must leave no orphan; a wrong-lane skill must be
/// rejected. Catalog is isolated to a temp dir.
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
        let d = TeamDraft(base: buildBase)
        XCTAssertEqual(d.name, buildBase.displayName,
                       "selecting a built-in must NOT preemptively rename it to (custom)")
        XCTAssertFalse(d.name.contains("(custom)"))
        XCTAssertFalse(d.rows.isEmpty)
        XCTAssertTrue(d.rows.allSatisfy { $0.modelId != nil }, "rows pre-fill a concrete model")
        XCTAssertTrue(d.isSavable)
    }

    func testSavingABuiltInKeepsItsNameAndId() throws {
        let base = buildBase   // capture once — after a save the built-in carries an override
        var d = TeamDraft(base: base)
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer)]
        let id = try d.commit()
        XCTAssertEqual(id, base.id, "editing a built-in saves at the SAME id — no duplicate")
        XCTAssertEqual(TeamCatalog.get(id)?.displayName, base.displayName,
                       "the name is kept — never suffixed with (custom)")
    }

    func testNotSavableWithAModellessRow() {
        var d = TeamDraft(base: buildBase)
        d.rows[0].modelId = nil
        XCTAssertFalse(d.isSavable, "every role needs a named model before Save")
    }

    func testCommitEditsBuiltInInPlaceNoDuplicateAndRestoreReverts() throws {
        let base = buildBase   // capture once — recomputing after the save would skip it
        var d = TeamDraft(base: base)
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer)]

        let id = try d.commit()
        let saved = TeamCatalog.get(id)
        XCTAssertEqual(id, base.id, "saved at the built-in's own id — not a new custom id")
        XCTAssertEqual(saved?.builtIn, false, "the effective team is now the user's editable version")
        XCTAssertEqual(saved?.workerSpecs.count, 1)
        XCTAssertEqual(saved?.workerSpecs.first?.preferredModelId, "model_opus", "saved by name, not Auto")
        // Exactly one entry for this id in the catalog — no duplicate row.
        XCTAssertEqual(TeamCatalog.list(lane: .code).filter { $0.id == id }.count, 1)
        XCTAssertTrue(TeamCatalog.hasOverride(id), "a Restore is now available")

        // Restore reverts to the shipped seed.
        _ = try TeamCatalog.restore(id)
        XCTAssertEqual(TeamCatalog.get(base.id)?.builtIn, true, "restore reveals the shipped team")
        XCTAssertFalse(TeamCatalog.hasOverride(id))
    }

    func testWrongLaneSkillIsRejectedWithNoOrphanLeftBehind() throws {
        guard let designSkill = SkillCatalog.list(lane: .design).first?.id else {
            throw XCTSkip("no design skills to cross with")
        }
        let before = TeamCatalog.list(lane: .code).count
        var d = TeamDraft(base: buildBase)
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
        var d = TeamDraft(base: buildBase)
        d.rows[0].promptDraft = "edited but never saved (this is Cancel)"
        // No commit() — equivalent to Cancel.
        XCTAssertEqual(customBuildSkills().count, skillsBefore, "cancel forks no skill")
        XCTAssertEqual(customBuildTeams().count, teamsBefore, "cancel saves no team")
    }

    func testPromptEditForksCustomSkillOnSaveAndRepointsRow() throws {
        var d = TeamDraft(base: buildBase)
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
                       "<Skill> for <Team> naming — keyed to the saved team name (kept, not suffixed)")
        XCTAssertEqual(team.workerSpecs.first?.skillId, fork.id, "row repointed to the fork")
        XCTAssertEqual(SkillCatalog.get(originalSkillId)?.template, originalTemplate,
                       "the built-in skill is never mutated")
    }

    func testModelOnlyChangeDoesNotFork() throws {
        var d = TeamDraft(base: buildBase)
        d.rows[0].modelId = "model_grok"   // model only; no promptDraft
        let skillsBefore = customBuildSkills().count
        _ = try d.commit()
        XCTAssertEqual(customBuildSkills().count, skillsBefore, "changing only the model forks no skill")
    }

    func testSavePreservesOrderedFallbackChainsTheEditorDoesNotExpose() throws {
        let base = try XCTUnwrap(BuiltInTeams.team("code_spec_review_max"))
        let workerChains = Dictionary(
            uniqueKeysWithValues: base.workerSpecs.map { ($0.id, $0.fallbackModelIds ?? []) })
        let leadChain = base.lead.fallbackModelIds
        let scoutChain = base.scout?.fallbackModelIds

        let id = try TeamDraft(base: base).commit()
        let saved = try XCTUnwrap(TeamCatalog.get(id))

        for row in saved.workerSpecs {
            XCTAssertEqual(row.fallbackModelIds ?? [], workerChains[row.id] ?? [], row.id)
        }
        XCTAssertEqual(saved.lead.fallbackModelIds, leadChain)
        XCTAssertEqual(saved.scout?.fallbackModelIds, scoutChain)
    }

    func testSavePreservesAllHiddenRoutingMetadata() throws {
        let worker = TeamWorkerSpec(
            id: "meta_worker", skillId: buildSkill, purpose: .answer,
            preferredModelId: "model_opus",
            fallbackModelIds: ["model_kimi_k3", "model_grok"],
            allowedModelIds: ["model_opus", "model_kimi_k3", "model_grok"],
            requiredCapabilityTags: [.review],
            count: 2, fallbackPolicy: .laneCapable, required: false,
            triangulate: true,
            triangulatePreferenceIds: ["model_grok", "model_kimi_k3"])
        let scout = TeamWorkerSpec(
            id: "meta_scout", skillId: buildSkill, purpose: .answer,
            preferredModelId: "model_grok",
            fallbackModelIds: ["model_kimi_k3"],
            allowedModelIds: ["model_grok", "model_kimi_k3"],
            requiredCapabilityTags: [.code],
            count: 1, fallbackPolicy: .laneCapable, required: false)
        let lead = TeamLeadSpec(
            skillId: "plan_writer_build",
            preferredModelId: "model_opus",
            fallbackModelIds: ["model_chatgpt_sol", "model_kimi_k3"],
            requiredCapabilityTags: [.planner],
            fallbackPolicy: .laneCapable,
            dissentPolicy: .compareOptions)
        let base = TeamPreset(
            id: "code_metadata_test", displayName: "Metadata Test", lane: .code,
            outputKind: .plan, scout: scout, workerSpecs: [worker], lead: lead)

        let id = try TeamDraft(base: base).commit()
        let saved = try XCTUnwrap(TeamCatalog.get(id))
        XCTAssertEqual(saved.workerSpecs.first?.fallbackModelIds, worker.fallbackModelIds)
        XCTAssertEqual(saved.workerSpecs.first?.allowedModelIds, worker.allowedModelIds)
        XCTAssertEqual(saved.workerSpecs.first?.requiredCapabilityTags, worker.requiredCapabilityTags)
        XCTAssertEqual(saved.workerSpecs.first?.count, worker.count)
        XCTAssertEqual(saved.workerSpecs.first?.required, worker.required)
        XCTAssertEqual(saved.workerSpecs.first?.triangulate, worker.triangulate)
        XCTAssertEqual(saved.workerSpecs.first?.triangulatePreferenceIds, worker.triangulatePreferenceIds)
        XCTAssertEqual(saved.lead.fallbackModelIds, lead.fallbackModelIds)
        XCTAssertEqual(saved.lead.requiredCapabilityTags, lead.requiredCapabilityTags)
        XCTAssertEqual(saved.scout?.fallbackModelIds, scout.fallbackModelIds)
        XCTAssertEqual(saved.scout?.allowedModelIds, scout.allowedModelIds)
        XCTAssertEqual(saved.scout?.requiredCapabilityTags, scout.requiredCapabilityTags)
        XCTAssertEqual(saved.scout?.required, scout.required)
    }

    func testFailedTeamSaveRollsBackForkedSkill() throws {
        var d = TeamDraft(base: buildBase)
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
        var d = TeamDraft(base: buildBase)
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
        var d = TeamDraft(base: buildBase)
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
        var d = TeamDraft(base: buildBase)
        d.rows[0] = .init(id: "r_new", skillId: "", modelId: "model_opus",
                          purpose: .answer,
                          promptDraft: "has prompt", customSkillName: nil)
        XCTAssertFalse(d.isSavable, "a create-from-scratch row needs a name")
    }

    func testMutatingMixedSourceSaveIsBlocked() {
        var d = TeamDraft(base: buildBase)
        d.mutating = true
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
