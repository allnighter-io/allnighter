import XCTest
import AgentOSCLI
import AgentOSTeam
@testable import AllnighterCore

/// OUR-S03 — terminal receipt seat chips show duration + tok/blame.
final class OURArtifactUsageChipTests: XCTestCase {

    func testSeatChipIncludesTokWhenReported() {
        let agent = Agent(
            id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
            skillId: "x", purpose: .answer
        )
        var run = TeamRun(
            id: "art1", prompt: "p", status: .complete,
            workers: [agent],
            answers: [
                TeamAnswer(
                    memberId: agent.id, modelId: "model_opus", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "Done work.",
                        timing: RunTiming(
                            startedAt: Date().addingTimeInterval(-20),
                            finishedAt: Date(),
                            durationMs: 18400
                        ),
                        reportedTokenUsage: ReportedTokenUsage(
                            inputTokens: 40000, outputTokens: 1200))
                )
            ],
            stages: [], createdAt: Date(), mutating: true
        )
        let card = ArtifactProjector.project(
            run,
            context: .init(
                modelDisplayName: { $0 },
                sourceId: { _ in "claude_code" }
            )
        )
        let seat = try! XCTUnwrap(card.seats.first)
        XCTAssertNotNil(seat.durationMs)
        XCTAssertTrue(seat.usageSegment?.contains("tok") == true, seat.usageSegment ?? "")
        let html = ArtifactProjector.renderHTML(card)
        XCTAssertTrue(html.contains("tok") || html.contains("usage"), html)
    }

    func testSeatChipBlamesSilentCLI() {
        let agent = Agent(
            id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
            skillId: "x", purpose: .answer
        )
        let run = TeamRun(
            id: "art2", prompt: "p", status: .complete,
            workers: [agent],
            answers: [
                TeamAnswer(
                    memberId: agent.id, modelId: "model_grok", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "ok",
                        timing: RunTiming(durationMs: 31000))
                )
            ],
            stages: [], createdAt: Date()
        )
        let card = ArtifactProjector.project(
            run,
            context: .init(
                modelDisplayName: { $0 },
                sourceId: { _ in "grok" }
            )
        )
        let seat = try! XCTUnwrap(card.seats.first)
        XCTAssertTrue(
            seat.usageSegment?.contains("tokens not reported by grok") == true,
            seat.usageSegment ?? "nil"
        )
    }

    func testNoInventedMultiSeatTotalOnChips() {
        let a = Agent(id: "a#0", modelId: "model_opus", instanceIndex: 0, skillId: "x", purpose: .answer)
        let b = Agent(id: "b#0", modelId: "model_grok", instanceIndex: 0, skillId: "x", purpose: .answer)
        let run = TeamRun(
            id: "art3", prompt: "p", status: .complete,
            workers: [a, b],
            answers: [
                TeamAnswer(
                    memberId: a.id, modelId: "model_opus", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "a",
                        reportedTokenUsage: ReportedTokenUsage(inputTokens: 1000, outputTokens: 200))
                ),
                TeamAnswer(
                    memberId: b.id, modelId: "model_grok", role: "answer",
                    result: WorkerRunResult(status: .done, output: "b")
                ),
            ],
            stages: [], createdAt: Date()
        )
        let card = ArtifactProjector.project(
            run,
            context: .init(modelDisplayName: { $0 }, sourceId: { id in
                id.contains("opus") ? "claude_code" : "grok"
            })
        )
        XCTAssertEqual(card.seats.count, 2)
        let byId = Dictionary(uniqueKeysWithValues: card.seats.map { ($0.agentId, $0) })
        XCTAssertTrue(byId["a#0"]?.usageSegment?.contains("tok") == true)
        XCTAssertTrue(byId["b#0"]?.usageSegment?.contains("not reported") == true)
        // No multi-seat manufactured total (would be ~1200 if we wrongly summed).
        XCTAssertFalse(card.seats.contains { $0.usageSegment == "1.2k tok" && $0.agentId == "b#0" })
    }
}
