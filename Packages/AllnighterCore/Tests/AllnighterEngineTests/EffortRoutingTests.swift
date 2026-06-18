import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// The run's team effort now reaches each CLI: as a `--effort` flag for drivers
/// that take one (Claude), and as a model-label variant for drivers that encode
/// effort in the model name (Antigravity). Grok has no effort axis.
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

    func testGrokHasNoEffortFlag() {
        let args = manifest("grok").resolvedArgs(.init(prompt: "hi", model: "grok-build", effort: .high))
        XCTAssertFalse(args.contains("--effort"), "Grok has no effort axis")
    }

    func testAntigravityRoutesEffortViaModelLabel() {
        // AGY carries no effort flag — effort rides in the model name.
        XCTAssertNil(manifest("antigravity").invoke?.effortFlag)
        let gemini = ModelCatalog.builtIns.first { $0.id == "model_gemini" }!
        XCTAssertEqual(gemini.effortVariants?[.low], "Gemini 3.5 Flash (Low)")
        XCTAssertEqual(gemini.effortVariants?[.high], "Gemini 3.5 Flash (High)")
        let model = Model(id: gemini.id, displayName: gemini.displayName, modelLabel: gemini.modelLabel,
                          driverId: gemini.driverId, effortVariants: gemini.effortVariants)
        let args = manifest("antigravity").resolvedArgs(
            .init(prompt: "hi", model: model.resolvedLabel(at: .high), effort: .high))
        XCTAssertTrue(args.contains("Gemini 3.5 Flash (High)"), "high effort selects the High variant")
        XCTAssertFalse(args.contains("--effort"))
    }

    func testGeminiProMedRoutesToHighSinceNoMediumVariant() {
        let pro = ModelCatalog.builtIns.first { $0.id == "model_gemini_pro" }!
        XCTAssertEqual(pro.effortVariants?[.med], "Gemini 3.1 Pro (High)")
    }

    func testConstantLabelWhenModelHasNoVariants() {
        let opus = Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code")
        XCTAssertEqual(opus.resolvedLabel(at: .high), "opus")
        XCTAssertEqual(opus.resolvedLabel(at: .low), "opus")
    }
}
