import XCTest
@testable import AllnighterCore

final class BuiltInTeamsTests: XCTestCase {

    private func fable() -> Model {
        Model(id: "model_fable", displayName: "Fable 5", modelLabel: "fable", driverId: "claude_code", role: .both)
    }

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    // MARK: - Catalog integrity

    func testRequiredBuiltInIdsArePresent() {
        let required = [
            "code_plan", "code_bug_hunt_min", "code_bug_hunt", "code_bug_hunt_max", "code_gui_bug_hunt", "code_security_review",
            "code_spec_review_min", "code_spec_review", "code_spec_review_max", "code_release_proof",
            "code_growth_min", "code_growth", "code_growth_max",
            "default_chat", "build_slice",
            "design_design_min", "design_design", "design_design_max", "design_polish",
            "design_usability_review",
            "copy_core", "copy_landing",
            "signal_outside", "signal_what_to_build_next"
        ]
        for id in required {
            XCTAssertNotNil(BuiltInTeams.team(id), "missing built-in team \(id)")
            XCTAssertTrue(BuiltInTeams.team(id)?.builtIn ?? false)
        }
        XCTAssertEqual(BuiltInTeams.all.count, required.count)
    }

    func testSpecReviewDepthFamilyCarriesCuratedLineups() {
        let min = BuiltInTeams.team("code_spec_review_min")!
        let standard = BuiltInTeams.team("code_spec_review")!
        let max = BuiltInTeams.team("code_spec_review_max")!

        XCTAssertEqual([min.displayName, standard.displayName, max.displayName],
                       ["Spec Review Min", "Spec Review", "Spec Review Max"])
        for team in [min, standard, max] {
            XCTAssertEqual(team.outputKind, .specReview)
            XCTAssertEqual(team.defaultEffort, .high)
            XCTAssertEqual(team.lead.skillId, "spec_review_writer")
            XCTAssertEqual(team.lead.preferredModelId, "model_fable")
        }
        XCTAssertEqual(min.agentSpecs.map(\.skillId), [
            "spec_first_principles_reviewer", "spec_proof_planner", "spec_scope_steward"
        ])
        XCTAssertEqual(standard.agentSpecs.map(\.skillId), [
            "spec_first_principles_reviewer", "spec_doc_hygiene_reviewer",
            "spec_contract_auditor", "spec_proof_planner", "spec_contrarian_reviewer"
        ])
        XCTAssertEqual(max.agentSpecs.map(\.skillId), [
            "spec_first_principles_reviewer", "spec_doc_hygiene_reviewer",
            "spec_contract_auditor", "spec_proof_planner", "spec_scope_steward",
            "spec_hype_skeptic", "spec_contrarian_reviewer"
        ])
        XCTAssertNil(min.scout)
        XCTAssertNil(standard.scout)
        XCTAssertEqual(max.scout?.skillId, "spec_outside_scout")
        XCTAssertEqual(max.scout?.preferredModelId, "model_grok")

        // Law 3 (Team_Catalog_Normalization.md): no per-row hardcoded model
        // identity — rows express NEED (capability), and the shared resolver
        // fills them from the ready bench. "No exemptions" applies to Spec
        // Review too, so every row here is capability-only, not a curated
        // per-team model list.
        XCTAssertTrue([min, standard, max].flatMap(\.agentSpecs).allSatisfy {
            $0.preferredModelId == nil && $0.requiredCapabilityTags.contains(.code)
        })
    }

    func testSynthesisTeamsPreferFableLeadAndDiverseWorkersOnFullBench() {
        let ready: [Model] = [
            fable(),
            Model(id: "model_cursor_gpt_sol", displayName: "GPT-5.6 Sol", modelLabel: "gpt-5.6-sol-high",
                  driverId: "cursor_agent", role: .both),
            Model(id: "model_cursor_composer_25", displayName: "Composer 2.5", modelLabel: "composer-2.5",
                  driverId: "cursor_agent", role: .answerer),
            Model(id: "model_gpt_sol", displayName: "GPT-5.6", modelLabel: "gpt-5.6", driverId: "codex", role: .answerer),
            Model(id: "model_gemini", displayName: "Gemini 3.6 Flash", modelLabel: "g", driverId: "antigravity", role: .answerer),
            Model(id: "model_sonnet", displayName: "Sonnet 5", modelLabel: "claude-sonnet-5", driverId: "claude_code", role: .answerer),
            Model(id: "model_grok", displayName: "Grok 4.5", modelLabel: "grok-4.5", driverId: "grok", role: .answerer),
            Model(id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-code/k3", driverId: "kimi", role: .answerer),
            Model(id: "model_cursor_grok_45", displayName: "Cursor Grok 4.5", modelLabel: "cursor-grok-4.5-high",
                  driverId: "cursor_agent", role: .answerer),
        ]
        let team = BuiltInTeams.team("code_spec_review_max")!
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .high, readyModels: ready)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.planWriter?.modelId, "model_fable")
        XCTAssertEqual(r.scoutWorker?.modelId, "model_grok")
        let crew = r.answerWorkers + r.reviewWorkers
        // Law 3: no row pins Sol by identity. Codex Sol may be recruited once;
        // Cursor Sol is never an automatic substitute even if present on the bench.
        let cursorSolWorkers = crew.filter { $0.modelId == "model_cursor_gpt_sol" }
        XCTAssertEqual(cursorSolWorkers.count, 0, "Cursor Sol must never auto-seat")
        let codexSolWorkers = crew.filter { $0.modelId == "model_gpt_sol" }
        XCTAssertLessThanOrEqual(codexSolWorkers.count, 1, "Codex Sol at most once")
        XCTAssertGreaterThan(Set(crew.map(\.modelId)).count, 2, "fan-out should spread across multiple models")
        let composerHits = crew.filter { $0.modelId == "model_cursor_composer_25" }.count
        XCTAssertLessThanOrEqual(composerHits, 1, "Composer at most once in the rotation")
    }

    /// Law 3 (Team_Catalog_Normalization.md): the old "strategic seat" rows used
    /// to pin `model_cursor_gpt_sol` by identity — a per-team hardcoded model, the
    /// exact anti-pattern the law forbids. These same rows now carry no
    /// identity at all: they express capability, and declaration order (this
    /// row is first among its purpose group) gives them first pick of the
    /// strongest ready model instead — verified live on a rich bench by
    /// `testSynthesisTeamsPreferFableLeadAndDiverseWorkersOnFullBench`.
    func testTierOneTeamsCarryNoHardcodedWorkerIdentity() {
        let tierOne: [String: String] = [
            "code_plan": "first_principles_builder",
            "code_bug_hunt_max": "contrarian_root_cause",
            "code_gui_bug_hunt": "contrarian_root_cause",
            "code_security_review": "security_fix_prioritizer",
            "code_spec_review": "spec_first_principles_reviewer",
            "code_spec_review_max": "spec_first_principles_reviewer",
            "code_release_proof": "acceptance_auditor",
        ]
        for (teamId, skillId) in tierOne {
            let row = BuiltInTeams.team(teamId)?.agentSpecs.first { $0.skillId == skillId }
            XCTAssertNil(row?.preferredModelId, "\(teamId) worker \(skillId) should express need, not identity")
            XCTAssertEqual(row?.requiredCapabilityTags, [.code], "\(teamId) worker \(skillId)")
        }
    }

    func testEverySynthesisTeamReservesFableForLead() {
        let passthrough: Set<String> = ["default_chat", "build_slice"]
        for team in BuiltInTeams.all where !passthrough.contains(team.id) {
            XCTAssertEqual(team.lead.preferredModelId, "model_fable", "\(team.id) lead should prefer Fable")
        }
    }

    func testEverySynthesisLeadHasOrderedCrossCLIFallbacks() {
        // Codex Sol is the designated deputy lead; Cursor Sol is never in the
        // automatic chain (paid Cursor quota — manual opt-in only).
        let expected = [
            "model_gpt_sol", "model_opus", "model_kimi_k3",
            "model_cursor_grok_45", "model_grok",
            "model_cursor_composer_25", "model_sonnet", "model_gemini",
            "model_cursor_auto"
        ]
        let passthrough: Set<String> = ["default_chat", "build_slice"]
        for team in BuiltInTeams.all where !passthrough.contains(team.id) {
            XCTAssertEqual(team.lead.fallbackModelIds, expected, team.id)
        }
    }

    func testSpecReviewDepthFamilyRunsOnAlternativeCLIs() {
        let kimiAndGrok = [
            Model(id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-code/k3",
                  driverId: "kimi", role: .both),
            Model(id: "model_grok", displayName: "Grok 4.5", modelLabel: "grok-4.5",
                  driverId: "grok", role: .answerer)
        ]
        let cursorOnly = [
            Model(id: "model_cursor_grok_45", displayName: "Cursor Grok 4.5",
                  modelLabel: "cursor-grok-4.5-high", driverId: "cursor_agent", role: .answerer),
            Model(id: "model_cursor_composer_25", displayName: "Composer 2.5",
                  modelLabel: "composer-2.5", driverId: "cursor_agent", role: .answerer)
        ]

        let scenarios: [(name: String, models: [Model], expectedLead: String)] = [
            ("Kimi + Grok", kimiAndGrok, "model_kimi_k3"),
            ("Cursor only", cursorOnly, "model_cursor_grok_45")
        ]
        for scenario in scenarios {
            for id in ["code_spec_review_min", "code_spec_review", "code_spec_review_max"] {
                let result = TeamResolver.resolve(
                    team: BuiltInTeams.team(id)!,
                    requestLane: .code,
                    requestEffort: .high,
                    readyModels: scenario.models)
                XCTAssertTrue(
                    result.isRunnable,
                    "\(scenario.name) / \(id): \(result.blockReason ?? "unknown block")")
                XCTAssertEqual(result.planWriter?.modelId, scenario.expectedLead)
                XCTAssertTrue(result.allWorkers.allSatisfy { worker in
                    scenario.models.contains { $0.id == worker.modelId }
                })
                XCTAssertFalse(
                    result.answerWorkers.contains { $0.modelId == result.planWriter?.modelId },
                    "\(scenario.name) / \(id) should reserve the resolved Lead model")
            }
        }
    }

    func testNoBuiltInSeedPrefersRemovedAgyClaudeRoutes() {
        // Antigravity Claude Opus/Sonnet 4.6 are not shipped in the default catalog.
        let removed = Set(["model_agy_opus", "model_agy_sonnet"])
        for team in BuiltInTeams.all {
            XCTAssertFalse(removed.contains(team.lead.preferredModelId ?? ""), "\(team.id) lead")
            for row in team.agentSpecs {
                XCTAssertFalse(removed.contains(row.preferredModelId ?? ""),
                               "\(team.id) worker \(row.id)")
            }
            if let scout = team.scout {
                XCTAssertFalse(removed.contains(scout.preferredModelId ?? ""), "\(team.id) scout")
            }
            XCTAssertFalse(team.lead.fallbackModelIds?.contains(where: removed.contains) ?? false,
                           "\(team.id) lead fallbacks")
        }
    }

    func testLeadFallsBackStrongestWhenFableUnavailable() {
        let team = BuiltInTeams.team("code_plan")!
        let ready: [Model] = [
            Model(id: "model_gpt_sol", displayName: "GPT-5.6", modelLabel: "gpt-5.6",
                  driverId: "codex", role: .answerer),
            Model(id: "model_cursor_composer_25", displayName: "Composer 2.5",
                  modelLabel: "composer-2.5", driverId: "cursor_agent", role: .answerer),
        ]
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .med, readyModels: ready)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.planWriter?.modelId, "model_gpt_sol")
    }

    func testImplementationSourceChoicesDoNotAppearAsTeams() {
        for team in BuiltInTeams.all {
            XCTAssertFalse(team.displayName.lowercased().contains("implementation"))
            XCTAssertFalse(team.id.contains("_implementation"))
        }
    }

    func testEveryReferencedSkillExistsInCatalog() {
        for team in BuiltInTeams.all {
            for row in team.agentSpecs {
                XCTAssertNotNil(SkillCatalog.skill(row.skillId),
                                "team \(team.id) references unknown skill \(row.skillId)")
            }
            XCTAssertNotNil(SkillCatalog.skill(team.lead.skillId),
                            "team \(team.id) references unknown Team Lead skill \(team.lead.skillId)")
        }
    }

    func testExactlyOneDefaultPerLane() {
        XCTAssertTrue(BuiltInTeams.all.lanesViolatingSingleDefault().isEmpty)
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .code)?.id, "code_plan")
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .design)?.id, "design_design")
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .copy)?.id, "copy_core")
    }

    func testEveryTeamLaneMatchesIdPrefixAndSkillLane() {
        let globalRunTeams: Set<String> = ["default_chat", "build_slice"]
        for team in BuiltInTeams.all {
            if !globalRunTeams.contains(team.id) {
                XCTAssertTrue(team.id.hasPrefix(team.lane.rawValue), "\(team.id) prefix != lane")
            }
            // Answer/review rows should be skills tagged for the team's lane.
            for row in team.agentSpecs {
                let skill = SkillCatalog.skill(row.skillId)
                XCTAssertEqual(skill?.lane, team.lane,
                              "skill \(row.skillId) lane \(skill?.lane.rawValue ?? "?") != team lane \(team.lane.rawValue) in \(team.id)")
            }
        }
    }

    func testCopyLandingPageCarriesTypeTag() {
        // The "landing-page" routing key must remain (TeamRequestResolver --type);
        // additional intent typeTags may accompany it.
        XCTAssertEqual(BuiltInTeams.team("copy_landing")?.typeTags.contains("landing-page"), true)
    }

    func testTypeTagsUniqueWithinLane() {
        // --type resolution is first-match over declaration order, so a tag
        // duplicated within a lane routes by array position — e.g. a Min tier
        // carrying the family's generic tag steals the bare intent from Default.
        // Law 4 (Team_Catalog_Normalization.md): within a lane, every typeTag
        // maps to exactly one team; the family's generic tag lives on Default.
        for lane in WorkLane.allCases {
            var seen: [String: String] = [:]
            for team in BuiltInTeams.teams(in: lane) {
                for tag in team.typeTags {
                    if let holder = seen[tag] {
                        XCTFail("typeTag '\(tag)' in lane \(lane.rawValue) on both \(holder) and \(team.id)")
                    }
                    seen[tag] = team.id
                }
            }
        }
    }

    func testBareFamilyTypeTagsResolveToDefaultTier() {
        // The depth law: a bare family intent never auto-routes to Min/Max.
        XCTAssertEqual(BuiltInTeams.teams(in: .code).first { $0.typeTags.contains("spec-review") }?.id,
                       "code_spec_review")
        XCTAssertEqual(BuiltInTeams.teams(in: .code).first { $0.typeTags.contains("growth") }?.id,
                       "code_growth")
        XCTAssertEqual(BuiltInTeams.teams(in: .code).first { $0.typeTags.contains("bug") }?.id,
                       "code_bug_hunt")
    }

    // MARK: - CN-S04 catalog guards (Team_Catalog_Normalization.md)

    func testNoOrphanMinMaxTiers() {
        // Every `_min`/`_max` id must have its base family present, and the
        // base itself must not be a tier (no chained `_min_min`-style ids).
        for team in BuiltInTeams.all {
            for suffix in ["_min", "_max"] {
                guard team.id.hasSuffix(suffix) else { continue }
                let baseId = String(team.id.dropLast(suffix.count))
                XCTAssertNotNil(BuiltInTeams.team(baseId),
                                "\(team.id) is a tier with no base team '\(baseId)' in the catalog")
                XCTAssertFalse(baseId.hasSuffix("_min") || baseId.hasSuffix("_max"),
                               "\(team.id) base id '\(baseId)' must not itself be a tier")
            }
        }
    }

    func testTieredFamiliesCompleteMinDefaultMax() {
        // The four families that earn depth (Team_Catalog_Normalization.md
        // §The normalized catalog) must ship the full Min/Default/Max.
        let tieredFamilies = ["code_spec_review", "code_growth", "code_bug_hunt", "design_design"]
        for base in tieredFamilies {
            for id in [base, "\(base)_min", "\(base)_max"] {
                XCTAssertNotNil(BuiltInTeams.team(id), "tiered family \(base) is missing \(id)")
            }
        }
    }

    func testDepthTierDisplayNamesFollowMinMaxLawAndCarryNoRetiredNames() {
        // Law 2 / Product_Vocabulary depth naming: the only depth vocabulary is Min/Max,
        // appended verbatim to the base family's display name — never a
        // flavor depth name.
        for team in BuiltInTeams.all {
            for (suffix, label) in [("_min", " Min"), ("_max", " Max")] {
                guard team.id.hasSuffix(suffix) else { continue }
                let baseId = String(team.id.dropLast(suffix.count))
                guard let base = BuiltInTeams.team(baseId) else {
                    XCTFail("\(team.id) has no base team '\(baseId)' to compare display name against")
                    continue
                }
                XCTAssertEqual(team.displayName, base.displayName + label,
                               "\(team.id) displayName should be '\(base.displayName + label)', not a flavor depth name")
            }
        }

        // Retired internal/flavor names (Team_Catalog_Normalization.md Law 1)
        // must never resurface on any built-in team.
        let retiredNames = [
            "Code Core", "Execution Playbook", "Premium Polish", "Usability Triage",
            "Design Core", "Radical Directions", "Conversion Studio",
            "Post-to-Project Signal", "Landing Page Team"
        ]
        for team in BuiltInTeams.all {
            for retired in retiredNames {
                XCTAssertFalse(team.displayName.contains(retired),
                               "\(team.id) displayName '\(team.displayName)' still carries retired name '\(retired)'")
            }
        }
    }

    func testEveryBuiltInTeamMeetsMetadataFloor() {
        // Team_Catalog_Normalization.md §Metadata every family ships: non-empty
        // typeTags, ≥1 starter, and a non-empty description. `default_chat` and
        // `build_slice` are primitives, not families (§Not families — primitives
        // & defaults); `build_slice` deliberately ships empty starterPrompts
        // because RunService prepends `starterPrompts.first` for mutating teams
        // (see the doc comment on `executionPlaybook` — a starter here would
        // double-inject the playbook preamble), and `default_chat` is the plain
        // pass-everything-through chat default with no canned prompt to offer.
        let starterExempt: Set<String> = ["default_chat", "build_slice"]
        for team in BuiltInTeams.all {
            XCTAssertFalse(team.typeTags.isEmpty, "\(team.id) has no typeTags")
            XCTAssertFalse(team.description.isEmpty, "\(team.id) has no description")
            if !starterExempt.contains(team.id) {
                XCTAssertFalse(team.starterPrompts.isEmpty, "\(team.id) has no starterPrompts")
            }
        }
    }

    func testNoHardcodedWorkerIdentityOutsideSignalLane() {
        // Law 3: outside the signal lane (whose Grok-scout/interpreter
        // preferences are deliberate), a workerSpecs row expresses NEED
        // (capability), never a pinned model identity — the `scout` property
        // is a separate field and is exempt regardless of lane.
        // `default_chat` and `build_slice` are the two global execution
        // passthrough teams: mutating, `executionSourceId`-pinned to a single
        // CLI source (Cursor), not caliber/capability synthesis teams — so
        // their one worker row legitimately carries `preferredModelId:
        // composer`. Verified by inspection (BuiltInTeams.swift `defaultChat`/
        // `executionPlaybook`); reported here rather than forced or silently
        // "fixed" in the catalog, per CN-S04.
        let sourcePinnedExempt: Set<String> = ["default_chat", "build_slice"]
        for team in BuiltInTeams.all where team.lane != .signal {
            if sourcePinnedExempt.contains(team.id) { continue }
            for row in team.agentSpecs {
                XCTAssertNil(row.preferredModelId,
                             "\(team.id) worker \(row.id) hardcodes model identity '\(row.preferredModelId ?? "")' outside the signal lane (Law 3)")
            }
        }
    }

    // MARK: - CMR-S03 (Cross_Model_Review_Hardening.md): lead/worker caliber invariant

    /// No shipped preset may default a pinned worker to a higher caliber than its
    /// own Lead. Rows with no pinned `preferredModelId` (the overwhelming
    /// majority — Law 3) resolve dynamically via `TeamResolver`'s own
    /// band-aware logic, already proven never to let a lower-caliber model
    /// beat a higher one (`TeamResolverTests.testPreferredCapabilityNeverBeatsCaliber`);
    /// this test is scoped to the few rows that carry a pinned identity at
    /// declaration time (signal lane + the two source-pinned passthrough teams).
    func testLeadCaliberDominatesWorkers() {
        func rank(_ modelId: String) -> Int {
            ModelCatalog.builtInCapabilities[modelId]?.strengthRank ?? ModelCatalog.unratedModelRank
        }
        for team in BuiltInTeams.all {
            guard let leadId = team.lead.preferredModelId else { continue }
            let leadRank = rank(leadId)
            var pinnedModelIds = team.agentSpecs.compactMap(\.preferredModelId)
            if let scoutId = team.scout?.preferredModelId { pinnedModelIds.append(scoutId) }
            for modelId in pinnedModelIds {
                XCTAssertGreaterThanOrEqual(
                    leadRank, rank(modelId),
                    "\(team.id) lead \(leadId) (rank \(leadRank)) is lower caliber than pinned model \(modelId) (rank \(rank(modelId)))")
            }
        }
    }

    // MARK: - Headline proof: one ready CLI runs Bug Hunt Max High

    func testBugHuntMaxHighWithOnlyOpusResolvesEightWorkersPlusWriter() {
        let team = BuiltInTeams.team("code_bug_hunt_max")!
        XCTAssertEqual(team.displayName, "Bug Hunt Max")
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

    /// Law 3: `regression_guard` is a capability-only row (no pinned identity),
    /// so on a single-model bench it just resolves to whatever is ready — no
    /// "preferred unavailable" substitution to report, only the honest
    /// self-fusion warning every row on this bench shares.
    func testRegressionGuardResolvesOnSingleModelBench() {
        let team = BuiltInTeams.team("code_bug_hunt_max")!
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        let regression = r.answerWorkers.first { $0.skillId == "regression_guard" }
        XCTAssertEqual(regression?.modelId, "model_opus")
        XCTAssertNil(regression?.substitutedFromModelId)
        XCTAssertTrue(r.warnings.contains { $0.contains("Only one ready model") })
    }

    // MARK: - Built-in immutability via duplicate-to-customize

    func testDuplicateLeavesBuiltInUnchanged() {
        let original = BuiltInTeams.team("code_bug_hunt_max")!
        let custom = original.duplicated(newId: "mike_bug_hunt", newName: "Mike's Bug Hunt")
        XCTAssertEqual(custom.id, "mike_bug_hunt")
        XCTAssertEqual(custom.displayName, "Mike's Bug Hunt")
        XCTAssertFalse(custom.builtIn)
        XCTAssertFalse(custom.isDefaultForLane)
        // The built-in is untouched.
        XCTAssertEqual(BuiltInTeams.team("code_bug_hunt_max")?.displayName, "Bug Hunt Max")
        XCTAssertTrue(BuiltInTeams.team("code_bug_hunt_max")?.builtIn ?? false)
    }
}
