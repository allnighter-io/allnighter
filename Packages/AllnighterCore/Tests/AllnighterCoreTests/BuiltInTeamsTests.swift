import XCTest
@testable import AllnighterCore

final class BuiltInTeamsTests: XCTestCase {

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    // MARK: - Catalog integrity

    func testRequiredBuiltInIdsArePresent() {
        let required = [
            "build_core", "build_bug_hunt", "build_security_review",
            "build_architecture_pressure_test", "build_release_proof",
            "design_core", "design_premium_polish", "design_conversion_studio",
            "design_radical_directions", "design_usability_triage",
            "copy_core", "copy_landing_page"
        ]
        for id in required {
            XCTAssertNotNil(BuiltInTeams.team(id), "missing built-in team \(id)")
            XCTAssertTrue(BuiltInTeams.team(id)?.builtIn ?? false)
        }
        XCTAssertEqual(BuiltInTeams.all.count, required.count)
    }

    func testEveryReferencedSkillExistsInCatalog() {
        for team in BuiltInTeams.all {
            for row in team.workerSpecs {
                XCTAssertNotNil(SkillCatalog.skill(row.skillId),
                                "team \(team.id) references unknown skill \(row.skillId)")
            }
            for (_, policy) in team.synthesisPolicyByEffort {
                XCTAssertNotNil(SkillCatalog.skill(policy.planWriterSkillId),
                                "team \(team.id) references unknown writer \(policy.planWriterSkillId)")
            }
        }
    }

    func testExactlyOneDefaultPerLane() {
        XCTAssertTrue(BuiltInTeams.all.lanesViolatingSingleDefault().isEmpty)
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .build)?.id, "build_core")
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .design)?.id, "design_core")
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .copy)?.id, "copy_core")
    }

    func testEveryTeamLaneMatchesIdPrefixAndSkillLane() {
        for team in BuiltInTeams.all {
            XCTAssertTrue(team.id.hasPrefix(team.lane.rawValue), "\(team.id) prefix != lane")
            // Answer/review rows should be skills tagged for the team's lane.
            for row in team.workerSpecs {
                let skill = SkillCatalog.skill(row.skillId)
                XCTAssertTrue(skill?.laneTags.contains(team.lane) ?? false,
                              "skill \(row.skillId) not tagged for lane \(team.lane.rawValue) in \(team.id)")
            }
        }
    }

    func testCopyLandingPageCarriesTypeTag() {
        XCTAssertEqual(BuiltInTeams.team("copy_landing_page")?.typeTags, ["landing-page"])
    }

    // MARK: - Headline proof: one ready CLI runs Bug Hunt High

    func testBugHuntHighWithOnlyOpusResolvesSevenWorkersPlusWriter() {
        let team = BuiltInTeams.team("build_bug_hunt")!
        XCTAssertEqual(team.defaultEffort, .high)
        let r = TeamResolver.resolve(team: team, requestLane: .build, requestEffort: .high, readyModels: [opus()])

        XCTAssertTrue(r.isRunnable)
        XCTAssertNil(r.blockReason)

        // Exactly seven answer/review workers, the expected distinct skills.
        let answerReview = r.answerWorkers + r.reviewWorkers
        XCTAssertEqual(answerReview.count, 7)
        XCTAssertEqual(Set(answerReview.map { $0.skillId ?? "" }), [
            "bug_reproducer", "minimal_fixer", "regression_guard", "trace_mapper",
            "state_skeptic", "user_impact_narrator", "contrarian_root_cause"
        ])

        // One synthetic plan/output worker, bug_packet_writer.
        XCTAssertEqual(r.planWriter?.skillId, "bug_packet_writer")
        XCTAssertEqual(r.planWriter?.purpose, .plan)

        // All workers on Opus; distinct skill ids; distinct instance indices.
        XCTAssertTrue(r.allWorkers.allSatisfy { $0.modelId == "model_opus" })
        XCTAssertEqual(Set(r.allWorkers.map(\.id)).count, 8)
        XCTAssertEqual(Set(r.allWorkers.map(\.instanceIndex)).count, 8)

        // Honest one-model + admission warnings; never "not enough models".
        XCTAssertTrue(r.warnings.contains { $0.contains("Only one ready model") })
        XCTAssertTrue(r.warnings.contains { $0.lowercased().contains("queue") })
        XCTAssertFalse(r.warnings.contains { $0.lowercased().contains("not enough") })
    }

    func testEffortGatingChangesBugHuntWorkerCount() {
        let team = BuiltInTeams.team("build_bug_hunt")!
        let bench = [opus()]
        func answerReviewCount(_ e: EffortLevel) -> Int {
            let r = TeamResolver.resolve(team: team, requestLane: .build, requestEffort: e, readyModels: bench)
            return r.answerWorkers.count + r.reviewWorkers.count
        }
        XCTAssertEqual(answerReviewCount(.low), 3)
        XCTAssertEqual(answerReviewCount(.med), 5)
        XCTAssertEqual(answerReviewCount(.high), 7)
    }

    // MARK: - Works Test E: preferred Codex unavailable falls back deterministically

    func testRegressionGuardFallsBackFromCodexToOpus() {
        let team = BuiltInTeams.team("build_bug_hunt")!
        let r = TeamResolver.resolve(team: team, requestLane: .build, requestEffort: .low, readyModels: [opus()])
        let regression = r.answerWorkers.first { $0.skillId == "regression_guard" }
        XCTAssertEqual(regression?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("preferred model_chatgpt unavailable") })
    }

    // MARK: - Built-in immutability via duplicate-to-customize

    func testDuplicateLeavesBuiltInUnchanged() {
        let original = BuiltInTeams.team("build_bug_hunt")!
        let custom = original.duplicated(newId: "mike_bug_hunt", newName: "Mike's Bug Hunt")
        XCTAssertEqual(custom.id, "mike_bug_hunt")
        XCTAssertEqual(custom.displayName, "Mike's Bug Hunt")
        XCTAssertFalse(custom.builtIn)
        XCTAssertFalse(custom.isDefaultForLane)
        // The built-in is untouched.
        XCTAssertEqual(BuiltInTeams.team("build_bug_hunt")?.displayName, "Bug Hunt")
        XCTAssertTrue(BuiltInTeams.team("build_bug_hunt")?.builtIn ?? false)
    }
}
