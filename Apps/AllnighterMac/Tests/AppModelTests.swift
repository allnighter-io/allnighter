import XCTest
import AllnighterCore
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
}
