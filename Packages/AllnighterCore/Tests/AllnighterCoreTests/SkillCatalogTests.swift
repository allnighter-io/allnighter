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

    func testAssemblePromptPrefixesTemplate() {
        let assembled = SkillCatalog.assemblePrompt(skillId: "correct_fix_planner", founderPrompt: "FIX THE BUG")
        XCTAssertTrue(assembled.hasSuffix("FIX THE BUG"))
        XCTAssertTrue(assembled.contains("smallest correct fix"))
        // Unknown skill id -> founder prompt unchanged.
        XCTAssertEqual(SkillCatalog.assemblePrompt(skillId: "nope", founderPrompt: "X"), "X")
    }

    func testModelCapabilitiesAreDeterministicAndRanked() {
        // Flagship-only seats top the ladder (Fable + Sol); Opus is a strong high seat.
        XCTAssertEqual(ModelCatalog.capabilities("model_fable").strengthRank, 100)
        XCTAssertEqual(ModelCatalog.capabilities("model_chatgpt_sol").strengthRank, 99)
        XCTAssertEqual(ModelCatalog.capabilities("model_chatgpt").strengthRank, 99)
        XCTAssertEqual(ModelCatalog.capabilities("model_chatgpt_terra").strengthRank, 86)
        XCTAssertEqual(ModelCatalog.capabilities("model_opus").strengthRank, 90)
        XCTAssertEqual(ModelCatalog.capabilities("model_agy_opus").strengthRank, 75,
                       "AGY Opus is fallback-only; never outranks Claude Opus 5")
        XCTAssertLessThan(ModelCatalog.capabilities("model_agy_opus").strengthRank,
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
