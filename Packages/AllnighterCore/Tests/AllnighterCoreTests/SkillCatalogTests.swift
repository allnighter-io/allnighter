import XCTest
@testable import AllnighterCore

final class SkillCatalogTests: XCTestCase {

    func testBuiltInSkillIdsAreUnique() {
        let ids = SkillCatalog.builtIns.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate built-in skill ids")
    }

    func testEverySkillHasNonEmptyTemplateAndLane() {
        for skill in SkillCatalog.builtIns {
            XCTAssertFalse(skill.template.isEmpty, "\(skill.id) has empty template")
            XCTAssertTrue(WorkLane.allCases.contains(skill.lane), "\(skill.id) has invalid lane")
            XCTAssertTrue(skill.builtIn)
        }
    }

    func testEveryBuiltInSkillHasExactlyOneLane() {
        for skill in SkillCatalog.builtIns {
            XCTAssertEqual(SkillCatalog.skills(in: skill.lane).filter { $0.id == skill.id }.count, 1)
            for lane in WorkLane.allCases where lane != skill.lane {
                XCTAssertFalse(SkillCatalog.skills(in: lane).contains { $0.id == skill.id },
                               "\(skill.id) must not appear in \(lane.rawValue) catalog list")
            }
        }
    }

    func testKnownSkillsResolveByID() {
        XCTAssertEqual(SkillCatalog.skill("bug_reproducer")?.displayName, "Bug Reproducer")
        XCTAssertEqual(SkillCatalog.skill("bug_packet_writer")?.purpose, .planWriter)
        XCTAssertEqual(SkillCatalog.skill("offer_strategist")?.lane, .copy)
        XCTAssertNil(SkillCatalog.skill("does_not_exist"))
    }

    func testLaneFilteringSeparatesBuildDesignCopy() {
        XCTAssertTrue(SkillCatalog.skills(in: .code).contains { $0.id == "product_architect" })
        XCTAssertFalse(SkillCatalog.skills(in: .code).contains { $0.id == "information_architect" })
        XCTAssertTrue(SkillCatalog.skills(in: .design).contains { $0.id == "design_critic" })
        XCTAssertTrue(SkillCatalog.skills(in: .copy).contains { $0.id == "objection_hunter" })
    }

    func testLeadCallEnvelopeInjectedForEveryPlanWriter() throws {
        let planWriters = SkillCatalog.builtIns.filter { $0.purpose == .planWriter }
        XCTAssertFalse(planWriters.isEmpty)
        for skill in planWriters {
            let assembled = SkillCatalog.assemblePrompt(skillId: skill.id, founderPrompt: "FOUNDER")
            XCTAssertTrue(assembled.contains("Lead Call envelope"), skill.id)
            XCTAssertTrue(assembled.contains("```lead-call"), skill.id)
            XCTAssertTrue(assembled.hasSuffix("FOUNDER"), skill.id)
            // Ban the old Spec Review failure mode in the injected law.
            XCTAssertTrue(assembled.contains("Never say \"not ready to build.\""), skill.id)
            XCTAssertFalse(assembled.contains("Seat brief"), skill.id)
        }
        // Answer seats get the elevator seat brief, not Lead Call.
        let answerAssembled = SkillCatalog.assemblePrompt(
            skillId: "spec_first_principles_reviewer", founderPrompt: "X")
        XCTAssertFalse(answerAssembled.contains("Lead Call envelope"))
        XCTAssertTrue(answerAssembled.contains("Seat brief"))
        XCTAssertTrue(answerAssembled.contains("```seat"))
        let docAssembled = SkillCatalog.assemblePrompt(
            skillId: SkillCatalog.docReviewerSkillId, founderPrompt: "Review docs/phases/Foo.md")
        XCTAssertTrue(docAssembled.contains("core promise"))
        XCTAssertTrue(docAssembled.contains("80/20"))
        XCTAssertFalse(docAssembled.contains("Seat brief"))
        XCTAssertFalse(docAssembled.contains("Lead Call envelope"))
    }

    func testSpecReviewWriterIsCraftBodyNotFullDocRewrite() throws {
        let template = try XCTUnwrap(SkillCatalog.skill("spec_review_writer")?.template)
        XCTAssertTrue(template.contains("Craft body"), template)
        XCTAssertTrue(template.contains("not a full rewritten phase doc"), template)
        XCTAssertFalse(template.contains("edits the founder should make"), template)
        XCTAssertFalse(template.contains("What is the single biggest gap?"), template)
        let assembled = SkillCatalog.assemblePrompt(
            skillId: "spec_review_writer", founderPrompt: "harden me")
        XCTAssertTrue(assembled.contains("Lead Call envelope"), assembled)
        XCTAssertTrue(assembled.contains("Partial"), assembled)
        XCTAssertTrue(assembled.contains("Never say \"not ready to build.\""), assembled)
    }

    func testAssemblePromptPrefixesTemplate() {
        let assembled = SkillCatalog.assemblePrompt(skillId: "correct_fix_planner", founderPrompt: "FIX THE BUG")
        XCTAssertTrue(assembled.hasSuffix("FIX THE BUG"))
        XCTAssertTrue(assembled.contains("smallest correct fix"))
        // Unknown skill id -> founder prompt unchanged.
        XCTAssertEqual(SkillCatalog.assemblePrompt(skillId: "nope", founderPrompt: "X"), "X")
    }

    func testDesignBoardAnswerSeatsReceiveCaptureBrief() {
        let designAnswerIds = [
            "visual_system_designer", "minimal_direction", "bold_direction", "editorial_direction",
            "minimal", "bold", "editorial"
        ]
        for skillId in designAnswerIds {
            let assembled = SkillCatalog.assemblePrompt(
                skillId: skillId, founderPrompt: "DESIGN", outputKind: .designBoard)
            XCTAssertTrue(assembled.contains("Design capture"), skillId)
            XCTAssertTrue(assembled.contains("option_<your-worker-id>.html"), skillId)
            XCTAssertTrue(assembled.contains("capture: html"), skillId)
            XCTAssertTrue(assembled.contains("Never") && assembled.contains("imageGen"), skillId)
            XCTAssertTrue(assembled.contains("Midjourney"), skillId)
            XCTAssertTrue(assembled.contains("Seat brief"), skillId)
            XCTAssertTrue(assembled.hasSuffix("DESIGN"), skillId)
        }
        // Polish-board answer seats must not get capture law without designBoard output.
        let polish = SkillCatalog.assemblePrompt(
            skillId: "hierarchy_sculptor", founderPrompt: "POLISH", outputKind: .polishBoard)
        XCTAssertFalse(polish.contains("Design capture"))
        // Code answer seats never get design capture.
        let code = SkillCatalog.assemblePrompt(
            skillId: "bug_reproducer", founderPrompt: "BUG", outputKind: .designBoard)
        XCTAssertFalse(code.contains("Design capture"))
        // Design review seats get seat brief only.
        let review = SkillCatalog.assemblePrompt(
            skillId: "accessibility_reviewer", founderPrompt: "A11Y", outputKind: .designBoard)
        XCTAssertTrue(review.contains("Seat brief"))
        XCTAssertFalse(review.contains("Design capture"))
    }

    func testDesignBoardWriterIsSpecStyleCloseout() throws {
        let skill = try XCTUnwrap(SkillCatalog.skill("design_board_writer"))
        XCTAssertTrue(skill.template.contains("Incorporate list"))
        XCTAssertTrue(skill.template.contains("Verified on disk"))
        XCTAssertTrue(skill.template.contains("Option A/B"))
        XCTAssertTrue(skill.template.contains("visible labels") || skill.template.contains("tile label"))
        let assembled = SkillCatalog.assemblePrompt(skillId: "design_board_writer", founderPrompt: "DESIGN")
        XCTAssertTrue(assembled.contains("Lead Call envelope"))
        XCTAssertTrue(assembled.contains("Incorporate list"))
    }

    func testDesignSeatCaptureBriefDeclaresPathConvention() {
        XCTAssertTrue(SkillCatalog.designSeatCaptureBrief.contains("capture: html"))
        XCTAssertTrue(SkillCatalog.designSeatCaptureBrief.contains("capture: svg"))
        XCTAssertTrue(SkillCatalog.designSeatCaptureBrief.contains("native"))
        XCTAssertTrue(SkillCatalog.designSeatCaptureBrief.contains("concept"))
        XCTAssertTrue(SkillCatalog.designSeatCaptureBrief.contains("SwiftUI"))
    }

    func testModelCapabilitiesAreDeterministicAndRanked() {
        // Flagship-only seats top the ladder (Fable + Sol); Opus is a strong high seat.
        XCTAssertEqual(ModelCatalog.capabilities("model_fable").strengthRank, 100)
        XCTAssertEqual(ModelCatalog.capabilities("model_cursor_gpt_sol").strengthRank, 99)
        XCTAssertEqual(ModelCatalog.capabilities("model_gpt_sol").strengthRank, 99)
        XCTAssertEqual(ModelCatalog.capabilities("model_gpt_terra").strengthRank, 86)
        XCTAssertEqual(ModelCatalog.capabilities("model_opus").strengthRank, 90)
        XCTAssertLessThan(ModelCatalog.capabilities("model_gemini").strengthRank,
                          ModelCatalog.capabilities("model_opus").strengthRank)
        XCTAssertTrue(ModelCatalog.capabilities("model_opus").capabilityTags.contains(.planner))
        XCTAssertTrue(ModelCatalog.capabilities("model_gemini").capabilityTags.contains(.image))
        // Unknown model -> empty defaults, never a crash.
        XCTAssertEqual(ModelCatalog.capabilities("ghost").strengthRank, 0)
        // Strict ordering by rank for the known bench (matches ModelCatalog.builtInCapabilities).
        let ranked = [
            "model_fable", "model_cursor_gpt_sol", "model_gpt_sol", "model_opus", "model_grok",
            "model_gpt_terra", "model_sonnet", "model_gemini", "model_grok_composer_25_fast",
        ]
            .map { ModelCatalog.capabilities($0).strengthRank }
        XCTAssertEqual(ranked, ranked.sorted(by: >))
    }

    func testModelCapabilitiesLaneTagsRemainMultiLane() {
        let opusLanes = ModelCatalog.capabilities("model_opus").laneTags
        XCTAssertGreaterThan(opusLanes.count, 1, "model capability laneTags stay multi-lane")
    }

    // MARK: - WSS-S01 shared-skill overrides

    private var skillsRoot: URL!
    private var teamsRoot: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-catalog-\(UUID().uuidString)", isDirectory: true)
        teamsRoot = base.appendingPathComponent("teams", isDirectory: true)
        skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: teamsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        super.tearDown()
    }

    func testOverridePrecedenceAndOneEntryMerge() throws {
        var override = try XCTUnwrap(SkillCatalog.get("bug_reproducer"))
        override.template = "WSS_SENTINEL: shared override."
        try SkillCatalog.saveOverride(override)

        XCTAssertEqual(SkillCatalog.origin(of: "bug_reproducer"), .override)
        XCTAssertTrue(SkillCatalog.hasOverride("bug_reproducer"))
        XCTAssertEqual(SkillCatalog.get("bug_reproducer")?.template, "WSS_SENTINEL: shared override.")
        XCTAssertEqual(SkillCatalog.list(lane: .code).filter { $0.id == "bug_reproducer" }.count, 1)
        XCTAssertTrue(SkillCatalog.assemblePrompt(skillId: "bug_reproducer", founderPrompt: "X")
            .contains("WSS_SENTINEL"))
    }

    func testRestoreIsIdempotent() throws {
        var override = try XCTUnwrap(SkillCatalog.get("bug_reproducer"))
        override.template = "temporary edit"
        try SkillCatalog.saveOverride(override)

        let r1 = try SkillCatalog.restore("bug_reproducer")
        XCTAssertTrue(r1.removedOverride)
        XCTAssertEqual(SkillCatalog.origin(of: "bug_reproducer"), .seed)

        let r2 = try SkillCatalog.restore("bug_reproducer")
        XCTAssertFalse(r2.removedOverride)
        XCTAssertEqual(SkillCatalog.origin(of: "bug_reproducer"), .seed)
    }

    func testRestoreUnsupportedForCustomSkill() throws {
        let custom = try SkillCatalog.duplicateBuiltIn("bug_reproducer", name: "Custom Only")
        XCTAssertThrowsError(try SkillCatalog.restore(custom.id)) { error in
            XCTAssertEqual(error as? CatalogError, .restoreUnsupported)
        }
    }

    func testSaveOverrideRejectsLaneOrPurposeChange() throws {
        var override = try XCTUnwrap(SkillCatalog.get("bug_reproducer"))
        override.lane = .design
        XCTAssertThrowsError(try SkillCatalog.saveOverride(override)) { error in
            guard case CatalogError.skillInvalid = error else { return XCTFail("expected skillInvalid") }
        }
    }

    func testBugReproducerOverrideVisibleToAllBugHuntTeams() throws {
        var override = try XCTUnwrap(SkillCatalog.get("bug_reproducer"))
        override.template = "SHARED_BUG_SENTINEL"
        try SkillCatalog.saveOverride(override)

        for teamId in ["code_bug_hunt_min", "code_bug_hunt", "code_bug_hunt_max"] {
            let team = try XCTUnwrap(TeamCatalog.get(teamId))
            XCTAssertTrue(team.agentSpecs.contains { $0.skillId == "bug_reproducer" })
            XCTAssertTrue(
                SkillCatalog.assemblePrompt(skillId: "bug_reproducer", founderPrompt: "Q")
                    .contains("SHARED_BUG_SENTINEL"),
                teamId
            )
        }
        let names = SkillCatalog.teamDisplayNamesReferencingSkill("bug_reproducer")
        XCTAssertTrue(names.contains("Bug Hunt Min"))
        XCTAssertTrue(names.contains("Bug Hunt"))
        XCTAssertTrue(names.contains("Bug Hunt Max"))
    }

    func testWorkerSkillCommitCreatesNewSkillImmediately() throws {
        let result = try WorkerSkillCommit.apply(.init(
            skillId: "", template: "Fresh body.", modelId: nil, lane: .code,
            defaultPurpose: .answer, isNewSkill: true, newSkillName: "Fresh Skill"
        ))
        XCTAssertFalse(result.skillId.isEmpty)
        XCTAssertEqual(SkillCatalog.get(result.skillId)?.displayName, "Fresh Skill")
    }

    func testWorkerSkillCommitSavesExistingBodyAtSameId() throws {
        var override = try XCTUnwrap(SkillCatalog.get("bug_reproducer"))
        override.template = "before"
        try SkillCatalog.saveOverride(override)

        _ = try WorkerSkillCommit.apply(.init(
            skillId: "bug_reproducer", template: "after worker done", modelId: nil,
            lane: .code, defaultPurpose: .answer, isNewSkill: false
        ))
        XCTAssertEqual(SkillCatalog.get("bug_reproducer")?.template, "after worker done")
    }
}
