import XCTest
import AppKit
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

@MainActor
final class AppModelTests: XCTestCase {

    func testLoadsDefaultPanel() {
        let model = AppModel()
        XCTAssertEqual(model.models.count, 6)
        XCTAssertFalse(model.isConfigurationBroken)
    }

    func testHasTieredPresets() {
        let model = AppModel()
        XCTAssertTrue(model.presets.contains { $0.id == "preset_fast" })
        XCTAssertTrue(model.presets.contains { $0.builtIn })
        // A preset is active by default and seats the panel.
        XCTAssertFalse(model.expandedWorkers.isEmpty)
    }

    func testApplyPresetSetsSeatsSynthesisAndActiveId() {
        let model = AppModel()
        guard let quality = model.presets.first(where: { $0.id == "preset_quality" }) else { return XCTFail("no quality preset") }
        model.apply(quality)
        XCTAssertEqual(model.activePresetId, "preset_quality")
        XCTAssertEqual(model.currentSynthesis.analysisDepth, .separate)
        XCTAssertEqual(model.expandedWorkers.count, quality.workerSpecs.expandedWorkers().count)
    }

    func testSelfDoublePresetExpandsToMultipleSeats() {
        let model = AppModel()
        guard let selfDouble = model.presets.first(where: { $0.id == "preset_self_double" }) else { return }
        model.apply(selfDouble)
        XCTAssertEqual(model.expandedWorkers.count, 3)
        XCTAssertEqual(Set(model.expandedWorkers.map(\.modelId)).count, 1)
    }

    func testToggleWorkerEditsSeatsAndClearsPreset() {
        let model = AppModel()
        guard let worker = model.models.first else { return }
        let wasSeated = model.isSeated(worker)
        model.toggle(worker)
        XCTAssertNotEqual(model.isSeated(worker), wasSeated)
        XCTAssertNil(model.activePresetId)
    }

    func testJudgeResolvesToCanSynthesizeModel() {
        let model = AppModel()
        // Default panel includes Opus (role .both).
        if model.models.contains(where: { $0.canWritePlan }) {
            XCTAssertNotNil(model.planWriterModel)
            XCTAssertTrue(model.planWriterModel?.canWritePlan ?? false)
        }
    }

    func testWorkOrderSummaryReflectsSeatsAndDepth() {
        let model = AppModel()
        let summary = model.workOrderSummary
        XCTAssertTrue(summary.contains("\(model.expandedWorkers.count) worker"))
        if model.currentSynthesis.analysisDepth == .combined {
            XCTAssertTrue(summary.contains("combined analysis + plan"))
        } else {
            XCTAssertTrue(summary.contains("separate analysis + plan"))
        }
    }

    func testRunRequiresPrompt() {
        let model = AppModel()
        model.prompt = "   "
        model.runTeam()
        XCTAssertNil(model.run)
        XCTAssertFalse(model.isRunning)
    }

    func testBundleMarkdownEmptyWithoutRun() {
        let model = AppModel()
        XCTAssertTrue(model.bundleMarkdown().isEmpty)
    }

    func testManualAnswerNoOpWithoutRun() {
        let model = AppModel()
        model.setManualAnswer(workerId: "model_opus#0", text: "hi")
        XCTAssertNil(model.run)
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

    /// Launch Authority TCC hotfix (H0/H1/H6): the cold-launch cache load must
    /// NOT start live detection. The original code red was launch → runDetection
    /// → isDetecting = true → shell/CLI spawn → TCC prompt. Re-adding a probe to
    /// the launch path would flip isDetecting and fail this gate.
    func testLoadCachedSetupStateDoesNotStartDetection() {
        let model = AppModel()
        XCTAssertFalse(model.isDetecting)
        model.loadCachedSetupState()
        XCTAssertFalse(model.isDetecting, "cold-launch cache load must never start a live probe")
    }

    /// Authority gate (H1): a full probe that is not user-initiated must fall
    /// back to the quiet cache load instead of spawning.
    func testFullSetupProbeWithoutUserIntentDoesNotDetect() {
        let model = AppModel()
        model.runFullSetupProbe(userInitiated: false)
        XCTAssertFalse(model.isDetecting, "a non-user-initiated full probe must not spawn")
    }

    func testHistorySelectionDrivesDisplayRun() {
        let model = AppModel()
        let past = TeamRun(id: "r1", prompt: "old prompt", status: .complete, createdAt: Date())
        model.openHistory(past)
        XCTAssertEqual(model.displayRun?.id, "r1")
        model.closeHistory()
        XCTAssertNil(model.displayRun)
    }
}
