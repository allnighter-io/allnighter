import XCTest
import AllnighterCore

final class WorkOrderTests: XCTestCase {
    func testPanelSummaryCombined() {
        let synthesis = SynthesisConfig(
            analysisDepth: .combined,
            analysisProfileId: "a",
            planProfileId: "p"
        )
        let summary = WorkOrder.panelSummary(seatCount: 3, judgeLabel: "Sonnet", synthesis: synthesis)
        XCTAssertEqual(summary, "3 seats · Sonnet judge · combined judge")
    }

    func testDesignSummarySingular() {
        XCTAssertEqual(WorkOrder.designSummary(outputCount: 1, engineNames: ["Grok"]), "1 mockup · Grok")
    }
}
