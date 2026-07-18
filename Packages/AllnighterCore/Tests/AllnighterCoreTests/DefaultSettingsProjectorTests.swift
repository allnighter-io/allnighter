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
    private func catalog(ready: Set<String> = [
        "model_fable", "model_chatgpt_sol", "model_chatgpt", "model_opus", "model_sonnet",
        "model_kimi_k3", "model_cursor_grok_45", "model_grok", "model_cursor_composer_25",
        "model_gemini", "model_cursor_auto", "model_composer", "model_extra"
    ]) -> [ModelListJSON.Entry] {
        [
            entry("model_fable", "Fable 5", ready: ready.contains("model_fable")),
            entry("model_chatgpt_sol", "ChatGPT 5.6 Sol", driver: "cursor_agent",
                  ready: ready.contains("model_chatgpt_sol")),
            entry("model_chatgpt", "ChatGPT 5.6", driver: "codex", ready: ready.contains("model_chatgpt")),
            entry("model_opus", "Opus 4.8", ready: ready.contains("model_opus")),
            entry("model_sonnet", "Sonnet 5", ready: ready.contains("model_sonnet")),
            entry("model_kimi_k3", "Kimi K3", driver: "kimi", ready: ready.contains("model_kimi_k3")),
            entry("model_cursor_grok_45", "Cursor Grok 4.5", driver: "cursor_agent",
                  ready: ready.contains("model_cursor_grok_45")),
            entry("model_grok", "Grok 4.5", driver: "grok", ready: ready.contains("model_grok")),
            entry("model_cursor_composer_25", "Composer 2.5", driver: "cursor_agent",
                  ready: ready.contains("model_cursor_composer_25")),
            entry("model_gemini", "Gemini 3.5 Flash", driver: "antigravity", ready: ready.contains("model_gemini")),
            entry("model_cursor_auto", "Cursor Auto", driver: "cursor", ready: ready.contains("model_cursor_auto")),
            entry("model_composer", "Grok Composer 2.5 Fast", driver: "grok", ready: ready.contains("model_composer")),
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
                       ["model_fable", "model_chatgpt_sol"])
        XCTAssertEqual(flagship.defaultModelId, "model_fable")
        XCTAssertTrue(flagship.members[0].isTierDefault)
        XCTAssertFalse(flagship.members[1].isTierDefault)
        XCTAssertEqual(flagship.substituteCount, 1)
        XCTAssertEqual(flagship.readyCount, 2)

        // Gemini spans Balanced + Fast.
        let balanced = p.tiers[1]
        XCTAssertEqual(balanced.members.map(\.id), [
            "model_chatgpt", "model_opus", "model_cursor_grok_45", "model_kimi_k3",
            "model_grok", "model_sonnet", "model_cursor_composer_25", "model_gemini"
        ])
        let gemini = balanced.members.first { $0.id == "model_gemini" }
        XCTAssertEqual(gemini?.tiers, ["balanced", "fast"])
    }

    func testUnassignedIsOnModelsNotInAnyTierSortedAToZ() {
        let p = DefaultSettingsProjector.build(settings: .fresh, models: catalog(), contractVersion: "1.0.0")
        // Only model_extra: it's on and untiered. model_off is off → excluded.
        XCTAssertEqual(p.unassigned.map(\.id), ["model_extra"])
        XCTAssertFalse(p.unassigned.contains { $0.id == "model_off" })
    }

    func testAutoResolvesDefaultWhenReady() {
        let p = DefaultSettingsProjector.build(settings: .fresh, models: catalog(), contractVersion: "1.0.0")
        XCTAssertEqual(p.auto.resolvedModelId, "model_fable")
        XCTAssertEqual(p.auto.resolvedModelName, "Fable 5")
        XCTAssertFalse(p.auto.substituted)
        XCTAssertFalse(p.auto.blocked)
    }

    func testAutoSubstitutesWhenDefaultDown() {
        // Fable down; Sol ready → Auto substitutes within Flagship.
        let models = catalog(ready: ["model_chatgpt_sol"])
        let p = DefaultSettingsProjector.build(settings: .fresh, models: models, contractVersion: "1.0.0")
        XCTAssertEqual(p.auto.resolvedModelId, "model_chatgpt_sol")
        XCTAssertTrue(p.auto.substituted)
        XCTAssertFalse(p.auto.blocked)
    }

    func testAutoPrefersFableAndFallsBackToSol() {
        let both = DefaultSettingsProjector.build(
            settings: .fresh, models: catalog(ready: ["model_fable", "model_chatgpt_sol"]), contractVersion: "1.0.0")
        XCTAssertEqual(both.auto.resolvedModelId, "model_fable")
        XCTAssertFalse(both.auto.substituted)
        let solOnly = DefaultSettingsProjector.build(
            settings: .fresh, models: catalog(ready: ["model_chatgpt_sol"]), contractVersion: "1.0.0")
        XCTAssertEqual(solOnly.auto.resolvedModelId, "model_chatgpt_sol")
        XCTAssertTrue(solOnly.auto.substituted)
    }

    func testAutoBlocksAndCarriesWaitsMessageWhenTierDown() {
        let models = catalog(ready: [])   // nothing ready
        let p = DefaultSettingsProjector.build(settings: .fresh, models: models, contractVersion: "1.0.0")
        XCTAssertNil(p.auto.resolvedModelId)
        XCTAssertTrue(p.auto.blocked)
        XCTAssertEqual(p.auto.waitsMessage, "No model on Flagship — waits")
    }

    func testOffBenchModelIsNeverLiveAndNeverResolvedByAuto() {
        // A Flagship tier where the default (fable) is OFF-bench but its driver is
        // "ready" upstream, and Sol is genuinely live. Auto must skip the off-bench
        // default and substitute to Sol — never run a model the user turned off.
        var s = DefaultModelSettings.fresh
        s.tiers.flagship = ["model_fable", "model_chatgpt_sol"]
        let models = [
            entry("model_fable", "Fable 5", enabled: false, ready: true),   // driver up, but OFF bench
            entry("model_chatgpt_sol", "ChatGPT 5.6 Sol", driver: "cursor_agent", enabled: true, ready: true),
        ]
        let p = DefaultSettingsProjector.build(settings: s, models: models, contractVersion: "1.0.0")
        let fable = p.tiers[0].members.first { $0.id == "model_fable" }
        XCTAssertEqual(fable?.ready, false, "off-bench model is not live even if its driver is up")
        XCTAssertEqual(p.tiers[0].readyCount, 1)
        XCTAssertEqual(p.auto.resolvedModelId, "model_chatgpt_sol", "Auto skips the off-bench default")
        XCTAssertTrue(p.auto.substituted)
    }

    func testBuildFromRawModelsMatchesEntryBuild() {
        // The [Model] convenience (used by the Mac app) gates "live" on enablement just
        // like the [Entry] path: an off-bench model whose source is "ready" is not live.
        let models = [
            Model(id: "model_fable", displayName: "Fable 5", modelLabel: "fable", driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_chatgpt_sol", displayName: "ChatGPT 5.6 Sol", modelLabel: "gpt-5.6-sol-high",
                  driverId: "cursor_agent", role: .both, enabled: false),
        ]
        var s = DefaultModelSettings.fresh
        s.tiers.flagship = ["model_fable", "model_chatgpt_sol"]
        let p = DefaultSettingsProjector.build(
            settings: s, benchModels: models,
            sourceReadyModelIds: ["model_fable", "model_chatgpt_sol"],   // both sources up
            driverDisplayName: { $0 }, contractVersion: "1.0.0")
        let fable = p.tiers[0].members.first { $0.id == "model_fable" }
        let sol = p.tiers[0].members.first { $0.id == "model_chatgpt_sol" }
        XCTAssertEqual(fable?.ready, true)
        XCTAssertEqual(sol?.ready, false, "off-bench → not live even though its source is up")
        XCTAssertEqual(p.auto.resolvedModelId, "model_fable")
    }

    func testStaleTierIdIsDroppedFromRender() {
        var s = DefaultModelSettings.fresh
        s.tiers.flagship.append("model_ghost")   // id not in catalog
        let p = DefaultSettingsProjector.build(settings: s, models: catalog(), contractVersion: "1.0.0")
        XCTAssertFalse(p.tiers[0].members.contains { $0.id == "model_ghost" })
    }
}
