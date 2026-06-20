import XCTest
@testable import AllnighterCore

final class DefaultModelSettingsTests: XCTestCase {

    // MARK: - Fresh install + seed

    func testFreshInstallIsAutoOnFlagshipWithSubstitutionsOn() {
        let s = DefaultModelSettings.fresh
        XCTAssertEqual(s.defaultTier, .flagship)
        XCTAssertTrue(s.allowHealthySubstitutions)
        XCTAssertEqual(s.tierDefault(.flagship), "model_opus")
        XCTAssertEqual(s.tiers.flagship, ["model_opus", "model_chatgpt", "model_composer"])
        XCTAssertEqual(s.tiers.balanced, ["model_sonnet", "model_composer", "model_gemini"])
        XCTAssertEqual(s.tiers.fast, ["model_cursor_auto", "model_grok", "model_gemini"])
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
        // Composer (cheap, flagship-grade) is seeded into Flagship AND Balanced.
        XCTAssertEqual(s.tiers.tiers(of: "model_composer"), [.flagship, .balanced])
        XCTAssertEqual(s.tiers.highestTier(of: "model_composer"), .flagship)
        // Gemini Flash spans Balanced + Fast.
        XCTAssertEqual(s.tiers.tiers(of: "model_gemini"), [.balanced, .fast])
        // A model in zero tiers is Unassigned.
        XCTAssertTrue(s.tiers.isUnassigned("model_cursor_composer_25"))
        XCTAssertEqual(s.tiers.tiers(of: "model_cursor_composer_25"), [])
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
        let s = DefaultModelSettings.fresh   // Flagship: opus, chatgpt, composer
        // Opus down, ChatGPT ready → substitute to ChatGPT.
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .flagship)
    }

    func testAutoSubstitutionsOnDefaultReadyIsNotASubstitution() {
        let r = SubstitutionResolver.resolveAuto(settings: .fresh, readyModelIds: ["model_opus", "model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_opus")
        XCTAssertFalse(r.substituted)
    }

    func testAutoSubstitutionsOffUsesTierDefaultOnly_waitsWhenDown() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        // Opus (the default) down, ChatGPT ready — with substitutions OFF Auto must WAIT,
        // never slide to ChatGPT.
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_chatgpt"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testAutoSubstitutionsOffRunsDefaultWhenReady() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_opus"])
        XCTAssertEqual(r.resolvedModelId, "model_opus")
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
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_opus"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .tierEmpty)
    }

    func testAutoOnBalancedUsesAMultiTierMember() {
        var s = DefaultModelSettings.fresh
        s.defaultTier = .balanced            // Balanced: sonnet, composer, gemini
        // Sonnet down, Composer (also a Flagship member) ready → Balanced Auto uses it.
        let r = SubstitutionResolver.resolveAuto(settings: s, readyModelIds: ["model_composer"])
        XCTAssertEqual(r.resolvedModelId, "model_composer")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .balanced)
    }

    // MARK: - Requested-model substitution (per-chat pick / team worker)

    func testRequestedReadyRunsAsIs() {
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: .fresh, readyModelIds: ["model_opus"])
        XCTAssertEqual(r.resolvedModelId, "model_opus")
        XCTAssertFalse(r.substituted)
    }

    func testRequestedDownSubstitutesWithinHighestTier() {
        // Opus down, ChatGPT ready, both Flagship → substitute to ChatGPT.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: .fresh, readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .flagship)
    }

    func testRequestedNeverDowngrades() {
        // Opus (Flagship) down; only Sonnet (Balanced) ready → no downgrade.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: .fresh, readyModelIds: ["model_sonnet"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testRequestedMultiTierModelSubstitutesWithinHighestTier() {
        // Composer is in Flagship + Balanced. Down → substitute within Flagship
        // (highest), never the lower tier — so it lands on Opus, not a Balanced model.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_composer", settings: .fresh, readyModelIds: ["model_opus", "model_sonnet"])
        XCTAssertEqual(r.resolvedModelId, "model_opus")
        XCTAssertEqual(r.tier, .flagship)
    }

    func testRequestedUnassignedDownNeverSubstitutes() {
        // model_cursor_composer_25 is Unassigned in the seed; down → wait, never substitute.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_cursor_composer_25", settings: .fresh, readyModelIds: ["model_opus"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .unassigned)
    }

    func testRequestedDownSubstitutionsOffWaits() {
        var s = DefaultModelSettings.fresh
        s.allowHealthySubstitutions = false
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: s, readyModelIds: ["model_chatgpt"])
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
        XCTAssertEqual(reset.tiers.flagship, ["model_opus", "model_chatgpt", "model_composer"])
    }
}
