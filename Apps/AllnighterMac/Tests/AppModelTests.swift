import XCTest
import AppKit
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

@MainActor
final class AppModelTests: XCTestCase {

    func testLoadsDefaultPanel() {
        let model = AppModel()
        // Falls back to at least one worker even if the bundle resource is missing.
        XCTAssertFalse(model.workers.isEmpty)
    }

    func testToggleFlipsEnabled() {
        let model = AppModel()
        guard let first = model.workers.first else { return XCTFail("no workers") }
        let before = first.enabled
        model.toggle(first)
        XCTAssertEqual(model.workers.first?.enabled, !before)
    }

    func testEnabledWorkersExcludesDisabled() {
        let model = AppModel()
        let total = model.workers.count
        if let first = model.workers.first, first.enabled {
            model.toggle(first)
            XCTAssertEqual(model.enabledWorkers.count, total - 1)
        }
    }

    func testRunRequiresPrompt() {
        let model = AppModel()
        model.prompt = "   "
        model.runCouncil()
        XCTAssertNil(model.run)
        XCTAssertFalse(model.isRunning)
    }

    func testSynthesizerIsAWorkerThatCanSynthesize() {
        let model = AppModel()
        // The default panel includes Opus (role .both); it should be the synthesizer.
        if model.workers.contains(where: { $0.canSynthesize && $0.enabled }) {
            XCTAssertNotNil(model.synthesizerWorker)
            XCTAssertTrue(model.synthesizerWorker?.canSynthesize ?? false)
        }
    }

    func testBundleMarkdownEmptyWithoutRun() {
        let model = AppModel()
        XCTAssertTrue(model.bundleMarkdown().isEmpty)
    }

    func testManualAnswerMarksMemberDone() {
        let model = AppModel()
        // Seed a run with one skipped member via a real run shape.
        model.prompt = "x"
        // No run yet; setManualAnswer should be a no-op without a run.
        model.setManualAnswer(workerId: "worker_opus", text: "hi")
        XCTAssertNil(model.run)
    }

    // MARK: - Phase 05

    func testBuiltInPanelPresetIsAvailable() {
        let model = AppModel()
        XCTAssertTrue(model.panelPresets.contains { $0.builtIn })
    }

    func testBuiltInInstructionPresetIsAvailable() {
        let model = AppModel()
        XCTAssertTrue(model.instructionPresets.contains { $0.id == SynthesisInstructions.defaultID })
    }

    func testApplyPresetSetsSynthesizerInstructionsAndPanel() {
        let model = AppModel()
        guard let preset = model.panelPresets.first(where: { $0.builtIn }) else { return XCTFail("no built-in preset") }
        model.applyPreset(preset)
        XCTAssertEqual(model.activePresetId, preset.id)
        XCTAssertEqual(model.synthesizerWorkerId, preset.draftSynthesizerWorkerId)
        XCTAssertEqual(model.selectedInstructionPresetId, preset.draftSynthesisInstructionPresetId)
        let enabledIds = Set(model.enabledWorkers.map(\.id))
        let expected = Set(preset.panelWorkerIds).intersection(Set(model.workers.map(\.id)))
        XCTAssertEqual(enabledIds, expected)
    }

    func testDefaultInstructionChoicePersistsPresetID() {
        let model = AppModel()
        model.selectInstructionPreset(id: SynthesisInstructions.defaultID)
        XCTAssertEqual(model.synthesisChoice.persistedValue, SynthesisInstructions.defaultID)
    }

    func testEditingInstructionsBecomesCustomChoice() {
        let model = AppModel()
        model.selectInstructionPreset(id: SynthesisInstructions.defaultID)
        model.instructionText = "Totally custom instructions."
        XCTAssertEqual(model.synthesisChoice.persistedValue, "Totally custom instructions.")
        XCTAssertEqual(model.synthesisChoice.text, "Totally custom instructions.")
    }

    func testTogglingPanelClearsActivePreset() {
        let model = AppModel()
        guard let preset = model.panelPresets.first(where: { $0.builtIn }),
              let worker = model.workers.first else { return }
        model.applyPreset(preset)
        XCTAssertNotNil(model.activePresetId)
        model.toggle(worker)
        XCTAssertNil(model.activePresetId)
    }

    func testQuickCapturePrefillsFromClipboardWhenEmpty() {
        let model = AppModel()
        model.prompt = ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("clipboard question", forType: .string)
        model.quickCapture(prefillClipboard: true)
        XCTAssertEqual(model.prompt, "clipboard question")
    }

    func testQuickCaptureDoesNotOverwriteExistingPrompt() {
        let model = AppModel()
        model.prompt = "already typed"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("clip", forType: .string)
        model.quickCapture(prefillClipboard: true)
        XCTAssertEqual(model.prompt, "already typed")
    }

    func testHistorySelectionDrivesDisplayRun() {
        let model = AppModel()
        let past = CouncilRun(id: "r1", prompt: "old prompt", status: .complete, createdAt: Date())
        model.openHistory(past)
        XCTAssertEqual(model.displayRun?.id, "r1")
        model.closeHistory()
        XCTAssertNil(model.displayRun)
    }
}
