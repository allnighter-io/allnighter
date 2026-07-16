import XCTest
@testable import AllnighterCore

final class DefaultSettingsProjectorTests: XCTestCase {

    private func entry(_ id: String, _ name: String, driver: String = "claude_code",
                       enabled: Bool = true, ready: Bool = true) -> ModelListJSON.Entry {
        ModelListJSON.Entry(
            id: id, displayName: name, modelLabel: name, driverId: driver, driverName: driver,
            role: "answerer", origin: "builtIn", enabled: enabled, ready: ready,
            status: ready ? "ready" : "notReady", state: enabled ? "onBench" : "available",
            capabilities: ModelCapabilities(laneTags: [], capabilityTags: [], strengthRank: 0))
    }

    /// Full catalog covering the fresh seed + one unassigned-on + one off-and-unassigned.
    private func catalog(ready: Set<String> = ["model_opus", "model_agy_opus", "model_chatgpt", "model_composer",
                                               "model_sonnet", "model_gemini", "model_cursor_auto",
                                               "model_grok", "model_extra"]) -> [ModelListJSON.Entry] {
        [
            entry("model_opus", "Opus 4.8", ready: ready.contains("model_opus")),
            entry("model_agy_opus", "Claude Opus 4.6", driver: "antigravity", ready: ready.contains("model_agy_opus")),
            entry("model_chatgpt", "ChatGPT 5.5", driver: "codex", ready: ready.contains("model_chatgpt")),
            entry("model_composer", "Grok Composer 2.5 Fast", driver: "grok", ready: ready.contains("model_composer")),
            entry("model_sonnet", "Sonnet 4.6", ready: ready.contains("model_sonnet")),
            entry("model_gemini", "Gemini 3.5 Flash", driver: "antigravity", ready: ready.contains("model_gemini")),
            entry("model_cursor_auto", "Cursor Auto", driver: "cursor", ready: ready.contains("model_cursor_auto")),
            entry("model_grok", "Grok Build", driver: "grok", ready: ready.contains("model_grok")),
            entry("model_extra", "Zed Helper", ready: ready.contains("model_extra")),          // on + unassigned
            entry("model_off", "Off Model", enabled: false, ready: false),                      // off + unassigned
        ]
    }

    func testProjectsTiersWithDefaultsAndMultiTierBadges() {
        let p = DefaultSettingsProjector.build(settings: .fresh, models: catalog(), contractVersion: "1.0.0")
        XCTAssertEqual(p.defaultTier, "flagship")
        XCTAssertTrue(p.allowHealthySubstitutions)
        XCTAssertEqual(p.tiers.map(\.tier), ["flagship", "balanced", "fast"])

        let flagship = p.tiers[0]
        XCTAssertTrue(flagship.isDefaultTier)
        XCTAssertEqual(flagship.members.map(\.id),
                       ["model_opus", "model_agy_opus", "model_chatgpt", "model_composer"])
        XCTAssertEqual(flagship.defaultModelId, "model_opus")
        XCTAssertTrue(flagship.members[0].isTierDefault)
        XCTAssertFalse(flagship.members[1].isTierDefault)
        XCTAssertEqual(flagship.substituteCount, 3)
        XCTAssertEqual(flagship.readyCount, 4)

        // Composer carries both its tiers as badges (many-to-many).
        let composer = flagship.members.first { $0.id == "model_composer" }
        XCTAssertEqual(composer?.tiers, ["flagship", "balanced"])
    }

    func testUnassignedIsOnModelsNotInAnyTierSortedAToZ() {
        let p = DefaultSettingsProjector.build(settings: .fresh, models: catalog(), contractVersion: "1.0.0")
        // Only model_extra: it's on and untiered. model_off is off → excluded.
        XCTAssertEqual(p.unassigned.map(\.id), ["model_extra"])
        XCTAssertFalse(p.unassigned.contains { $0.id == "model_off" })
    }

    func testAutoResolvesDefaultWhenReady() {
        let p = DefaultSettingsProjector.build(settings: .fresh, models: catalog(), contractVersion: "1.0.0")
        XCTAssertEqual(p.auto.resolvedModelId, "model_opus")
        XCTAssertEqual(p.auto.resolvedModelName, "Opus 4.8")
        XCTAssertFalse(p.auto.substituted)
        XCTAssertFalse(p.auto.blocked)
    }

    func testAutoSubstitutesWhenDefaultDown() {
        // Opus down; ChatGPT ready (agy also down) → Auto substitutes within Flagship.
        let models = catalog(ready: ["model_chatgpt"])
        let p = DefaultSettingsProjector.build(settings: .fresh, models: models, contractVersion: "1.0.0")
        XCTAssertEqual(p.auto.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(p.auto.substituted)
        XCTAssertFalse(p.auto.blocked)
    }

    func testAutoPrefersOpus48AndFallsBackToAgyOpus() {
        // Both Opus seats ready → always Claude 4.8.
        let both = DefaultSettingsProjector.build(
            settings: .fresh, models: catalog(ready: ["model_opus", "model_agy_opus"]), contractVersion: "1.0.0")
        XCTAssertEqual(both.auto.resolvedModelId, "model_opus")
        XCTAssertFalse(both.auto.substituted)
        // Claude down, AGY Opus ready → ordered Opus fallback.
        let agyOnly = DefaultSettingsProjector.build(
            settings: .fresh, models: catalog(ready: ["model_agy_opus"]), contractVersion: "1.0.0")
        XCTAssertEqual(agyOnly.auto.resolvedModelId, "model_agy_opus")
        XCTAssertTrue(agyOnly.auto.substituted)
    }

    func testAutoBlocksAndCarriesWaitsMessageWhenTierDown() {
        let models = catalog(ready: [])   // nothing ready
        let p = DefaultSettingsProjector.build(settings: .fresh, models: models, contractVersion: "1.0.0")
        XCTAssertNil(p.auto.resolvedModelId)
        XCTAssertTrue(p.auto.blocked)
        XCTAssertEqual(p.auto.waitsMessage, "No model on Flagship — waits")
    }

    func testOffBenchModelIsNeverLiveAndNeverResolvedByAuto() {
        // A Flagship tier where the default (opus) is OFF-bench but its driver is
        // "ready" upstream, and chatgpt is genuinely live. Auto must skip the off-bench
        // default and substitute to chatgpt — never run a model the user turned off.
        var s = DefaultModelSettings.fresh
        s.tiers.flagship = ["model_opus", "model_chatgpt"]
        let models = [
            entry("model_opus", "Opus 4.8", enabled: false, ready: true),   // driver up, but OFF bench
            entry("model_chatgpt", "ChatGPT 5.5", driver: "codex", enabled: true, ready: true),
        ]
        let p = DefaultSettingsProjector.build(settings: s, models: models, contractVersion: "1.0.0")
        let opus = p.tiers[0].members.first { $0.id == "model_opus" }
        XCTAssertEqual(opus?.ready, false, "off-bench model is not live even if its driver is up")
        XCTAssertEqual(p.tiers[0].readyCount, 1)
        XCTAssertEqual(p.auto.resolvedModelId, "model_chatgpt", "Auto skips the off-bench default")
        XCTAssertTrue(p.auto.substituted)
    }

    func testBuildFromRawModelsMatchesEntryBuild() {
        // The [Model] convenience (used by the Mac app) gates "live" on enablement just
        // like the [Entry] path: an off-bench model whose source is "ready" is not live.
        let models = [
            Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt", driverId: "codex", role: .answerer, enabled: false),
        ]
        var s = DefaultModelSettings.fresh
        s.tiers.flagship = ["model_opus", "model_chatgpt"]
        let p = DefaultSettingsProjector.build(
            settings: s, benchModels: models,
            sourceReadyModelIds: ["model_opus", "model_chatgpt"],   // both sources up
            driverDisplayName: { $0 }, contractVersion: "1.0.0")
        let opus = p.tiers[0].members.first { $0.id == "model_opus" }
        let gpt = p.tiers[0].members.first { $0.id == "model_chatgpt" }
        XCTAssertEqual(opus?.ready, true)
        XCTAssertEqual(gpt?.ready, false, "off-bench → not live even though its source is up")
        XCTAssertEqual(p.auto.resolvedModelId, "model_opus")
    }

    func testStaleTierIdIsDroppedFromRender() {
        var s = DefaultModelSettings.fresh
        s.tiers.flagship.append("model_ghost")   // id not in catalog
        let p = DefaultSettingsProjector.build(settings: s, models: catalog(), contractVersion: "1.0.0")
        XCTAssertFalse(p.tiers[0].members.contains { $0.id == "model_ghost" })
    }
}
