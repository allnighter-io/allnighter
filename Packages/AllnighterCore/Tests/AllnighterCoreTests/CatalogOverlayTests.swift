import XCTest
@testable import AllnighterCore
import AgentOSCLI

final class CatalogOverlayTests: XCTestCase {

    /// Founder-ruled caliber order for the primary seats (2026-08-08):
    /// Fable > Sol > Opus > K3 > Grok 4.5 > GLM > Qwen 3.8 Max > DeepSeek V4 Pro.
    ///
    /// Seating itself is deliberately NOT hardcoded (see
    /// `TeamResolverTests.testW1SpecReviewMinFullBenchSeatsDiverseFamilies`) so a
    /// new, higher-ranked model auto-seats. That makes the *data* the only place
    /// this ordering can be wrong — and it was: Qwen 3.8 Max shipped at rank 92,
    /// above Opus (90) and K3 (88), so Spec Review Min quietly seated Qwen over
    /// K3. A seating-law test cannot catch a bad rank, so the rank is asserted
    /// here, where it is authored.
    func testPrimarySeatCaliberFollowsFounderOrdering() {
        let order = [
            "model_fable", "model_gpt_sol", "model_opus", "model_kimi_k3",
            "model_cursor_grok_45", "model_opencode_glm_5_2",
            "model_opencode_qwen_38_max", "model_opencode_deepseek_v4_pro",
        ]
        let caps = ModelCatalog.builtInCapabilities
        let ranks: [(String, Int)] = order.map { id in
            guard let rank = caps[id]?.strengthRank else {
                XCTFail("primary seat \(id) missing from the built-in catalog")
                return (id, -1)
            }
            return (id, rank)
        }
        for (lhs, rhs) in zip(ranks, ranks.dropFirst()) {
            XCTAssertGreaterThan(
                lhs.1, rhs.1,
                "founder caliber order broken: \(lhs.0)=\(lhs.1) must outrank \(rhs.0)=\(rhs.1)")
        }

        // Driver variants of one reasoning family share a caliber — a seat must
        // not get stronger by being run through a different CLI.
        for (a, b) in [("model_fable", "model_cursor_fable"),
                       ("model_gpt_sol", "model_cursor_gpt_sol"),
                       ("model_opus", "model_cursor_opus"),
                       ("model_grok", "model_cursor_grok_45"),
                       ("model_grok_46", "model_cursor_grok_46"),
                       ("model_qwen_38_max", "model_opencode_qwen_38_max")] {
            XCTAssertEqual(caps[a]?.strengthRank, caps[b]?.strengthRank,
                           "\(a) and \(b) are the same model on different CLIs")
        }

        // Headroom: nothing may sit at the ceiling, or a genuinely stronger
        // model has nowhere to go (founder: "if max is 100 we will have
        // problems too soon").
        let top = caps.values.compactMap(\.strengthRank).max() ?? 0
        XCTAssertLessThanOrEqual(top, 96, "leave room above the strongest seat; top rank is \(top)")
    }

    func testOverlayAcceptsPolicyFieldsOnly() {
        let valid = Data(
            """
            {
              "schemaVersion": 1,
              "models": {
                "model_grok": {
                  "defaultOn": true,
                  "defaultEffort": "high",
                  "caliber": {
                    "laneTags": ["code"],
                    "capabilityTags": ["code"],
                    "strengthRank": 87
                  }
                }
              }
            }
            """.utf8
        )
        XCTAssertNoThrow(try CatalogOverlayLoader.decode(valid))

        let invalid = Data(
            """
            {
              "schemaVersion": 1,
              "models": {
                "model_grok": {
                  "defaultOn": true,
                  "modelLabel": "nope"
                }
              }
            }
            """.utf8
        )
        XCTAssertThrowsError(try CatalogOverlayLoader.decode(invalid)) { error in
            XCTAssertTrue(String(describing: error).contains("unknown field 'modelLabel'"))
        }
    }

    func testUnknownOverlayModelIsDiagnosedAndIgnored() throws {
        let overlay = CatalogOverlay(models: [
            "model_grok": CatalogOverlayModel(defaultOn: true),
            "model_ghost": CatalogOverlayModel(defaultOn: true),
        ])
        let catalog = try CatalogLoader.bundled()
        let diags = CatalogMerge.unknownOverlayDiagnostics(overlay: overlay, catalog: catalog)
        XCTAssertTrue(diags.contains { $0.modelId == "model_ghost" })
        XCTAssertFalse(ModelCatalog.builtIns.contains { $0.id == "model_ghost" })
    }

    func testHiddenModelSuppressesPersistedRosterEntry() throws {
        let overlay = CatalogOverlay(models: [
            "model_sonnet": CatalogOverlayModel(defaultOn: true, hidden: true),
        ])
        let roster = ModelRosterState(enabledModelIds: ["model_sonnet", "model_opus"])
        let diags = CatalogMerge.hiddenRosterDiagnostics(overlay: overlay, roster: roster)
        XCTAssertTrue(diags.contains { $0.modelId == "model_sonnet" })

        let catalog = try CatalogLoader.bundled()
        let visible = try CatalogMerge.builtInDefinitions(catalog: catalog, overlay: overlay)
        XCTAssertFalse(visible.contains { $0.id == "model_sonnet" })
    }

    func testInvalidHiddenAndDefaultOnFailsDecode() {
        let invalid = Data(
            """
            {
              "schemaVersion": 1,
              "models": {
                "model_grok": { "defaultOn": true, "hidden": true }
              }
            }
            """.utf8
        )
        XCTAssertThrowsError(try CatalogOverlayLoader.decode(invalid)) { error in
            XCTAssertTrue(String(describing: error).contains("hidden and defaultOn"))
        }
    }

    func testAntigravityClaudeSeatsAreFreshDefaults() {
        let agy = ModelCatalog.builtIns.filter { $0.driverId == "antigravity" }
        XCTAssertEqual(
            Set(agy.filter(\.defaultEnabled).map(\.id)),
            ["model_gemini", "model_agy_opus", "model_agy_sonnet"]
        )
        XCTAssertEqual(agy.first { $0.id == "model_agy_opus" }?.displayName, "Opus 4.6 (Antigravity)")
        XCTAssertEqual(agy.first { $0.id == "model_agy_sonnet" }?.displayName, "Sonnet 4.6 (Antigravity)")
    }

    func testLunaShipsOnEconomyBenchWithHighDefaultEffort() {
        let luna = ModelCatalog.builtIns.first { $0.id == "model_gpt_luna" }
        XCTAssertEqual(luna?.displayName, "GPT-5.6 Luna")
        XCTAssertEqual(luna?.modelLabel, "gpt-5.6-luna")
        XCTAssertTrue(luna?.defaultEnabled ?? false)
        XCTAssertEqual(luna?.defaultEffort, .high)
        XCTAssertTrue(DefaultModelSettings.fresh.tiers.economy.contains("model_gpt_luna"))
        XCTAssertEqual(DefaultModelSettings.fresh.tierDefault(.economy), "model_gpt_luna")
    }
}
