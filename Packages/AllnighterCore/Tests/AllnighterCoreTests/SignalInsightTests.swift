import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// F-S03 Works Test (WT-FLOOR03): Signal produces a typed Insight with receipts,
/// freshness, and a skeptic pass — not only markdown. The Insight Writer's fenced
/// block parses (tolerantly), and the Floor surfaces it on a `kind: insight`
/// return with an insightJSON artifact ref.
final class SignalInsightTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private let writerOutput = """
    Here is the insight in prose.

    No move today — the signal is stale.

    ```signal-insight
    {
      "title": "New model release",
      "summary": "A competitor shipped X.",
      "whatHappened": "They posted a release note.",
      "whyItMatters": "It shifts expectations.",
      "whyThisProject": "We compete on the same surface.",
      "window": "closing",
      "freshness": { "observedAt": "2026-06-18T00:00:00Z", "status": "fresh" },
      "internalLessons": ["ship the gate sooner"],
      "skepticPass": { "verdict": "caution", "reason": "topic is saturated", "saturationRisk": true },
      "receipts": [
        { "id": "r1", "sourceKind": "releaseNote", "observedAt": "2026-06-18T00:00:00Z",
          "relevance": "primary source", "evidenceRole": "primary", "url": "https://example.com" }
      ]
    }
    ```
    """

    func testModelRoundTrips() throws {
        let insight = SignalInsight(
            title: "t", summary: "s", whatHappened: "w", whyItMatters: "m", whyThisProject: "p",
            window: .uncertain, freshness: .init(observedAt: now, status: .uncertain),
            skepticPass: .init(verdict: .pass, reason: "ok"),
            receipts: [SignalReceipt(id: "r1", sourceKind: .xPost, observedAt: now,
                                     relevance: "primary", evidenceRole: .primary)])
        let data = try CoreJSON.encode(insight)
        XCTAssertEqual(try CoreJSON.decode(SignalInsight.self, from: data), insight)
    }

    func testParserExtractsTypedInsight() {
        let insight = SignalInsightParser.parse(fromWriterOutput: writerOutput)
        XCTAssertEqual(insight?.title, "New model release")
        XCTAssertEqual(insight?.window, .closing)
        XCTAssertEqual(insight?.freshness.status, .fresh)
        XCTAssertEqual(insight?.skepticPass.verdict, .caution)
        XCTAssertEqual(insight?.skepticPass.saturationRisk, true)
        XCTAssertEqual(insight?.receipts.count, 1)
        XCTAssertEqual(insight?.receipts.first?.evidenceRole, .primary)
        // Tolerant: externalProductIdeas was omitted → empty, not a decode failure.
        XCTAssertEqual(insight?.externalProductIdeas, [])
    }

    func testParserReturnsNilWithoutBlock() {
        XCTAssertNil(SignalInsightParser.parse(fromWriterOutput: "# Insight\nNo move today."))
        XCTAssertNil(SignalInsightParser.parse(fromWriterOutput: nil))
    }

    func testFloorSurfacesTypedInsight() {
        let plan = StageOutput(id: "stage_plan", purpose: .plan, status: .done,
                               payload: .plan(markdown: writerOutput))
        let run = TeamRun(id: "sigrun", prompt: "p", status: .complete, origin: .cli,
                          presetId: "signal_post_to_project",
                          workers: [Worker(id: "w#0", modelId: "model_grok", instanceIndex: 0, purpose: .plan)],
                          workerAnswers: [TeamAnswer(memberId: "w#0", modelId: "model_grok", role: "plan",
                                                     result: WorkerRunResult(status: .done, output: "x"))],
                          stages: [plan], createdAt: now, lane: .signal, outputKind: .insight)
        let floor = FloorProjector.project(run)
        XCTAssertEqual(floor.floorReturn?.kind, .insight)
        XCTAssertEqual(floor.floorReturn?.insight?.title, "New model release")
        XCTAssertEqual(floor.floorReturn?.insight?.skepticPass.verdict, .caution)
        XCTAssertTrue(floor.floorReturn?.artifactRefs.contains { $0.kind == .insightJSON } ?? false)
    }
}
