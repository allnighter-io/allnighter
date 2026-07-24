import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// The run's team effort now reaches each CLI: as a `--effort` flag for drivers
/// that take one (Claude), and as a model-label variant for drivers that encode
/// effort in the model name (Antigravity). Grok 4.5 uses `--reasoning-effort`.
final class EffortRoutingTests: XCTestCase {

    private func manifest(_ id: String) -> DriverManifest {
        DefaultConfig.manifests.first { $0.id == id }!
    }

    func testClaudeAppendsEffortFlagFromTeamEffort() {
        let m = manifest("claude_code")
        XCTAssertNotNil(m.invoke?.effortFlag, "Claude wires the --effort flag")
        XCTAssertEqual(
            m.resolvedArgs(.init(prompt: "hi", model: "opus", effort: .high)).suffix(2),
            ["--effort", "high"])
        XCTAssertEqual(
            m.resolvedArgs(.init(prompt: "hi", model: "opus", effort: .med)).suffix(2),
            ["--effort", "medium"])
        XCTAssertEqual(
            m.resolvedArgs(.init(prompt: "hi", model: "opus", effort: .low)).suffix(2),
            ["--effort", "low"])
    }

    func testGrokPassesReasoningEffortFlag() {
        let args = manifest("grok").resolvedArgs(.init(prompt: "hi", model: "grok-4.5", effort: .high))
        let idx = try! XCTUnwrap(args.firstIndex(of: "--reasoning-effort"))
        XCTAssertEqual(args[idx + 1], "high")
    }

    func testCodexPassesModelAndReasoningEffortBeforePrompt() {
        let m = manifest("codex")
        XCTAssertNotNil(m.invoke?.effortFlag)
        let args = m.resolvedArgs(.init(prompt: "do it", model: "gpt-5.4-mini",
                                        outputFile: "/tmp/out.txt", effort: .high))
        XCTAssertTrue(args.contains("-m"))
        XCTAssertTrue(args.contains("gpt-5.4-mini"), "the selected Codex model is passed via -m")
        XCTAssertTrue(args.contains(#"model_reasoning_effort="high""#))
        let cIdx = try! XCTUnwrap(args.firstIndex(of: "-c"))
        let promptIdx = try! XCTUnwrap(args.firstIndex(of: "do it"))
        XCTAssertLessThan(cIdx, promptIdx, "the effort override precedes the positional prompt")
        // Low/medium map through too.
        XCTAssertTrue(m.resolvedArgs(.init(prompt: "x", model: "gpt-5.5", outputFile: "/tmp/o", effort: .low))
            .contains(#"model_reasoning_effort="low""#))
    }

    func testAntigravityRoutesEffortViaModelLabel() {
        // AGY carries no effort flag — effort rides in the model name.
        XCTAssertNil(manifest("antigravity").invoke?.effortFlag)
        let gemini = ModelCatalog.builtIns.first { $0.id == "model_gemini" }!
        XCTAssertEqual(gemini.effortVariants?[.low], "Gemini 3.6 Flash (Low)")
        XCTAssertEqual(gemini.effortVariants?[.high], "Gemini 3.6 Flash (High)")
        let model = Model(id: gemini.id, displayName: gemini.displayName, modelLabel: gemini.modelLabel,
                          driverId: gemini.driverId, effortVariants: gemini.effortVariants)
        let args = manifest("antigravity").resolvedArgs(
            .init(prompt: "hi", model: model.resolvedLabel(at: .high), effort: .high))
        XCTAssertTrue(args.contains("Gemini 3.6 Flash (High)"), "high effort selects the High variant")
        XCTAssertFalse(args.contains("--effort"))
    }

    func testGeminiProMedRoutesToHighSinceNoMediumVariant() {
        let pro = ModelCatalog.builtIns.first { $0.id == "model_gemini_pro" }!
        XCTAssertEqual(pro.effortVariants?[.med], "Gemini 3.1 Pro (High)")
    }

    func testConstantLabelWhenModelHasNoVariants() {
        let opus = Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code")
        XCTAssertEqual(opus.resolvedLabel(at: .high), "opus")
        XCTAssertEqual(opus.resolvedLabel(at: .low), "opus")
    }

    func testSupportsEffortFlagBasedDrivers() {
        let opus = Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code")
        XCTAssertTrue(opus.supportsEffort(manifest: manifest("claude_code")))
        let chatgpt = Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex")
        XCTAssertTrue(chatgpt.supportsEffort(manifest: manifest("codex")))
    }

    func testCursorModelsDoNotSupportEffort() {
        let cursorFast = Model(id: "model_cursor_composer_25_fast", displayName: "Composer 2.5 Fast",
                               modelLabel: "composer-2.5-fast", driverId: "cursor_agent")
        XCTAssertFalse(cursorFast.supportsEffort(manifest: manifest("cursor_agent")))
    }

    func testGrok45SupportsEffort() {
        let grok = Model(id: "model_grok", displayName: "Grok 4.5", modelLabel: "grok-4.5", driverId: "grok")
        XCTAssertTrue(grok.supportsEffort(manifest: manifest("grok")))
        let composer = Model(id: "model_composer", displayName: "Grok Composer 2.5 Fast",
                             modelLabel: "grok-composer-2.5-fast", driverId: "grok")
        XCTAssertTrue(composer.supportsEffort(manifest: manifest("grok")))
    }

    func testCursorGrokRoutesEffortViaModelLabel() throws {
        let manifest = try Fixtures.manifest(.manifestCursor)
        let def = ModelCatalog.builtIns.first { $0.id == "model_cursor_grok_45" }!
        let model = Model(id: def.id, displayName: def.displayName, modelLabel: def.modelLabel,
                          driverId: def.driverId, effortVariants: def.effortVariants)
        let args = manifest.resolvedArgs(
            .init(prompt: "hi", model: model.resolvedLabel(at: .high), effort: .high))
        let modelIdx = try XCTUnwrap(args.firstIndex(of: "--model"))
        XCTAssertEqual(args[modelIdx + 1], "cursor-grok-4.5-high")
        XCTAssertFalse(args.contains("--reasoning-effort"))
    }

    func testAntigravityEffortVariantsGateEffortDial() {
        let flash = ModelCatalog.builtIns.first { $0.id == "model_gemini" }!
        let flashModel = Model(id: flash.id, displayName: flash.displayName, modelLabel: flash.modelLabel,
                               driverId: flash.driverId, effortVariants: flash.effortVariants)
        XCTAssertTrue(flashModel.supportsEffort(manifest: manifest("antigravity")))
        let fixed = ModelCatalog.builtIns.first { $0.id == "model_agy_sonnet" }!
        let fixedModel = Model(id: fixed.id, displayName: fixed.displayName, modelLabel: fixed.modelLabel,
                               driverId: fixed.driverId, effortVariants: fixed.effortVariants)
        XCTAssertFalse(fixedModel.supportsEffort(manifest: manifest("antigravity")))
    }

    func testUnknownCustomModelInheritsDriverEffortFlag() {
        let custom = Model(id: "custom_grok_fast", displayName: "Mystery", modelLabel: "mystery", driverId: "grok")
        XCTAssertTrue(custom.supportsEffort(manifest: manifest("grok")))
    }
}
