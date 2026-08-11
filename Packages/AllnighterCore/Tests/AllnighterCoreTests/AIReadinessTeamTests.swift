import XCTest
@testable import AllnighterCore

final class AIReadinessTeamTests: XCTestCase {

    func testTeamExistsAndHasCorrectMetadata() {
        let team = BuiltInTeams.team("code_ai_readiness")
        XCTAssertNotNil(team, "code_ai_readiness team must exist")
        guard let team else { return }

        XCTAssertEqual(team.id, "code_ai_readiness")
        XCTAssertEqual(team.displayName, "AI Readiness")
        XCTAssertEqual(team.lane, .code)
        XCTAssertEqual(team.outputKind, .aiReadinessReport)
        XCTAssertEqual(team.defaultEffort, .high)
        XCTAssertFalse(team.mutating, "AI Readiness is read-only advisory — must never mutate the repo")
        XCTAssertTrue(team.builtIn)
    }

    func testExactlyNineSeatsPresent() {
        let team = BuiltInTeams.team("code_ai_readiness")!
        let expectedAgentSkillIds: Set<String> = [
            "readiness_setup_scout",
            "readiness_context_cartographer",
            "readiness_measurement_auditor",
            "readiness_test_infra_scout",
            "readiness_loop_scout",
            "readiness_automation_mapper",
            "readiness_shape_specialist",
            "readiness_strength_scout"
        ]

        let agentSkillIds = Set(team.agentSpecs.map(\.skillId))
        XCTAssertEqual(agentSkillIds, expectedAgentSkillIds,
                       "eight parallel blind answer seats with exact skill ids")
        XCTAssertEqual(team.agentSpecs.count, 8)
        XCTAssertEqual(team.lead.skillId, "ai_readiness_writer",
                       "writer/Lead seat must be ai_readiness_writer")
    }

    func testEveryReferencedSkillExistsInCatalog() {
        let team = BuiltInTeams.team("code_ai_readiness")!
        let allSkillIds = team.agentSpecs.map(\.skillId) + [team.lead.skillId]

        for skillId in allSkillIds {
            let skill = SkillCatalog.skill(skillId)
            XCTAssertNotNil(skill, "skill '\(skillId)' referenced by code_ai_readiness must exist in SkillCatalog")
        }
    }

    func testAnswerSeatTemplatesRequireFindingPacket() {
        let answerSkillIds = [
            "readiness_setup_scout",
            "readiness_context_cartographer",
            "readiness_measurement_auditor",
            "readiness_test_infra_scout",
            "readiness_loop_scout",
            "readiness_automation_mapper",
            "readiness_shape_specialist",
            "readiness_strength_scout"
        ]

        for skillId in answerSkillIds {
            let skill = SkillCatalog.skill(skillId)
            XCTAssertNotNil(skill, "answer skill \(skillId) must exist")
            guard let template = skill?.template else { continue }

            XCTAssertTrue(template.contains("Finding packet"),
                          "\(skillId) template must mention 'Finding packet'")
            XCTAssertTrue(template.contains("strengths"),
                          "\(skillId) template must include strengths[] field")
            XCTAssertTrue(template.contains("couldNotDetermine"),
                          "\(skillId) template must include couldNotDetermine[] field")
            XCTAssertTrue(template.contains("seatId"),
                          "\(skillId) template must include seatId in finding packet")
            XCTAssertTrue(template.contains("evidence"),
                          "\(skillId) template must require evidence field")
        }
    }

    func testAllTemplatesBanScoreLanguage() {
        let allSkillIds = [
            "readiness_setup_scout",
            "readiness_context_cartographer",
            "readiness_measurement_auditor",
            "readiness_test_infra_scout",
            "readiness_loop_scout",
            "readiness_automation_mapper",
            "readiness_shape_specialist",
            "readiness_strength_scout",
            "ai_readiness_writer"
        ]

        let bannedPhrases = ["score", "grade", "rating", "percentage"]

        for skillId in allSkillIds {
            let skill = SkillCatalog.skill(skillId)
            XCTAssertNotNil(skill, "skill \(skillId) must exist")
            guard let template = skill?.template else { continue }

            let lower = template.lowercased()
            for phrase in bannedPhrases {
                let containsScore = lower.contains(phrase)
                // The ban is on USING scores — the template may MENTION the ban
                // to teach the agent not to use them. Check that the surrounding
                // context is a prohibition, not an instruction to produce one.
                if containsScore {
                    let around = lower.range(of: phrase).map { range in
                        let start = lower.index(range.lowerBound, offsetBy: -30, limitedBy: lower.startIndex) ?? lower.startIndex
                        let end = lower.index(range.upperBound, offsetBy: 30, limitedBy: lower.endIndex) ?? lower.endIndex
                        return String(lower[start..<end])
                    } ?? ""
                    XCTAssertTrue(around.contains("ban") || around.contains("no ") || around.contains("do not") || around.contains("never"),
                                  "\(skillId) template uses '\(phrase)' in context: '\(around)' — must be a prohibition, not an instruction")
                }
            }
        }
    }

    func testWriterTemplateRequiresAIReadinessReportMachineBlock() {
        let writer = SkillCatalog.skill("ai_readiness_writer")
        XCTAssertNotNil(writer)
        guard let template = writer?.template else { return }

        XCTAssertTrue(template.contains("ai-readiness-report"),
                      "writer template must reference ai-readiness-report fenced block")
        XCTAssertTrue(template.contains("AIReadinessReport"),
                      "writer template must reference AIReadinessReport schema")
    }

    func testMeasurementAuditorCharterMatchesLegacySpirit() {
        let readinessAuditor = SkillCatalog.skill("readiness_measurement_auditor")
        let legacyAuditor = SkillCatalog.skill("measurement_auditor")

        XCTAssertNotNil(readinessAuditor)
        XCTAssertNotNil(legacyAuditor)

        guard let readinessTemplate = readinessAuditor?.template,
              let legacyTemplate = legacyAuditor?.template else { return }

        // Core measurement-audit phrases must carry over to the readiness version
        let sharedPhrases = [
            "cannot be made to fail",
            "fitted validator",
            "gone red",
            "yardstick",
            "worst case"
        ]
        for phrase in sharedPhrases {
            XCTAssertTrue(readinessTemplate.lowercased().contains(phrase.lowercased()),
                          "readiness_measurement_auditor must itself carry: \(phrase)")
        }

        // Must be distinct ids
        XCTAssertNotEqual(readinessAuditor?.id, legacyAuditor?.id)
        XCTAssertEqual(readinessAuditor?.id, "readiness_measurement_auditor")
        XCTAssertEqual(legacyAuditor?.id, "measurement_auditor")
    }

    func testStrengthScoutIsStrengthsOnly() {
        let skill = SkillCatalog.skill("readiness_strength_scout")
        XCTAssertNotNil(skill)
        guard let template = skill?.template else { return }

        XCTAssertTrue(template.contains("strengths only") || template.contains("findings\": []") || template.contains("\"findings\": []"),
                      "strength_scout must signal findings: [] and strengths only")
        XCTAssertTrue(template.contains("strengths"),
                      "strength_scout must include strengths array in finding packet")
        XCTAssertTrue(template.contains("Ban YAML") || template.contains("JSON only"),
                      "strength_scout must require JSON finding packet")
    }

    func testLeadUsesCompareOptionsDissent() {
        let team = BuiltInTeams.team("code_ai_readiness")!
        XCTAssertEqual(team.lead.dissentPolicy, .compareOptions,
                       "AI Readiness multi-seat team uses compareOptions (matching Spec Review pattern)")
    }

    func testWriterLocksAIReadinessReportSchemaAndPartialOnSeatFailure() {
        let writer = SkillCatalog.skill("ai_readiness_writer")!
        let template = writer.template
        XCTAssertTrue(template.contains("agreedCount"))
        XCTAssertTrue(template.contains("totalCount"))
        XCTAssertTrue(template.contains("Partial"))
        XCTAssertTrue(template.contains("Ban alternate keys") || template.contains("attributedTo"))
        XCTAssertTrue(template.contains("\"seatId\""))
        XCTAssertFalse(template.contains("consensus\":"),
                       "writer must not teach consensus as a receipt field")
    }

    func testLoopScoutPrefersNonOpenCodeModel() {
        let team = BuiltInTeams.team("code_ai_readiness")!
        let loop = team.agentSpecs.first { $0.skillId == "readiness_loop_scout" }
        XCTAssertNil(loop?.preferredModelId, "Law 3: loop scout must not pin model identity")
        XCTAssertTrue(loop?.fallbackModelIds?.contains("model_gpt_sol") ?? false)
        XCTAssertFalse(loop?.fallbackModelIds?.contains(where: { $0.contains("opencode") }) ?? false)
    }

    func testTeamHasTypeTagsAndStarters() {
        let team = BuiltInTeams.team("code_ai_readiness")!
        XCTAssertFalse(team.typeTags.isEmpty, "must have type tags")
        XCTAssertTrue(team.typeTags.contains("ai-readiness"))
        XCTAssertFalse(team.starterPrompts.isEmpty, "must have starter prompts")
    }
}
