import XCTest
@testable import AllnighterCore

final class TeamResolverTests: XCTestCase {

    // Real built-in model ids so ModelCatalog capabilities apply.
    private func opus() -> Model { Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both) }
    private func codex() -> Model { Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .answerer) }
    private func gemini() -> Model { Model(id: "model_gemini", displayName: "Gemini", modelLabel: "g", driverId: "antigravity", role: .answerer) }

    private func leadSpec(_ skill: String = "plan_writer_build",
                          tags: [ModelCapabilityTag] = [.planner]) -> TeamLeadSpec {
        TeamLeadSpec(skillId: skill, requiredCapabilityTags: tags, fallbackPolicy: .strongestReady)
    }

    private func team(rows: [TeamWorkerSpec],
                      lane: WorkLane = .code,
                      lead: TeamLeadSpec? = nil) -> TeamPreset {
        TeamPreset(
            id: "code_test", displayName: "Test", lane: lane, outputKind: .plan,
            defaultEffort: .med, workerSpecs: rows,
            lead: lead ?? leadSpec()
        )
    }

    // MARK: - Self-fusion: one model fills many rows

    func testOneModelFillsManyRowsWithDistinctInstanceIndices() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "correct_fix_planner"),
            TeamWorkerSpec(id: "r3", skillId: "regression_guard")
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.allWorkers.map(\.modelId), Array(repeating: "model_opus", count: 4)) // 3 answer + writer
        XCTAssertEqual(r.allWorkers.map(\.id), ["model_opus#0", "model_opus#1", "model_opus#2", "model_opus#3"])
        XCTAssertEqual(Set(r.allWorkers.map(\.instanceIndex)).count, 4)
        XCTAssertEqual(r.planWriter?.purpose, .plan)
        XCTAssertTrue(r.warnings.contains { $0.contains("Only one ready model") })
    }

    // MARK: - Deterministic fallback when preferred is unavailable

    func testPreferredUnavailableFallsBackAndWarns() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
        ])
        // Codex preferred but down; another Codex seat ready → home-driver fill.
        let chatgpt54 = Model(id: "model_chatgpt_54", displayName: "ChatGPT 5.4",
                              modelLabel: "gpt-5.4", driverId: "codex", role: .answerer)
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low,
                                     readyModels: [opus(), chatgpt54])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_chatgpt_54")
        XCTAssertTrue(r.warnings.contains { $0.contains("preferred model_chatgpt unavailable") })
        XCTAssertEqual(r.answerWorkers.first?.substitutedFromModelId, "model_chatgpt")
        XCTAssertTrue(r.isRunnable)
    }

    func testPreferredUnavailableDoesNotCrossDriverWithoutOrderedFallback() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
        ])
        // Codex preferred/down; only Claude ready → seat blocks (no silent paid/cross-CLI swap).
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertTrue(r.answerWorkers.isEmpty)
    }

    func testCursorSolNeverAutoSeatsOnSpecReviewMinWhenCodexSolReady() {
        let ready: [Model] = [
            Model(id: "model_chatgpt", displayName: "ChatGPT 5.6 Sol", modelLabel: "gpt-5.6-sol",
                  driverId: "codex", role: .both),
            Model(id: "model_chatgpt_sol", displayName: "ChatGPT 5.6 Sol (Cursor)", modelLabel: "gpt-5.6-sol-high",
                  driverId: "cursor_agent", role: .both),
            Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus",
                  driverId: "claude_code", role: .both),
            Model(id: "model_kimi_k3", displayName: "Kimi K3", modelLabel: "kimi-code/k3",
                  driverId: "kimi", role: .both),
            Model(id: "model_grok", displayName: "Grok 4.5", modelLabel: "grok-4.5",
                  driverId: "grok", role: .answerer),
            Model(id: "model_gemini", displayName: "Gemini", modelLabel: "g",
                  driverId: "antigravity", role: .answerer),
        ]
        let team = BuiltInTeams.team("code_spec_review_min")!
        let r = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .med, readyModels: ready)
        XCTAssertTrue(r.isRunnable)
        let crewIds = Set((r.answerWorkers + r.reviewWorkers).map(\.modelId))
        XCTAssertFalse(crewIds.contains("model_chatgpt_sol"),
                       "Cursor Sol must never auto-seat on Spec Review Min")
        XCTAssertTrue(crewIds.contains("model_chatgpt") || r.planWriter?.modelId == "model_chatgpt",
                      "Codex Sol may seat as the default Sol route")
    }

    func testCursorSolStillResolvesWhenExplicitlyPreferred() {
        let cursorSol = Model(id: "model_chatgpt_sol", displayName: "ChatGPT 5.6 Sol (Cursor)",
                              modelLabel: "gpt-5.6-sol-high", driverId: "cursor_agent", role: .both)
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_chatgpt_sol",
                           allowedModelIds: ["model_chatgpt_sol"],
                           fallbackPolicy: .exactOnly)
        ], lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_chatgpt_sol",
                              fallbackPolicy: .exactOnly))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low,
                                     readyModels: [cursorSol])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_chatgpt_sol")
    }

    func testPreferredUsedWhenReady() {
        let t = team(
            rows: [
                TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                               preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
            ],
            lead: TeamLeadSpec(
                skillId: "plan_writer_build",
                preferredModelId: "model_opus",
                fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus(), codex()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_chatgpt")
        XCTAssertFalse(r.warnings.contains { $0.contains("preferred") })
        XCTAssertNil(r.answerWorkers.first?.substitutedFromModelId, "no substitution → no flag")
    }

    func testOrderedCrossSourceFallbackWinsBeforeGlobalRank() {
        let kimi = Model(id: "model_kimi_k3", displayName: "Kimi K3",
                         modelLabel: "kimi-code/k3", driverId: "kimi", role: .both)
        let t = team(rows: [
            TeamWorkerSpec(
                id: "r1",
                skillId: "regression_guard",
                preferredModelId: "model_chatgpt_sol",
                fallbackModelIds: ["model_kimi_k3", "model_opus"],
                fallbackPolicy: .strongestReady)
        ])
        let r = TeamResolver.resolve(
            team: t,
            requestLane: .code,
            requestEffort: .low,
            readyModels: [opus(), kimi])

        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_kimi_k3",
                       "declared cross-CLI order must beat global strength rank")
        XCTAssertEqual(r.answerWorkers.first?.substitutedFromModelId, "model_chatgpt_sol")
    }

    func testWorkersReserveResolvedFallbackLeadModel() {
        let kimi = Model(id: "model_kimi_k3", displayName: "Kimi K3",
                         modelLabel: "kimi-code/k3", driverId: "kimi", role: .both)
        let t = team(
            rows: [
                TeamWorkerSpec(
                    id: "r1",
                    skillId: "regression_guard",
                    preferredModelId: "missing",
                    fallbackModelIds: ["model_kimi_k3", "model_opus"])
            ],
            lead: TeamLeadSpec(
                skillId: "plan_writer_build",
                preferredModelId: "missing",
                fallbackModelIds: ["model_kimi_k3", "model_opus"]))
        let r = TeamResolver.resolve(
            team: t,
            requestLane: .code,
            requestEffort: .low,
            readyModels: [opus(), kimi])

        XCTAssertEqual(r.planWriter?.modelId, "model_kimi_k3")
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_opus",
                       "the model that actually resolved for Lead should be reserved")
    }

    // MARK: - Optional disable vs required block

    func testOptionalRowDisablesWithWarningButRuns() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "outlier_direction",
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: false)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.disabledRows.map(\.skillId), ["outlier_direction"])
        XCTAssertFalse(r.disabledRows[0].required)
        XCTAssertTrue(r.warnings.contains { $0.contains("Optional worker") && $0.contains("disabled") })
    }

    func testRequiredRowUnavailableBlocksTeam() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "visual_system_designer",
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: true)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertNotNil(r.blockReason)
        XCTAssertTrue(r.blockReason?.contains("required worker") ?? false)
    }

    // MARK: - Plan writer block

    func testPlanWriterUnavailableBlocksRun() {
        let t = team(
            rows: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer")],
            lead: leadSpec(tags: [.image]) // no ready model has .image
        )
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertEqual(r.blockReason, "plan/output writer could not resolve for Test")
        XCTAssertNil(r.planWriter)
    }

    // MARK: - Lane mismatch rejects before running

    func testLaneMismatchBlocks() {
        let t = team(rows: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer")])
        let r = TeamResolver.resolve(team: t, requestLane: .design, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertTrue(r.blockReason?.contains("is a code team") ?? false)
    }

    // MARK: - Image-capable model resolves the design row when ready

    private func sonnet(enabled: Bool = true) -> Model {
        Model(id: "model_sonnet", displayName: "Sonnet 4.6", modelLabel: "sonnet", driverId: "claude_code", role: .answerer, enabled: enabled)
    }

    func testDisabledPreferredFallsBackWithWarning() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_sonnet", fallbackPolicy: .anyReady)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("model_sonnet") })
    }

    func testExactOnlyBlocksWhenPreferredDisabled() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_sonnet", allowedModelIds: ["model_sonnet"],
                           fallbackPolicy: .exactOnly)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
    }

    func testExactOnlyDoesNotUseOrderedFallbackChain() {
        let t = team(rows: [
            TeamWorkerSpec(
                id: "r1",
                skillId: "regression_guard",
                preferredModelId: "model_sonnet",
                fallbackModelIds: ["model_opus"],
                fallbackPolicy: .exactOnly)
        ])
        let r = TeamResolver.resolve(
            team: t,
            requestLane: .code,
            requestEffort: .low,
            readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertTrue(r.answerWorkers.isEmpty)
    }

    func testImageRowResolvesWhenCapableModelReady() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "visual_system_designer",
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: true)
        ], lane: .design, lead: leadSpec("design_board_writer", tags: [.design]))
        let r = TeamResolver.resolve(team: t, requestLane: .design, requestEffort: .low, readyModels: [opus(), gemini()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_gemini")
        XCTAssertTrue(r.isRunnable)
    }

    func testWorkerRowsReserveLeadModelWhenAlternativesExist() {
        let composer = Model(id: "model_cursor_composer_25", displayName: "Composer 2.5", modelLabel: "composer-2.5",
                             driverId: "cursor_agent", role: .answerer)
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "correct_fix_planner"),
        ], lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus", fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low,
                                     readyModels: [opus(), codex(), composer])
        XCTAssertEqual(r.planWriter?.modelId, "model_opus")
        XCTAssertFalse(r.answerWorkers.contains { $0.modelId == "model_opus" })
    }

    func testCustomModelOnReadyDriverResolves() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: base.appendingPathComponent("models", isDirectory: true))
        ModelCatalog.overrideRosterForTesting(fileURL: base.appendingPathComponent("model_roster.json"))
        defer {
            CatalogRoots.resetTestingOverrides()
            ModelCatalog.resetTestingOverrides()
            try? FileManager.default.removeItem(at: base)
        }
        let registry = DriverRegistry([
            DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI)
        ])
        let custom = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        let customModel = ModelCatalog.resolvedModels(registry: registry).first { $0.id == custom.id }!
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: custom.id, fallbackPolicy: .exactOnly)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [customModel])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, custom.id)
    }

    // MARK: - CN-S06: preferred capability reorders within caliber, never filters

    private func mk(_ id: String) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: id, role: .both)
    }
    private func capsFn(_ map: [String: ModelCapabilities]) -> (String) -> ModelCapabilities {
        { map[$0] ?? ModelCapabilities() }
    }

    /// #1 Rich bench: a `.security`-tagged model and an untagged model of the SAME
    /// caliber (equal rank) → the tagged one takes the security seat first. The
    /// untagged model sorts FIRST by id ("m_gen" < "m_sec"), so a pass here proves
    /// the preference — not an id tie-break — decided the seat.
    func testPreferredCapabilityWinsWithinSameCaliber() {
        let caps = capsFn([
            "m_lead": ModelCapabilities(laneTags: [.code], capabilityTags: [.planner], strengthRank: 95),
            "m_gen":  ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 88),
            "m_sec":  ModelCapabilities(laneTags: [.code], capabilityTags: [.code, .security], strengthRank: 88),
        ])
        let t = team(
            rows: [TeamWorkerSpec(id: "sec_seat", skillId: "secrets_reviewer",
                                  preferredCapabilityTags: [.security], fallbackPolicy: .anyReady)],
            lead: TeamLeadSpec(skillId: "security_register_writer",
                               preferredModelId: "m_lead", fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .high,
                                     readyModels: [mk("m_lead"), mk("m_gen"), mk("m_sec")],
                                     capabilities: caps)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "m_sec")
    }

    /// Preference reorders across DIFFERENT ranks inside one caliber band
    /// (Law 3: "reorders candidates within caliber" — caliber is the
    /// Flagship/High/Mid band, not the exact rank): a rank-87 specialist takes
    /// the seat from a rank-92 generalist, both High band.
    func testPreferredCapabilityWinsAcrossRanksWithinBand() {
        let caps = capsFn([
            "m_lead": ModelCapabilities(laneTags: [.code], capabilityTags: [.planner], strengthRank: 99),
            "m_gen":  ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 92),
            "m_sec":  ModelCapabilities(laneTags: [.code], capabilityTags: [.code, .security], strengthRank: 87),
        ])
        let t = team(
            rows: [TeamWorkerSpec(id: "sec_seat", skillId: "secrets_reviewer",
                                  preferredCapabilityTags: [.security], fallbackPolicy: .anyReady)],
            lead: TeamLeadSpec(skillId: "security_register_writer",
                               preferredModelId: "m_lead", fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .high,
                                     readyModels: [mk("m_lead"), mk("m_gen"), mk("m_sec")],
                                     capabilities: caps)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "m_sec",
                       "same-band specialist should win the seat regardless of exact rank")
    }

    /// #3 A lower-caliber `.security` specialist does NOT displace a higher-caliber
    /// generalist — the caliber BAND dominates; preference reorders only inside a band.
    func testPreferredCapabilityNeverBeatsCaliber() {
        let caps = capsFn([
            "m_lead": ModelCapabilities(laneTags: [.code], capabilityTags: [.planner], strengthRank: 99),
            "m_gen":  ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 90),
            "m_sec":  ModelCapabilities(laneTags: [.code], capabilityTags: [.code, .security], strengthRank: 80),
        ])
        let t = team(
            rows: [TeamWorkerSpec(id: "sec_seat", skillId: "secrets_reviewer",
                                  preferredCapabilityTags: [.security], fallbackPolicy: .anyReady)],
            lead: TeamLeadSpec(skillId: "security_register_writer",
                               preferredModelId: "m_lead", fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .high,
                                     readyModels: [mk("m_lead"), mk("m_gen"), mk("m_sec")],
                                     capabilities: caps)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "m_gen",
                       "higher-caliber generalist must not be displaced by a lower-caliber specialist")
    }

    /// #2 Reduced bench with ZERO `.security`-ready models → Security Review
    /// staffing is IDENTICAL to a resolver run with the preferences stripped
    /// (proves the preference NEVER filters and NEVER reorders when no candidate
    /// carries the tag: same seats, same models, same order).
    func testPreferredCapabilityIsNoOpWhenNoSpecialistReady() {
        let caps = capsFn([
            "m_a": ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 92),
            "m_b": ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 88),
            "m_c": ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 85),
            "m_d": ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 82),
            "m_e": ModelCapabilities(laneTags: [.code], capabilityTags: [.code], strengthRank: 80),
        ])
        let bench = ["m_a", "m_b", "m_c", "m_d", "m_e"].map(mk)
        let secTeam = BuiltInTeams.buildSecurityReview
        XCTAssertTrue(secTeam.workerSpecs.allSatisfy { $0.preferredCapabilityTags == [.security] },
                      "precondition: the built-in Security Review rows declare a .security preference")
        var stripped = secTeam
        stripped.workerSpecs = secTeam.workerSpecs.map {
            var s = $0; s.preferredCapabilityTags = []; return s
        }
        let withPref = TeamResolver.resolve(team: secTeam, requestLane: .code, requestEffort: .high,
                                            readyModels: bench, capabilities: caps)
        let withoutPref = TeamResolver.resolve(team: stripped, requestLane: .code, requestEffort: .high,
                                               readyModels: bench, capabilities: caps)
        XCTAssertEqual(withPref.allWorkers.map(\.modelId), withoutPref.allWorkers.map(\.modelId),
                       "with no .security model ready, preference must not change staffing")
        XCTAssertEqual(withPref.allWorkers.map(\.id), withoutPref.allWorkers.map(\.id))
    }

    /// #4 Round-trip decode: a TeamWorkerSpec JSON persisted before the new field
    /// existed decodes with an empty `preferredCapabilityTags` (decode-tolerant).
    func testDecodeToleratesMissingPreferredCapabilityTags() throws {
        let spec = TeamWorkerSpec(id: "r1", skillId: "secrets_reviewer",
                                  requiredCapabilityTags: [.code])
        let data = try JSONEncoder().encode(spec)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "preferredCapabilityTags") // simulate old persisted JSON
        XCTAssertNil(obj["preferredCapabilityTags"])
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(TeamWorkerSpec.self, from: legacy)
        XCTAssertEqual(decoded.preferredCapabilityTags, [])
        XCTAssertEqual(decoded.skillId, "secrets_reviewer")
        XCTAssertEqual(decoded.requiredCapabilityTags, [.code])
    }

    // MARK: - Seating Law (SEAT-S2) — FULL-bench Works Tests

    /// FULL = enabled auto built-ins + fixture Haiku. `poisonedCaps` mirrors the
    /// Bug A disk record (Fable@100); pass `useUnratedReadPath: true` for W1/W3
    /// (S1 floors customs to rank 40). W2 injects the poisoned rank into the
    /// pre-fix comparator only.
    private func fullBenchWithHaikuFixture(
        useUnratedReadPath: Bool
    ) -> (ready: [Model], haikuId: String, caps: (String) -> ModelCapabilities) {
        let haikuId = "fixture_custom_haiku"
        let haiku = Model(
            id: haikuId, displayName: "Claude Haiku (fixture)", modelLabel: "claude-haiku",
            driverId: "claude_code", role: .answerer, enabled: true)
        let ready = ModelCatalog.defaultFreshModels()
            .filter { $0.enabled && ModelCatalog.allowsAutomaticSubstitution($0.id) }
            + [haiku]
        let poisoned = ModelCatalog.builtInCapabilities["model_fable"]!
        var unrated = poisoned
        unrated.strengthRank = ModelCatalog.unratedModelRank
        let caps: (String) -> ModelCapabilities = { id in
            if id == haikuId {
                return useUnratedReadPath ? unrated : poisoned
            }
            return ModelCatalog.capabilities(id)
        }
        return (ready, haikuId, caps)
    }

    /// Pre-SEAT-S2 strongest: band → preferred → rank → family → id (family under rank).
    /// Old exclusion: shrink pool whenever any tagged auto alternative remains.
    private func preFixStrongest(
        pool: [Model],
        caps: (String) -> ModelCapabilities,
        requiredTags: [ModelCapabilityTag],
        preferredTags: [ModelCapabilityTag],
        avoidFamilies: Set<String>,
        exclude: Set<String>
    ) -> Model? {
        func hasTags(_ m: Model) -> Bool {
            let tags = caps(m.id).capabilityTags
            return requiredTags.allSatisfy { tags.contains($0) }
        }
        func hasPreferred(_ m: Model) -> Bool {
            let tags = caps(m.id).capabilityTags
            return preferredTags.allSatisfy { tags.contains($0) }
        }
        func autoOK(_ m: Model) -> Bool { ModelCatalog.allowsAutomaticSubstitution(m.id) }
        func band(_ m: Model) -> Int { ModelCatalog.caliberBand(caps(m.id).strengthRank) }
        var work = pool
        let expanded = exclude.reduce(into: Set<String>()) { $0.formUnion(ModelCatalog.diversityExclusionIds(for: $1)) }
        if !expanded.isEmpty {
            let alt = work.filter { !expanded.contains($0.id) }
            if alt.contains(where: { hasTags($0) && autoOK($0) }) { work = alt }
        }
        return work.filter(hasTags).filter(autoOK).sorted { a, b in
            let ra = caps(a.id).strengthRank, rb = caps(b.id).strengthRank
            let ba = band(a), bb = band(b)
            if ba != bb { return ba > bb }
            let pa = hasPreferred(a), pb = hasPreferred(b)
            if pa != pb { return pa && !pb }
            if ra != rb { return ra > rb }
            let fa = ModelCatalog.modelFamily(a.id, driverId: a.driverId)
            let fb = ModelCatalog.modelFamily(b.id, driverId: b.driverId)
            let usedA = avoidFamilies.contains(fa), usedB = avoidFamilies.contains(fb)
            if usedA != usedB { return !usedA && usedB }
            return a.id < b.id
        }.first
    }

    /// W1 — Spec Review Min seats gpt / Cursor Grok / Kimi; Haiku absent (S1 floor + S2).
    func testW1SpecReviewMinFullBenchSeatsDiverseFamilies() {
        let (ready, haikuId, caps) = fullBenchWithHaikuFixture(useUnratedReadPath: true)
        let team = BuiltInTeams.team("code_spec_review_min")!
        let r = TeamResolver.resolve(
            team: team, requestLane: .code, requestEffort: .high,
            readyModels: ready, capabilities: caps)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.planWriter?.modelId, "model_fable")
        XCTAssertEqual(
            r.answerWorkers.map(\.modelId),
            ["model_chatgpt", "model_cursor_grok_45", "model_kimi_k3"])
        XCTAssertFalse(r.answerWorkers.map(\.modelId).contains(haikuId))
        let answerFamilies = Set(r.answerWorkers.map { w in
            ModelCatalog.modelFamily(w.modelId, driverId: ready.first { $0.id == w.modelId }?.driverId)
        })
        XCTAssertEqual(answerFamilies, Set(["gpt", "grok", "kimi"]))
        XCTAssertEqual(ModelCatalog.modelFamily("model_fable"), "claude")
    }

    /// W2 — Same FULL through pre-fix comparator (family under rank) seats Haiku#2.
    /// Evidence: DCE9AE48 (min) before the seating law landed.
    func testW2PreFixComparatorStillSeatsPoisonedHaiku() {
        let (ready, haikuId, caps) = fullBenchWithHaikuFixture(useUnratedReadPath: false)
        let leadId = "model_fable"
        var familyUsed: Set<String> = [ModelCatalog.modelFamily(leadId)]
        var exclude: Set<String> = []
        var pool = ready
        // Reserve lead when alternatives exist (mirrors resolve).
        if pool.contains(where: { $0.id != leadId }) {
            pool.removeAll { $0.id == leadId }
        }
        var answers: [String] = []
        for _ in 0..<3 {
            guard let pick = preFixStrongest(
                pool: pool, caps: caps, requiredTags: [.code], preferredTags: [],
                avoidFamilies: familyUsed, exclude: exclude
            ) else { break }
            answers.append(pick.id)
            familyUsed.insert(ModelCatalog.modelFamily(pick.id, driverId: pick.driverId))
            exclude.formUnion(ModelCatalog.diversityExclusionIds(for: pick.id))
        }
        XCTAssertEqual([leadId] + answers, [leadId, haikuId, "model_chatgpt", "model_opus"],
                       "Pre-fix sort (DCE9AE48) seats Flagship Haiku before diversity mattered")
    }

    /// W3 — Spec Review Max: Haiku absent; scout Grok; ≥4 families; no strict majority.
    func testW3SpecReviewMaxFullBenchFamilySpread() {
        let (ready, haikuId, caps) = fullBenchWithHaikuFixture(useUnratedReadPath: true)
        let team = BuiltInTeams.team("code_spec_review_max")!
        let r = TeamResolver.resolve(
            team: team, requestLane: .code, requestEffort: .high,
            readyModels: ready, capabilities: caps)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.scoutWorker?.modelId, "model_grok")
        let crew = (r.answerWorkers + r.reviewWorkers + (r.planWriter.map { [$0] } ?? []))
        XCTAssertFalse(crew.map(\.modelId).contains(haikuId))
        let families = crew.map { worker in
            ModelCatalog.modelFamily(
                worker.modelId,
                driverId: ready.first { $0.id == worker.modelId }?.driverId)
        }
        let counts = Dictionary(grouping: families, by: { $0 }).mapValues(\.count)
        XCTAssertGreaterThanOrEqual(Set(families).count, 4)
        let majorityThreshold = families.count / 2 + 1
        XCTAssertFalse(counts.values.contains { $0 >= majorityThreshold },
                       "no single family holds a strict majority: \(counts)")
    }

    /// W5 — Single-model bench still runs.
    func testW5SingleModelBenchRemainsRunnable() {
        let fable = Model(id: "model_fable", displayName: "Fable 5", modelLabel: "fable",
                          driverId: "claude_code", role: .both)
        let team = BuiltInTeams.team("code_spec_review_min")!
        let r = TeamResolver.resolve(
            team: team, requestLane: .code, requestEffort: .high, readyModels: [fable])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.planWriter?.modelId, "model_fable")
        XCTAssertFalse(r.answerWorkers.isEmpty)
    }

    /// W6 — Preferred on a used family still wins (diversity does not override).
    func testW6PreferredOverridesFamilyDiversity() {
        let ready: [Model] = [
            Model(id: "model_fable", displayName: "Fable", modelLabel: "fable",
                  driverId: "claude_code", role: .both),
            Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                  driverId: "claude_code", role: .both),
            Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
                  driverId: "codex", role: .both),
        ]
        let t = team(
            rows: [
                TeamWorkerSpec(id: "r1", skillId: "seat_a"), // claims chatgpt (unused family)
                TeamWorkerSpec(
                    id: "r2", skillId: "seat_b",
                    preferredModelId: "model_opus", fallbackPolicy: .anyReady),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_fable",
                               fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .med, readyModels: ready)
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first { $0.skillId == "seat_b" }?.modelId, "model_opus")
    }
}
