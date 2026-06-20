import XCTest
@testable import AllnighterCore

final class DefaultModelSettingsTests: XCTestCase {

    // MARK: - Fresh install + seed

    func testFreshInstallIsAutoOnFlagshipWithSubstitutionsOn() {
        let s = DefaultModelSettings.fresh
        XCTAssertEqual(s.defaultTier, .flagship)
        XCTAssertTrue(s.allowHealthySubstitutions)
        XCTAssertEqual(s.tierDefault(.flagship), "model_opus")
        XCTAssertEqual(s.tiers.flagship, ["model_opus", "model_chatgpt"])
        XCTAssertEqual(s.tiers.balanced, ["model_sonnet"])
        XCTAssertEqual(s.tiers.fast, ["model_gemini"])
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

    // MARK: - Normalization (a model in at most one tier)

    func testNormalizeKeepsFirstTierAndReportsDuplicates() {
        let m = TierMembership(flagship: ["a", "b", "a"], balanced: ["b", "c"], fast: ["c"])
        let (clean, dups) = m.normalized()
        XCTAssertEqual(clean.flagship, ["a", "b"])
        XCTAssertEqual(clean.balanced, ["c"])
        XCTAssertEqual(clean.fast, [])
        XCTAssertEqual(Set(dups), ["a", "b", "c"])
    }

    func testTierOfAndUnassigned() {
        let s = DefaultModelSettings.fresh
        XCTAssertEqual(s.tiers.tier(of: "model_opus"), .flagship)
        XCTAssertEqual(s.tiers.tier(of: "model_sonnet"), .balanced)
        XCTAssertNil(s.tiers.tier(of: "model_grok"), "unassigned model has no tier")
    }

    // MARK: - Auto resolution + the toggle-gates-Auto rule

    func testAutoSubstitutionsOnPicksFirstReadyInTier() {
        let s = DefaultModelSettings.fresh   // Flagship: opus, chatgpt
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
        let r = SubstitutionResolver.resolveAuto(settings: .fresh, readyModelIds: ["model_sonnet"]) // only Balanced ready
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

    // MARK: - Requested-model substitution (per-chat pick / team worker)

    func testRequestedReadyRunsAsIs() {
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: .fresh, readyModelIds: ["model_opus"])
        XCTAssertEqual(r.resolvedModelId, "model_opus")
        XCTAssertFalse(r.substituted)
    }

    func testRequestedDownSubstitutesWithinSameTier() {
        // Opus down, ChatGPT ready, both Flagship → substitute to ChatGPT.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: .fresh, readyModelIds: ["model_chatgpt"])
        XCTAssertEqual(r.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(r.substituted)
        XCTAssertEqual(r.tier, .flagship)
    }

    func testRequestedNeverCrossesTier() {
        // Opus (Flagship) down; only Sonnet (Balanced) ready → no cross-tier substitution.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_opus", settings: .fresh, readyModelIds: ["model_sonnet"])
        XCTAssertNil(r.resolvedModelId)
        XCTAssertEqual(r.blockedReason, .shelfEmpty)
    }

    func testRequestedUnassignedDownNeverSubstitutes() {
        // model_grok is Unassigned in the seed; down → wait, never substitute.
        let r = SubstitutionResolver.resolveRequested(modelId: "model_grok", settings: .fresh, readyModelIds: ["model_opus"])
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

    func testPersistenceRoundTripAndFreshFallback() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("default_model_settings.json")
        let p = DefaultModelSettingsPersistence(fileURL: file)

        // No file yet → fresh seed.
        XCTAssertEqual(p.load().defaultTier, .flagship)

        var s = DefaultModelSettings.fresh
        s.defaultTier = .balanced
        s.allowHealthySubstitutions = false
        s.tiers.flagship = ["model_opus", "model_chatgpt", "model_opus"]  // dup to be normalized
        try p.save(s)

        let loaded = p.load()
        XCTAssertEqual(loaded.defaultTier, .balanced)
        XCTAssertFalse(loaded.allowHealthySubstitutions)
        XCTAssertEqual(loaded.tiers.flagship, ["model_opus", "model_chatgpt"], "duplicate normalized away")
        XCTAssertNotNil(loaded.updatedAt)
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
        XCTAssertEqual(reset.tiers.flagship, ["model_opus", "model_chatgpt"])
    }
}
