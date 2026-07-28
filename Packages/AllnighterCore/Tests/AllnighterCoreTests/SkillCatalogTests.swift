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
        XCTAssertEqual(ModelCatalog.capabilities("model_chatgpt_sol").strengthRank, 99)
        XCTAssertEqual(ModelCatalog.capabilities("model_chatgpt").strengthRank, 99)
        XCTAssertEqual(ModelCatalog.capabilities("model_chatgpt_terra").strengthRank, 86)
        XCTAssertEqual(ModelCatalog.capabilities("model_opus").strengthRank, 90)
        XCTAssertLessThan(ModelCatalog.capabilities("model_gemini").strengthRank,
                          ModelCatalog.capabilities("model_opus").strengthRank)
        XCTAssertTrue(ModelCatalog.capabilities("model_opus").capabilityTags.contains(.planner))
        XCTAssertTrue(ModelCatalog.capabilities("model_gemini").capabilityTags.contains(.image))
        // Unknown model -> empty defaults, never a crash.
        XCTAssertEqual(ModelCatalog.capabilities("ghost").strengthRank, 0)
        // Strict ordering by rank for the known bench (matches ModelCatalog.builtInCapabilities).
        let ranked = [
            "model_fable", "model_chatgpt_sol", "model_chatgpt", "model_opus", "model_grok",
            "model_chatgpt_terra", "model_sonnet", "model_gemini", "model_composer",
        ]
            .map { ModelCatalog.capabilities($0).strengthRank }
        XCTAssertEqual(ranked, ranked.sorted(by: >))
    }

    func testModelCapabilitiesLaneTagsRemainMultiLane() {
        let opusLanes = ModelCatalog.capabilities("model_opus").laneTags
        XCTAssertGreaterThan(opusLanes.count, 1, "model capability laneTags stay multi-lane")
    }
}
