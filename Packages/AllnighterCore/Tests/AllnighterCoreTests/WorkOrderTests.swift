import XCTest
import AllnighterCore

final class WorkOrderTests: XCTestCase {
    func testPanelSummaryCombined() {
        let synthesis = SynthesisConfig(
            analysisDepth: .combined,
            analysisProfileId: "a",
            planProfileId: "p"
        )
        let summary = WorkOrderSummary.teamSummary(workerCount: 3, planWriterLabel: "Sonnet", synthesis: synthesis)
        XCTAssertEqual(summary, "3 workers · Sonnet plan writer · combined analysis + plan")
    }

    func testDesignSummarySingular() {
        XCTAssertEqual(WorkOrderSummary.designSummary(outputCount: 1, engineNames: ["Grok"]), "1 mockup · Grok")
    }
}
