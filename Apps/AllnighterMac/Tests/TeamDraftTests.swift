import XCTest
import AllnighterCore
@testable import AllnighterMac

/// The Customize editor's write path. Team Save is roster-only; skill bodies commit on
/// Agent Done via `WorkerSkillCommit`. Catalog is isolated to a temp dir.
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

    private func customSkillCount() -> Int {
        SkillCatalog.list(lane: .code).filter { SkillCatalog.origin(of: $0.id) == .custom }.count
    }

    func testSeedFromBuiltInKeepsRealNameUntilSaved() {
        let d = TeamDraft(base: buildBase)
        XCTAssertEqual(d.name, buildBase.displayName)
        XCTAssertFalse(d.name.contains("(custom)"))
        XCTAssertEqual(d.rows.map(\.modelId), buildBase.agentSpecs.map(\.preferredModelId))
    }

    func testSavableAllowsAutoModel() throws {
        let pinned = try XCTUnwrap(
            TeamCatalog.list(lane: .code).first {
                $0.builtIn && !$0.agentSpecs.isEmpty
                    && $0.agentSpecs.allSatisfy { $0.preferredModelId != nil }
                    && $0.lead.preferredModelId != nil
            }
        )
        var d = TeamDraft(base: pinned)
        XCTAssertTrue(d.isSavable)

        d.rows[0].modelId = nil
        XCTAssertTrue(d.isSavable, "nil model = Auto and must not block team save")
    }

    func testSavingABuiltInKeepsItsNameAndId() throws {
        let base = buildBase
        var d = TeamDraft(base: base)
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer)]
        let id = try d.commit()
        XCTAssertEqual(id, base.id)
        XCTAssertEqual(TeamCatalog.get(id)?.displayName, base.displayName)
    }

    func testNotSavableWithoutSkillId() {
        var d = TeamDraft(base: buildBase)
        d.rows[0].skillId = ""
        XCTAssertFalse(d.isSavable)
    }

    func testCommitEditsBuiltInInPlaceNoDuplicateAndRestoreReverts() throws {
        let base = buildBase
        var d = TeamDraft(base: base)
        d.rows = [.init(id: "r1", skillId: buildSkill, modelId: "model_opus", purpose: .answer)]

        let id = try d.commit()
        let saved = TeamCatalog.get(id)
        XCTAssertEqual(id, base.id)
        XCTAssertEqual(saved?.builtIn, false)
        XCTAssertEqual(saved?.agentSpecs.first?.preferredModelId, "model_opus")
        XCTAssertEqual(TeamCatalog.list(lane: .code).filter { $0.id == id }.count, 1)

        _ = try TeamCatalog.restore(id)
        XCTAssertEqual(TeamCatalog.get(base.id)?.builtIn, true)
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
        XCTAssertEqual(TeamCatalog.list(lane: .code).count, before)
    }

    func testTeamSaveDoesNotWriteSkills() throws {
        let before = customSkillCount()
        var d = TeamDraft(base: buildBase)
        d.rows[0].modelId = "model_grok"
        _ = try d.commit()
        XCTAssertEqual(customSkillCount(), before, "roster-only save must not mint skills")
    }

    func testWorkerDoneSharedOverrideSurvivesTeamCancel() throws {
        _ = try WorkerSkillCommit.apply(.init(
            skillId: buildSkill, template: "WSS_TEAM_CANCEL_SENTINEL", modelId: nil,
            lane: .code, defaultPurpose: .answer, isNewSkill: false
        ))
        var d = TeamDraft(base: buildBase)
        d.rows[0].modelId = "model_grok"
        _ = try d.commit()
        XCTAssertTrue(SkillCatalog.get(buildSkill)?.template.contains("WSS_TEAM_CANCEL_SENTINEL") == true)
    }

    func testNewSkillCreatedOnWorkerDoneNotTeamSave() throws {
        let before = customSkillCount()
        let created = try WorkerSkillCommit.apply(.init(
            skillId: "", template: "Brand new body.", modelId: "model_opus",
            lane: .code, defaultPurpose: .answer, isNewSkill: true, newSkillName: "My Fresh Skill"
        ))
        XCTAssertEqual(customSkillCount(), before + 1)
        XCTAssertEqual(SkillCatalog.get(created.skillId)?.displayName, "My Fresh Skill")

        var d = TeamDraft(base: buildBase)
        d.rows[0].skillId = created.skillId
        _ = try d.commit()
        XCTAssertNotNil(SkillCatalog.get(created.skillId), "explicit new skill survives roster save")
    }

    func testSavePreservesOrderedFallbackChainsTheEditorDoesNotExpose() throws {
        let base = try XCTUnwrap(BuiltInTeams.team("code_spec_review_max"))
        let workerChains = Dictionary(
            uniqueKeysWithValues: base.agentSpecs.map { ($0.id, $0.fallbackModelIds ?? []) })
        let leadChain = base.lead.fallbackModelIds
        let scoutChain = base.scout?.fallbackModelIds

        let id = try TeamDraft(base: base).commit()
        let saved = try XCTUnwrap(TeamCatalog.get(id))

        for row in saved.agentSpecs {
            XCTAssertEqual(row.fallbackModelIds ?? [], workerChains[row.id] ?? [], row.id)
        }
        XCTAssertEqual(saved.lead.fallbackModelIds, leadChain)
        XCTAssertEqual(saved.scout?.fallbackModelIds, scoutChain)
    }

    func testSavePreservesAllHiddenRoutingMetadata() throws {
        let worker = TeamAgentSpec(
            id: "meta_worker", skillId: buildSkill, purpose: .answer,
            preferredModelId: "model_opus",
            fallbackModelIds: ["model_kimi_k3", "model_grok"],
            allowedModelIds: ["model_opus", "model_kimi_k3", "model_grok"],
            requiredCapabilityTags: [.review],
            count: 2, fallbackPolicy: .laneCapable, required: false,
            triangulate: true,
            triangulatePreferenceIds: ["model_grok", "model_kimi_k3"])
        let scout = TeamAgentSpec(
            id: "meta_scout", skillId: buildSkill, purpose: .answer,
            preferredModelId: "model_grok",
            fallbackModelIds: ["model_kimi_k3"],
            allowedModelIds: ["model_grok", "model_kimi_k3"],
            requiredCapabilityTags: [.code],
            count: 1, fallbackPolicy: .laneCapable, required: false)
        let lead = TeamLeadSpec(
            skillId: "plan_writer_build",
            preferredModelId: "model_opus",
            fallbackModelIds: ["model_cursor_gpt_sol", "model_kimi_k3"],
            requiredCapabilityTags: [.planner],
            fallbackPolicy: .laneCapable,
            dissentPolicy: .compareOptions)
        let base = TeamPreset(
            id: "code_metadata_test", displayName: "Metadata Test", lane: .code,
            outputKind: .plan, scout: scout, agentSpecs: [worker], lead: lead)

        let id = try TeamDraft(base: base).commit()
        let saved = try XCTUnwrap(TeamCatalog.get(id))
        XCTAssertEqual(saved.agentSpecs.first?.fallbackModelIds, worker.fallbackModelIds)
        XCTAssertEqual(saved.agentSpecs.first?.triangulate, worker.triangulate)
        XCTAssertEqual(saved.lead.fallbackModelIds, lead.fallbackModelIds)
        XCTAssertEqual(saved.scout?.fallbackModelIds, scout.fallbackModelIds)
    }

    func testMutatingMixedSourceSaveIsBlocked() {
        var d = TeamDraft(base: buildBase)
        d.mutating = true
        if d.rows.count > 1 {
            d.rows[1].modelId = "model_gpt_sol"
        }
        XCTAssertThrowsError(try d.commit()) { error in
            guard case CatalogError.teamInvalid(let message) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(message.contains("one CLI"))
        }
    }
}
