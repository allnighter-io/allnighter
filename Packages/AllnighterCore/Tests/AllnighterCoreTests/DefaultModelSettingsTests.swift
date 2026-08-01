import XCTest
@testable import AllnighterCore

final class DefaultModelSettingsTests: XCTestCase {

    // MARK: - Fresh install + seed

    func testFreshInstallIsAutoOnFrontierWithSubstitutionsOn() {
        let s = DefaultModelSettings.fresh
        XCTAssertEqual(s.defaultTier, .frontier)
        XCTAssertTrue(s.allowHealthySubstitutions)
        XCTAssertEqual(s.tierDefault(.frontier), "model_fable")
        // Frontier: Fable + Codex Sol + Kimi K3. Cursor Sol is never seeded.
        XCTAssertEqual(s.tiers.frontier, ["model_fable", "model_gpt_sol", "model_kimi_k3"])
        XCTAssertFalse(s.tiers.frontier.contains("model_cursor_gpt_sol"))
        XCTAssertEqual(s.tiers.balanced, [
            "model_gpt_terra", "model_opus", "model_agy_opus", "model_cursor_grok_45",
            "model_grok", "model_sonnet", "model_cursor_composer_25", "model_gemini"
        ])
        XCTAssertEqual(s.tiers.economy, [
            "model_gpt_luna", "model_agy_sonnet", "model_kimi_k27", "model_cursor_composer_25",
            "model_cursor_auto", "model_gemini"
        ])
        for fastId in ["model_cursor_composer_25_fast", "model_grok_composer_25_fast"] {
            XCTAssertTrue(s.tiers.isUnassigned(fastId), "\(fastId) must stay unassigned in fresh seed")
        }
    }

    func testPickerSectionsListsBenchModelsInEveryAssignedTier() {
        let bench = [
            "model_fable", "model_gpt_sol", "model_gemini", "model_cursor_composer_25",
            "model_kimi_k27", "model_cursor_gpt_sol", "model_grok_composer_25_fast",
        ]
        let sections = DefaultModelSettings.fresh.tiers.pickerSections(orderedBench: bench)
        XCTAssertEqual(sections.map(\.title), ["Frontier", "Balanced", "Economy", "Unassigned"])
        XCTAssertEqual(sections[0].modelIds, ["model_fable", "model_gpt_sol"])
        XCTAssertEqual(sections[1].modelIds, ["model_cursor_composer_25", "model_gemini"])
        XCTAssertEqual(sections[2].modelIds, ["model_kimi_k27", "model_cursor_composer_25", "model_gemini"])
        XCTAssertEqual(sections[3].modelIds, ["model_cursor_gpt_sol", "model_grok_composer_25_fast"])
    }

    func testMergingMissingFreshTierMembersIsAdditive() {
        var saved = DefaultModelSettings.fresh
        saved.tiers.economy = saved.tiers.economy.filter { $0 != "model_agy_sonnet" }
        let merged = saved.mergingMissingFreshTierMembers()
        XCTAssertTrue(merged.tiers.economy.contains("model_agy_sonnet"))
        XCTAssertEqual(merged.tiers.frontier, saved.tiers.frontier)
        XCTAssertFalse(merged.tiers.balanced.contains("model_agy_sonnet"))
    }

    func testPickerModelIdsOmitsCollapsedUnassigned() {
        let bench = ["model_fable", "model_grok_composer_25_fast"]
        let flat = DefaultModelSettings.fresh.tiers.pickerModelIds(orderedBench: bench, includeUnassigned: false)
        XCTAssertEqual(flat, ["model_fable"])
    }

    func testAutoPrefersFableOverCodexSolWhenBothReady() {
        let r = SubstitutionResolver.resolveAuto(
            settings: .fresh,
            readyModelIds: ["model_fable", "model_gpt_sol"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertFalse(r.substituted)
    }

    func testAutoFallsBackToCodexSolWhenFableUnavailable() {
        let r = SubstitutionResolver.resolveAuto(
            settings: .fresh,
            readyModelIds: ["model_gpt_sol"])
        XCTAssertEqual(r.resolvedModelId, "model_gpt_sol")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .frontier)
    }

    func testRequestedFableFallsBackToCodexSol() {
        let r = SubstitutionResolver.resolveRequested(
            modelId: "model_fable",
            settings: .fresh,
            readyModelIds: ["model_gpt_sol"])
        XCTAssertEqual(r.resolvedModelId, "model_gpt_sol")
        XCTAssertTrue(r.substituted)
    }

    func testRequestedMediumModelFallsBackToCodexTerra() {
        let r = SubstitutionResolver.resolveRequested(
            modelId: "model_opus",
            settings: .fresh,
            readyModelIds: ["model_gpt_terra"])
        XCTAssertEqual(r.resolvedModelId, "model_gpt_terra")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .balanced)
    }

    func testRoundTripCodable() throws {
        let s = DefaultModelSettings.fresh
        let data = try CoreJSON.encode(s)
        let back = try CoreJSON.decode(DefaultModelSettings.self, from: data)
        XCTAssertEqual(back, s)
        // Tier membership encodes as a keyed object, not an array of pairs.
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"frontier\""))
    }

    // MARK: - Many-to-many membership

    func testModelCanBelongToMultipleTiers() {
        let s = DefaultModelSettings.fresh
        // K3 is Frontier-only; medium Terra is in Balanced; Gemini spans Balanced + Economy;
        // GPT-5.6 Luna is the Economy-tier default; Antigravity Sonnet 4.6 and K2.7 are Economy-only.
        XCTAssertEqual(s.tiers.tiers(of: "model_gpt_sol"), [.frontier])
        XCTAssertEqual(s.tiers.tiers(of: "model_kimi_k3"), [.frontier])
        XCTAssertEqual(s.tiers.highestTier(of: "model_kimi_k3"), .frontier)
        XCTAssertEqual(s.tiers.tiers(of: "model_gpt_terra"), [.balanced])
        XCTAssertEqual(s.tiers.tiers(of: "model_gemini"), [.balanced, .economy])
        XCTAssertEqual(s.tiers.tiers(of: "model_gpt_luna"), [.economy])
        XCTAssertEqual(s.tiers.tiers(of: "model_agy_sonnet"), [.economy])
        XCTAssertEqual(s.tiers.tiers(of: "model_kimi_k27"), [.economy])
        XCTAssertEqual(s.tierDefault(.economy), "model_gpt_luna")
        XCTAssertEqual(s.tiers.tiers(of: "model_agy_opus"), [.balanced])
        XCTAssertTrue(s.tiers.isUnassigned("model_grok_composer_25_fast"))
        XCTAssertTrue(s.tiers.isUnassigned("model_cursor_composer_25_fast"))
        XCTAssertEqual(s.tiers.tiers(of: "model_cursor_composer_25"), [.balanced, .economy])
        XCTAssertTrue(s.tiers.isUnassigned("model_cursor_gpt_sol"))
    }

    func testNormalizePreservesCrossTierAndDedupesWithinTier() {
        // `a` is intentionally in two tiers (preserved); the second `a` *within*
        // Frontier is the only true duplicate.
        let m = TierMembership(frontier: ["a", "b", "a"], balanced: ["a", "c"], economy: ["c"])
        let (clean, dups) = m.normalized()
        XCTAssertEqual(clean.frontier, ["a", "b"], "intra-tier dup removed")
        XCTAssertEqual(clean.balanced, ["a", "c"], "cross-tier `a` preserved")
        XCTAssertEqual(clean.economy, ["c"], "cross-tier `c` preserved")
        XCTAssertEqual(dups, ["a"], "only the within-Frontier dup is reported")
    }

    // MARK: - Auto resolution + the toggle-gates-Auto rule

    func testAutoSubstitutionsOnPicksFirstReadyInTier() {
        let s = DefaultModelSettings.fresh   // Frontier: fable, chatgpt
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_gpt_sol"])
        XCTAssertEqual(r.resolvedModelId, "model_gpt_sol")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .frontier)
    }

    func testAutoSubstitutionsOnDefaultReadyIsNotASubstitution() {
        let r = SubstitutionResolver.resolveAuto(settings: .fresh, readyModelIds: ["model_fable", "model_gpt_sol"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertFalse(r.substituted)
    }

    func testAutoSubstitutionsOffUsesTierDefaultOnly_waitsWhenDown() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        // Fable (the default) down, Codex Sol ready — with substitutions OFF Auto must WAIT.
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_gpt_sol"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testAutoSubstitutionsOffRunsDefaultWhenReady() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_fable"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
    }

    func testAutoBlocksWhenWholeTierDown() {
        // Only Sonnet (Balanced) ready → Frontier Auto must not downgrade.
        let r = SubstitutionResolver.resolveAuto(settings: .fresh, readyModelIds: ["model_sonnet"])
        XCTAssertNil(r.resolvedModelId, "no silent downgrade to Balanced")
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testAutoBlocksWhenTierEmpty() {
        var s = DefaultModelSettings.fresh
        s.tiers.frontier = []
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_gpt_sol"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .tierEmpty)
    }

    func testAutoOnBalancedUsesAMultiTierMember() {
        var s = DefaultModelSettings.fresh
        s.defaultTier = .balanced
        // First Balanced member (chatgpt) down; next ready member wins.
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_opus"])
        XCTAssertEqual(r.resolvedModelId, "model_opus")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .balanced)
    }

    // MARK: - Requested-model substitution (per-chat pick / team worker)

    func testRequestedReadyRunsAsIs() {
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: .fresh, readyModelIds: ["model_fable"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertFalse(r.substituted)
    }

    func testRequestedDownSubstitutesWithinHighestTier() {
        // Fable down, Codex Sol ready, both Frontier → substitute to Codex Sol.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: .fresh, readyModelIds: ["model_gpt_sol"])
        XCTAssertEqual(r.resolvedModelId, "model_gpt_sol")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .frontier)
    }

    func testRequestedNeverDowngrades() {
        // Fable (Frontier) down; only Sonnet (Balanced) ready → no downgrade.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: .fresh, readyModelIds: ["model_sonnet"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testRequestedMultiTierModelSubstitutesWithinHighestTier() {
        // ChatGPT spans Frontier + Balanced. Down → substitute within Frontier
        // (highest), never the lower tier.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_gpt_sol", settings: .fresh, readyModelIds: ["model_fable", "model_sonnet"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertEqual(r.tier, .frontier)
    }

    func testRequestedUnassignedDownNeverSubstitutes() {
        // Cursor Sol is Unassigned in the seed; down → wait, never substitute.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_cursor_gpt_sol", settings: .fresh, readyModelIds: ["model_fable"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .unassigned)
    }

    func testRequestedDownSubstitutionsOffWaits() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: s, readyModelIds: ["model_gpt_sol"])
        XCTAssertNil(r.resolvedModelId)
    }

    // MARK: - Tier + bench parity

    func testAssignToTierEnablesOffBenchModel() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let settingsFile = dir.appendingPathComponent("default_model_settings.json")
        let rosterURL = dir.appendingPathComponent("model_roster.json")
        ModelCatalog.overrideRosterForTesting(fileURL: rosterURL)
        defer { ModelCatalog.resetTestingOverrides() }

        try ModelRosterPersistence(fileURL: rosterURL).save(
            ModelRosterState(enabledModelIds: ["model_opus"]))
        XCTAssertFalse(ModelCatalog.isEnabled("model_kimi_k27"))

        var settings = DefaultModelSettings.fresh
        settings.tiers.economy = settings.tiers.economy.filter { $0 != "model_kimi_k27" }
        let persistence = DefaultModelSettingsPersistence(fileURL: settingsFile)
        try persistence.save(settings)

        _ = try DefaultModelTierActions.assign("model_kimi_k27", to: .economy,
                                               settingsPersistence: persistence)

        XCTAssertTrue(ModelCatalog.isEnabled("model_kimi_k27"))
        XCTAssertTrue(persistence.load().tiers.economy.contains("model_kimi_k27"))
    }

    // MARK: - Persistence

    func testPersistenceRoundTripPreservesMultiTierAndDedupesWithinTier() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("default_model_settings.json")
        let p = DefaultModelSettingsPersistence(fileURL: file)

        // No file yet → fresh seed.
        XCTAssertEqual(p.load().defaultTier, .frontier)

        var s = DefaultModelSettings.fresh
        s.defaultTier = .balanced
        s.allowHealthySubstitutions = false
        s.tiers.frontier = ["model_opus", "model_gpt_sol", "model_opus"]  // intra-tier dup
        s.tiers.balanced = ["model_opus", "model_sonnet"]                  // model_opus also in Balanced
        try p.save(s)

        let loaded = p.load()
        XCTAssertEqual(loaded.defaultTier, .balanced)
        XCTAssertFalse(loaded.allowHealthySubstitutions)
        XCTAssertEqual(loaded.tiers.frontier, ["model_opus", "model_gpt_sol"], "intra-tier dup normalized away")
        XCTAssertEqual(loaded.tiers.balanced, ["model_opus", "model_sonnet"], "cross-tier membership preserved")
        XCTAssertNotNil(loaded.updatedAt)
    }

    func testCorruptFileIsBackedUpNotSilentlyDiscarded() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("default_model_settings.json")
        try Data("{ this is not valid json".utf8).write(to: file)

        let loaded = DefaultModelSettingsPersistence(fileURL: file).load()
        XCTAssertEqual(loaded.defaultTier, .frontier, "falls back to the seed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path),
                      "corrupt file preserved for recovery, not silently dropped")
    }

    func testLegacyTierKeysDecodeFromPersistedJSON() throws {
        let json = """
        {"schemaVersion":1,"defaultTier":"flagship","allowHealthySubstitutions":true,\
        "tiers":{"flagship":["model_fable"],"balanced":["model_opus"],"fast":["model_gemini"]}}
        """
        let decoded = try CoreJSON.decode(DefaultModelSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.defaultTier, .frontier)
        XCTAssertEqual(decoded.tiers.frontier, ["model_fable"])
        XCTAssertEqual(decoded.tiers.balanced, ["model_opus"])
        XCTAssertEqual(decoded.tiers.economy, ["model_gemini"])
    }

    func testResetRestoresFreshSeed() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = DefaultModelSettingsPersistence(fileURL: dir.appendingPathComponent("s.json"))
        var s = DefaultModelSettings.fresh
        s.defaultTier = .economy
        try p.save(s)
        let reset = try p.reset()
        XCTAssertEqual(reset.defaultTier, .frontier)
        XCTAssertEqual(reset.tiers.frontier, ["model_fable", "model_gpt_sol", "model_kimi_k3"])
    }
}
