import XCTest
import AllnighterCore

final class WorkOrderTests: XCTestCase {
    func testPanelSummaryCombined() {
        let synthesis = SynthesisConfig(
            analysisDepth: .combined,
            analysisProfileId: "a",
            planProfileId: "p"
        )
        let summary = WorkOrder.teamSummary(workerCount: 3, judgeLabel: "Sonnet", synthesis: synthesis)
        XCTAssertEqual(summary, "3 workers · Sonnet plan writer · combined analysis + plan")
    }

    func testDesignSummarySingular() {
        XCTAssertEqual(WorkOrder.designSummary(outputCount: 1, engineNames: ["Grok"]), "1 mockup · Grok")
    }
}
