import XCTest
@testable import AllnighterCore

final class BuiltInTeamsTests: XCTestCase {

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    // MARK: - Catalog integrity

    func testRequiredBuiltInIdsArePresent() {
        let required = [
            "code_core", "code_bug_hunt_lite", "code_bug_hunt", "code_gui_bug_hunt", "code_security_review",
            "code_spec_review", "code_release_proof",
            "default_chat", "execution_playbook",
            "design_core", "design_premium_polish", "design_conversion_studio",
            "design_radical_directions", "design_usability_triage",
            "copy_core", "copy_landing_page",
            "signal_post_to_project", "signal_what_to_build_next"
        ]
        for id in required {
            XCTAssertNotNil(BuiltInTeams.team(id), "missing built-in team \(id)")
            XCTAssertTrue(BuiltInTeams.team(id)?.builtIn ?? false)
        }
        XCTAssertEqual(BuiltInTeams.all.count, required.count)
    }

    func testSpecReviewCarriesGeneralSpecReviewLineup() {
        let team = BuiltInTeams.team("code_spec_review")!
        XCTAssertEqual(team.displayName, "Spec Review")
        XCTAssertEqual(team.outputKind, .specReview)
        XCTAssertEqual(team.defaultEffort, .high)
        XCTAssertEqual(team.typeTags, ["launch", "spec-review"])
        XCTAssertEqual(team.scout?.skillId, "spec_outside_scout")
        XCTAssertEqual(team.scout?.preferredModelId, "model_grok")
        XCTAssertEqual(team.lead.skillId, "spec_review_writer")
        XCTAssertEqual(team.lead.preferredModelId, "model_opus")
        XCTAssertEqual(Set(team.workerSpecs.map(\.skillId)), [
            "spec_first_principles_reviewer",
            "spec_doc_hygiene_reviewer",
            "spec_contract_auditor",
            "spec_proof_planner",
            "spec_scope_steward",
            "spec_hype_skeptic",
            "spec_contrarian_reviewer"
        ])
        XCTAssertTrue(team.workerSpecs.allSatisfy { $0.preferredModelId != nil })
    }

    func testSynthesisTeamsPreferOpusLeadAndDiverseWorkersOnFullBench() {
        let ready: [Model] = [
            opus(),
            Model(id: "model_cursor_composer_25", displayName: "Composer 2.5", modelLabel: "composer-2.5",
                  driverId: "cursor_agent", role: .answerer),
            Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .answerer),
            Model(id: "model_gemini", displayName: "Gemini 3.5 Flash", modelLabel: "g", driverId: "antigravity", role: .answerer),
            Model(id: "model_sonnet", displayName: "Sonnet 4.6", modelLabel: "sonnet", driverId: "claude_code", role: .answerer),
            Model(id: "model_grok", displayName: "Grok Build", modelLabel: "grok-build", driverId: "grok", role: .answerer),
        ]
        let team = BuiltInTeams.team("code_spec_review")!
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .high, readyModels: ready)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.planWriter?.modelId, "model_opus")
        XCTAssertEqual(r.scoutWorker?.modelId, "model_grok")
        let crew = r.answerWorkers + r.reviewWorkers
        let opusWorkers = crew.filter { $0.modelId == "model_opus" }
        XCTAssertEqual(opusWorkers.count, 1, "one strategic Opus worker, not a pile-up")
        XCTAssertEqual(opusWorkers.first?.skillId, "spec_first_principles_reviewer")
        XCTAssertGreaterThan(Set(crew.map(\.modelId)).count, 2, "fan-out should spread across multiple models")
    }

    func testTierOneTeamsCarryOneStrategicOpusWorker() {
        let tierOne: [String: String] = [
            "code_core": "first_principles_builder",
            "code_bug_hunt": "contrarian_root_cause",
            "code_gui_bug_hunt": "contrarian_root_cause",
            "code_security_review": "security_fix_prioritizer",
            "code_spec_review": "spec_first_principles_reviewer",
            "code_release_proof": "acceptance_auditor",
        ]
        for (teamId, skillId) in tierOne {
            let row = BuiltInTeams.team(teamId)?.workerSpecs.first { $0.skillId == skillId }
            XCTAssertEqual(row?.preferredModelId, "model_opus", "\(teamId) strategic worker \(skillId)")
        }
    }

    func testEverySynthesisTeamReservesOpusForLead() {
        let passthrough: Set<String> = ["default_chat", "execution_playbook"]
        for team in BuiltInTeams.all where !passthrough.contains(team.id) {
            XCTAssertEqual(team.lead.preferredModelId, "model_opus", "\(team.id) lead should prefer Opus")
        }
    }

    func testImplementationSourceChoicesDoNotAppearAsTeams() {
        for team in BuiltInTeams.all {
            XCTAssertFalse(team.displayName.lowercased().contains("implementation"))
            XCTAssertFalse(team.id.contains("_implementation"))
        }
    }

    func testEveryReferencedSkillExistsInCatalog() {
        for team in BuiltInTeams.all {
            for row in team.workerSpecs {
                XCTAssertNotNil(SkillCatalog.skill(row.skillId),
                                "team \(team.id) references unknown skill \(row.skillId)")
            }
            XCTAssertNotNil(SkillCatalog.skill(team.lead.skillId),
                            "team \(team.id) references unknown Team Lead skill \(team.lead.skillId)")
        }
    }

    func testExactlyOneDefaultPerLane() {
        XCTAssertTrue(BuiltInTeams.all.lanesViolatingSingleDefault().isEmpty)
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .code)?.id, "code_core")
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .design)?.id, "design_core")
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .copy)?.id, "copy_core")
    }

    func testEveryTeamLaneMatchesIdPrefixAndSkillLane() {
        let globalRunTeams: Set<String> = ["default_chat", "execution_playbook"]
        for team in BuiltInTeams.all {
            if !globalRunTeams.contains(team.id) {
                XCTAssertTrue(team.id.hasPrefix(team.lane.rawValue), "\(team.id) prefix != lane")
            }
            // Answer/review rows should be skills tagged for the team's lane.
            for row in team.workerSpecs {
                let skill = SkillCatalog.skill(row.skillId)
                XCTAssertEqual(skill?.lane, team.lane,
                              "skill \(row.skillId) lane \(skill?.lane.rawValue ?? "?") != team lane \(team.lane.rawValue) in \(team.id)")
            }
        }
    }

    func testCopyLandingPageCarriesTypeTag() {
        XCTAssertEqual(BuiltInTeams.team("copy_landing_page")?.typeTags, ["landing-page"])
    }

    // MARK: - Headline proof: one ready CLI runs Bug Hunter Forensics High

    func testBugHuntForensicsHighWithOnlyOpusResolvesEightWorkersPlusWriter() {
        let team = BuiltInTeams.team("code_bug_hunt")!
        XCTAssertEqual(team.displayName, "Bug Hunter Forensics")
        XCTAssertEqual(team.defaultEffort, .high)
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .high, readyModels: [opus()])

        XCTAssertTrue(r.isRunnable)
        XCTAssertNil(r.blockReason)

        // Exactly eight answer/review workers, the expected distinct skills.
        let answerReview = r.answerWorkers + r.reviewWorkers
        XCTAssertEqual(answerReview.count, 8)
        XCTAssertEqual(Set(answerReview.map { $0.skillId ?? "" }), [
            "bug_reproducer", "truth_owner_mapper", "correct_fix_planner", "regression_guard",
            "trace_mapper", "state_skeptic",
            "contrarian_root_cause", "fix_altitude_reviewer"
        ])

        // One synthetic plan/output worker, bug_packet_writer.
        XCTAssertEqual(r.planWriter?.skillId, "bug_packet_writer")
        XCTAssertEqual(r.planWriter?.purpose, .plan)

        // All workers on Opus; distinct skill ids; distinct instance indices.
        XCTAssertTrue(r.allWorkers.allSatisfy { $0.modelId == "model_opus" })
        XCTAssertEqual(Set(r.allWorkers.map(\.id)).count, 9)
        XCTAssertEqual(Set(r.allWorkers.map(\.instanceIndex)).count, 9)

        // Honest one-model + admission warnings; never "not enough models".
        XCTAssertTrue(r.warnings.contains { $0.contains("Only one ready model") })
        XCTAssertTrue(r.warnings.contains { $0.lowercased().contains("queue") })
        XCTAssertFalse(r.warnings.contains { $0.lowercased().contains("not enough") })
    }


    func testGUIBugHuntCarriesRenderedProofSkills() {
        let team = BuiltInTeams.team("code_gui_bug_hunt")!
        XCTAssertEqual(team.displayName, "GUI Bug Hunt")
        XCTAssertEqual(team.outputKind, .bugPacket)
        XCTAssertEqual(team.defaultEffort, .high)

        let high = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .high, readyModels: [opus()])
        XCTAssertTrue(high.isRunnable)
        XCTAssertEqual(high.planWriter?.skillId, "gui_bug_packet_writer")
        XCTAssertTrue(high.answerWorkers.contains { $0.skillId == "gui_proof_guard" })
        XCTAssertTrue(high.reviewWorkers.contains { $0.skillId == "gui_layout_reviewer" })
    }

    // MARK: - Works Test E: preferred Codex unavailable falls back deterministically

    func testRegressionGuardFallsBackWhenPreferredUnavailable() {
        let team = BuiltInTeams.team("code_bug_hunt")!
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        let regression = r.answerWorkers.first { $0.skillId == "regression_guard" }
        XCTAssertEqual(regression?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("preferred model_cursor_composer_25 unavailable") })
    }

    // MARK: - Built-in immutability via duplicate-to-customize

    func testDuplicateLeavesBuiltInUnchanged() {
        let original = BuiltInTeams.team("code_bug_hunt")!
        let custom = original.duplicated(newId: "mike_bug_hunt", newName: "Mike's Bug Hunt")
        XCTAssertEqual(custom.id, "mike_bug_hunt")
        XCTAssertEqual(custom.displayName, "Mike's Bug Hunt")
        XCTAssertFalse(custom.builtIn)
        XCTAssertFalse(custom.isDefaultForLane)
        // The built-in is untouched.
        XCTAssertEqual(BuiltInTeams.team("code_bug_hunt")?.displayName, "Bug Hunter Forensics")
        XCTAssertTrue(BuiltInTeams.team("code_bug_hunt")?.builtIn ?? false)
    }
}
