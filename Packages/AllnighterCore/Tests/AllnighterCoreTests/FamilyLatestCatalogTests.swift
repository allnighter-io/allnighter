import XCTest
import AgentOSCLI
@testable import AllnighterCore

final class FamilyLatestCatalogTests: XCTestCase {

    func testBuiltInGrokPureNameResolvesTo46AndPinStaysPinned() throws {
        let grok = try XCTUnwrap(ModelCatalog.get("model_grok"))
        XCTAssertEqual(grok.modelLabel, "grok-4.6")
        XCTAssertEqual(grok.resolvedPinId, "model_grok_46")
        XCTAssertEqual(grok.family, "grok")
        XCTAssertNil(grok.generation)

        let pin = try XCTUnwrap(ModelCatalog.get("model_grok_46"))
        XCTAssertEqual(pin.modelLabel, "grok-4.6")
        XCTAssertNil(pin.resolvedPinId)
        XCTAssertEqual(pin.generation, 46)

        let pin45 = try XCTUnwrap(ModelCatalog.get("model_grok_45"))
        XCTAssertEqual(pin45.modelLabel, "grok-4.5")
        XCTAssertNil(pin45.resolvedPinId)
    }

    func testBuiltInGeminiFlashIsDirect38Seat() throws {
        let flash = try XCTUnwrap(ModelCatalog.get("model_gemini"))
        XCTAssertEqual(flash.modelLabel, "Gemini 3.8 Flash (Medium)")
        XCTAssertNil(flash.resolvedPinId)
        XCTAssertNil(flash.family)
        XCTAssertNil(flash.generation)
        XCTAssertEqual(flash.displayName, "Gemini 3.8 Flash")
        XCTAssertEqual(flash.effortVariants?[.high], "Gemini 3.8 Flash (High)")
        XCTAssertNil(ModelCatalog.get("model_gemini_36"))
        XCTAssertNil(ModelCatalog.get("model_gemini_37"))
        XCTAssertNil(ModelCatalog.get("model_gemini_38"))
        XCTAssertNil(ModelCatalog.get("model_gemini_pro"))
    }

    func testSonnetUsesVendorAliasLikeOpus() {
        XCTAssertEqual(ModelCatalog.get("model_sonnet")?.modelLabel, "sonnet")
        XCTAssertEqual(ModelCatalog.get("model_opus")?.modelLabel, "opus")
        XCTAssertEqual(ModelCatalog.get("model_fable")?.modelLabel, "fable")
        XCTAssertNil(ModelCatalog.get("model_sonnet")?.resolvedPinId)
        XCTAssertNil(ModelCatalog.get("model_opus")?.family)
    }

    func testGPTSiblingsHaveNoPureNameAndNoInventedOrder() throws {
        XCTAssertNil(ModelCatalog.get("model_gpt"))
        for id in ["model_gpt_sol", "model_gpt_luna", "model_gpt_terra"] {
            let def = try XCTUnwrap(ModelCatalog.get(id))
            XCTAssertNil(def.family, id)
            XCTAssertNil(def.generation, id)
            XCTAssertNil(def.resolvedPinId, id)
        }
    }

    func testCursorGrokAndKimiHaveNoPureName() {
        XCTAssertNil(ModelCatalog.get("model_cursor_grok"))
        XCTAssertNil(ModelCatalog.get("model_kimi"))
        XCTAssertEqual(ModelCatalog.get("model_cursor_grok_46")?.generation, 46)
        XCTAssertEqual(ModelCatalog.get("model_kimi_k3")?.generation, 30)
        XCTAssertNil(ModelCatalog.get("model_kimi_k27_hs")?.family)
    }

    func testModelsJSONSurfacesResolvedPin() throws {
        let grok = try XCTUnwrap(ModelCatalog.get("model_grok"))
        XCTAssertEqual(grok.resolvedPinId, "model_grok_46")
        let pin = try XCTUnwrap(ModelCatalog.get("model_grok_46"))
        XCTAssertNil(pin.resolvedPinId)
    }

    func testReplayUsesPinNotPureName() throws {
        var grok = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok-4.6",
            driverId: "grok")
        grok.resolvedPinId = "model_grok_46"
        var pin = Model(
            id: "model_grok_46", displayName: "Grok 4.6", modelLabel: "grok-4.6",
            driverId: "grok")
        pin.family = "grok"
        pin.generation = 46
        let facts = ModelPinFact.facts(requestedIds: ["model_grok"], models: [grok, pin])
        let run = TeamRun(
            id: "r1", prompt: "x", createdAt: Date(),
            explicitModelIds: ["model_grok"],
            modelPinFacts: facts)
        XCTAssertEqual(run.replayModelIds, ["model_grok_46"])
        let replay = TeamRunReplayCommand.build(from: run)
        let tokens = replay.split(separator: " ").map(String.init)
        let modelIdx = try XCTUnwrap(tokens.firstIndex(of: "--model"))
        XCTAssertEqual(tokens[modelIdx + 1], "model_grok_46")
        XCTAssertEqual(facts?.first?.requestedId, "model_grok")
        XCTAssertEqual(facts?.first?.modelLabel, "grok-4.6")
    }

    func testPinnedIdReplayStaysOnThatPin() {
        var pin = Model(
            id: "model_grok_46", displayName: "Grok 4.6", modelLabel: "grok-4.6",
            driverId: "grok")
        pin.family = "grok"
        pin.generation = 46
        let facts = ModelPinFact.facts(requestedIds: ["model_grok_46"], models: [pin])
        let run = TeamRun(
            id: "r1", prompt: "x", createdAt: Date(),
            explicitModelIds: ["model_grok_46"],
            modelPinFacts: facts)
        XCTAssertEqual(facts?.first?.pinId, "model_grok_46")
        XCTAssertTrue(TeamRunReplayCommand.build(from: run).contains("--model model_grok_46"))
    }
}
