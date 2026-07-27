import XCTest
@testable import AllnighterCore

final class DefaultModelSettingsTests: XCTestCase {

    // MARK: - Fresh install + seed

    func testFreshInstallIsAutoOnFlagshipWithSubstitutionsOn() {
        let s = DefaultModelSettings.fresh
        XCTAssertEqual(s.defaultTier, .flagship)
        XCTAssertTrue(s.allowHealthySubstitutions)
        XCTAssertEqual(s.tierDefault(.flagship), "model_fable")
        // Flagship: Fable + Codex Sol only. Cursor Sol is never seeded.
        XCTAssertEqual(s.tiers.flagship, ["model_fable", "model_chatgpt"])
        XCTAssertFalse(s.tiers.flagship.contains("model_chatgpt_sol"))
        XCTAssertEqual(s.tiers.balanced, [
            "model_chatgpt_terra", "model_opus", "model_cursor_grok_45", "model_kimi_k3",
            "model_kimi_k27", "model_grok", "model_sonnet", "model_cursor_composer_25", "model_gemini"
        ])
        XCTAssertEqual(s.tiers.fast, ["model_cursor_auto", "model_composer", "model_gemini"])
    }

    func testAutoPrefersFableOverCodexSolWhenBothReady() {
        let r = SubstitutionResolver.resolveAuto(
            settings: .fresh,
            readyModelIds: ["model_fable", "model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertFalse(r.substituted)
    }

    func testAutoFallsBackToCodexSolWhenFableUnavailable() {
        let r = SubstitutionResolver.resolveAuto(
            settings: .fresh,
            readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .flagship)
    }

    func testRequestedFableFallsBackToCodexSol() {
        let r = SubstitutionResolver.resolveRequested(
            modelId: "model_fable",
            settings: .fresh,
            readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
    }

    func testRequestedMediumModelFallsBackToCodexTerra() {
        let r = SubstitutionResolver.resolveRequested(
            modelId: "model_opus",
            settings: .fresh,
            readyModelIds: ["model_chatgpt_terra"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt_terra")
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
        XCTAssertTrue(json.contains("\"flagship\""))
    }

    // MARK: - Many-to-many membership

    func testModelCanBelongToMultipleTiers() {
        let s = DefaultModelSettings.fresh
        // Sol is Flagship-only; medium Terra is in Balanced; Gemini spans Balanced + Fast.
        XCTAssertEqual(s.tiers.tiers(of: "model_chatgpt"), [.flagship])
        XCTAssertEqual(s.tiers.highestTier(of: "model_chatgpt"), .flagship)
        XCTAssertEqual(s.tiers.tiers(of: "model_chatgpt_terra"), [.balanced])
        XCTAssertEqual(s.tiers.tiers(of: "model_gemini"), [.balanced, .fast])
        // Composer Fast is Fast-only in the seed; Composer 2.5 is Balanced-only.
        XCTAssertEqual(s.tiers.tiers(of: "model_composer"), [.fast])
        XCTAssertEqual(s.tiers.tiers(of: "model_cursor_composer_25"), [.balanced])
        XCTAssertTrue(s.tiers.isUnassigned("model_chatgpt_sol"))
    }

    func testNormalizePreservesCrossTierAndDedupesWithinTier() {
        // `a` is intentionally in two tiers (preserved); the second `a` *within*
        // Flagship is the only true duplicate.
        let m = TierMembership(flagship: ["a", "b", "a"], balanced: ["a", "c"], fast: ["c"])
        let (clean, dups) = m.normalized()
        XCTAssertEqual(clean.flagship, ["a", "b"], "intra-tier dup removed")
        XCTAssertEqual(clean.balanced, ["a", "c"], "cross-tier `a` preserved")
        XCTAssertEqual(clean.fast, ["c"], "cross-tier `c` preserved")
        XCTAssertEqual(dups, ["a"], "only the within-Flagship dup is reported")
    }

    // MARK: - Auto resolution + the toggle-gates-Auto rule

    func testAutoSubstitutionsOnPicksFirstReadyInTier() {
        let s = DefaultModelSettings.fresh   // Flagship: fable, chatgpt
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .flagship)
    }

    func testAutoSubstitutionsOnDefaultReadyIsNotASubstitution() {
        let r = SubstitutionResolver.resolveAuto(settings: .fresh, readyModelIds: ["model_fable", "model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertFalse(r.substituted)
    }

    func testAutoSubstitutionsOffUsesTierDefaultOnly_waitsWhenDown() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        // Fable (the default) down, Codex Sol ready — with substitutions OFF Auto must WAIT.
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_chatgpt"])
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
        // Only Sonnet (Balanced) ready → Flagship Auto must not downgrade.
        let r = SubstitutionResolver.resolveAuto(settings: .fresh, readyModelIds: ["model_sonnet"])
        XCTAssertNil(r.resolvedModelId, "no silent downgrade to Balanced")
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testAutoBlocksWhenTierEmpty() {
        var s = DefaultModelSettings.fresh
        s.tiers.flagship = []
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_chatgpt"])
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
        // Fable down, Codex Sol ready, both Flagship → substitute to Codex Sol.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: .fresh, readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .flagship)
    }

    func testRequestedNeverDowngrades() {
        // Fable (Flagship) down; only Sonnet (Balanced) ready → no downgrade.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: .fresh, readyModelIds: ["model_sonnet"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testRequestedMultiTierModelSubstitutesWithinHighestTier() {
        // ChatGPT spans Flagship + Balanced. Down → substitute within Flagship
        // (highest), never the lower tier.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_chatgpt", settings: .fresh, readyModelIds: ["model_fable", "model_sonnet"])
        XCTAssertEqual(r.resolvedModelId, "model_fable")
        XCTAssertEqual(r.tier, .flagship)
    }

    func testRequestedUnassignedDownNeverSubstitutes() {
        // Cursor Sol is Unassigned in the seed; down → wait, never substitute.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_chatgpt_sol", settings: .fresh, readyModelIds: ["model_fable"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .unassigned)
    }

    func testRequestedDownSubstitutionsOffWaits() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        let r = SubstitutionResolver.resolveRequested(modelId: "model_fable", settings: s, readyModelIds: ["model_chatgpt"])
        XCTAssertNil(r.resolvedModelId)
    }

    // MARK: - Persistence

    func testPersistenceRoundTripPreservesMultiTierAndDedupesWithinTier() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("default_model_settings.json")
        let p = DefaultModelSettingsPersistence(fileURL: file)

        // No file yet → fresh seed.
        XCTAssertEqual(p.load().defaultTier, .flagship)

        var s = DefaultModelSettings.fresh
        s.defaultTier = .balanced
        s.allowHealthySubstitutions = false
        s.tiers.flagship = ["model_opus", "model_chatgpt", "model_opus"]  // intra-tier dup
        s.tiers.balanced = ["model_opus", "model_sonnet"]                  // model_opus also in Balanced
        try p.save(s)

        let loaded = p.load()
        XCTAssertEqual(loaded.defaultTier, .balanced)
        XCTAssertFalse(loaded.allowHealthySubstitutions)
        XCTAssertEqual(loaded.tiers.flagship, ["model_opus", "model_chatgpt"], "intra-tier dup normalized away")
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
        XCTAssertEqual(loaded.defaultTier, .flagship, "falls back to the seed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path),
                      "corrupt file preserved for recovery, not silently dropped")
    }

    func testResetRestoresFreshSeed() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = DefaultModelSettingsPersistence(fileURL: dir.appendingPathComponent("s.json"))
        var s = DefaultModelSettings.fresh
        s.defaultTier = .fast
        try p.save(s)
        let reset = try p.reset()
        XCTAssertEqual(reset.defaultTier, .flagship)
        XCTAssertEqual(reset.tiers.flagship, ["model_fable", "model_chatgpt"])
    }
}
