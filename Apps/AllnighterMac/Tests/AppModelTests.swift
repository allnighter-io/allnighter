import XCTest
import AppKit
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

@MainActor
final class AppModelTests: XCTestCase {

    func testLoadsDefaultPanel() {
        let model = AppModel()
        XCTAssertFalse(model.workers.isEmpty)
    }

    func testHasTieredPresets() {
        let model = AppModel()
        XCTAssertTrue(model.presets.contains { $0.id == "preset_fast" })
        XCTAssertTrue(model.presets.contains { $0.builtIn })
        // A preset is active by default and seats the panel.
        XCTAssertFalse(model.expandedSeats.isEmpty)
    }

    func testApplyPresetSetsSeatsSynthesisAndActiveId() {
        let model = AppModel()
        guard let quality = model.presets.first(where: { $0.id == "preset_quality" }) else { return XCTFail("no quality preset") }
        model.apply(quality)
        XCTAssertEqual(model.activePresetId, "preset_quality")
        XCTAssertEqual(model.currentSynthesis.analysisDepth, .separate)
        XCTAssertEqual(model.expandedSeats.count, quality.seats.expandedSeats().count)
    }

    func testSelfDoublePresetExpandsToMultipleSeats() {
        let model = AppModel()
        guard let selfDouble = model.presets.first(where: { $0.id == "preset_self_double" }) else { return }
        model.apply(selfDouble)
        XCTAssertEqual(model.expandedSeats.count, 3)
        XCTAssertEqual(Set(model.expandedSeats.map(\.workerId)).count, 1)
    }

    func testToggleWorkerEditsSeatsAndClearsPreset() {
        let model = AppModel()
        guard let worker = model.workers.first else { return }
        let wasSeated = model.isSeated(worker)
        model.toggle(worker)
        XCTAssertNotEqual(model.isSeated(worker), wasSeated)
        XCTAssertNil(model.activePresetId)
    }

    func testJudgeResolvesToCanSynthesizeWorker() {
        let model = AppModel()
        // Default panel includes Opus (role .both).
        if model.workers.contains(where: { $0.canSynthesize }) {
            XCTAssertNotNil(model.judgeWorker)
            XCTAssertTrue(model.judgeWorker?.canSynthesize ?? false)
        }
    }

    func testWorkOrderSummaryReflectsSeatsAndDepth() {
        let model = AppModel()
        let summary = model.workOrderSummary
        XCTAssertTrue(summary.contains("\(model.expandedSeats.count) seat"))
        if model.currentSynthesis.analysisDepth == .combined {
            XCTAssertTrue(summary.contains("combined judge"))
        } else {
            XCTAssertTrue(summary.contains("separate analysis + plan"))
        }
    }

    func testRunRequiresPrompt() {
        let model = AppModel()
        model.prompt = "   "
        model.runCouncil()
        XCTAssertNil(model.run)
        XCTAssertFalse(model.isRunning)
    }

    func testBundleMarkdownEmptyWithoutRun() {
        let model = AppModel()
        XCTAssertTrue(model.bundleMarkdown().isEmpty)
    }

    func testManualAnswerNoOpWithoutRun() {
        let model = AppModel()
        model.setManualAnswer(seatId: "worker_opus#0", text: "hi")
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

    func testHistorySelectionDrivesDisplayRun() {
        let model = AppModel()
        let past = CouncilRun(id: "r1", prompt: "old prompt", status: .complete, createdAt: Date())
        model.openHistory(past)
        XCTAssertEqual(model.displayRun?.id, "r1")
        model.closeHistory()
        XCTAssertNil(model.displayRun)
    }
}
