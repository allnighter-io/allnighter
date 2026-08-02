import XCTest
import AllnighterCore
@testable import AllnighterMac

/// CLI M1 step 9 contract proof: the Mac GUI renders the public `TeamRunJSON`
/// shape — the exact thing `alln team --json` emits — directly, with no legacy
/// field translation (no seat/member/council/panel/masterPlan).
final class TeamRunJSONPresenterTests: XCTestCase {

    /// The checked-in CLI fixture renders straight through the presenter.
    func testRendersCheckedInFixtureWithNewShape() throws {
        let run = try Fixtures.decode(TeamRunJSON.self, .teamRunJSON)
        let p = TeamRunJSONPresenter(run: run)

        XCTAssertEqual(p.statusLabel, "done")
        XCTAssertFalse(p.prompt.isEmpty)
        XCTAssertEqual(p.agentRows.count, run.agents.count)
        XCTAssertTrue(p.agentRows.allSatisfy { !$0.modelName.isEmpty })   // model name straight from `agents`
        XCTAssertEqual(run.schemaVersion, 2)
        XCTAssertNotNil(run.answer?.markdown)
        XCTAssertEqual(p.answerMarkdown, run.answer?.markdown)
        XCTAssertEqual(p.planMarkdown, run.answer?.markdown)
        // Agent answers come from `answers` (new vocab), keyed by agentId;
        // one-agent canonical text is on `answer` and surfaced on that row.
        XCTAssertTrue(p.agentRows.contains { $0.answerMarkdown != nil })
        let encoded = try CoreJSON.encode(run)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(root["models"], "catalog models must not appear on TeamRunJSON v2")
        XCTAssertNotNil(root["answer"])
    }

    /// A run with a failed worker and a failed plan renders failures honestly —
    /// the GUI surfaces the failure and shows no plan, straight from TeamRunJSON.
    func testRendersFailedWorkersHonestly() {
        let json = TeamRunJSON(
            contractVersion: "3.0.0",
            teamRun: .init(id: "run_x", status: .done, origin: .cli, prompt: "p",
                           promptSource: .init(kind: .positional), createdAt: "2026-06-15T00:00:00Z"),
            agents: [
                .init(id: "w_ok", modelId: "m", modelName: "Opus 5", sourceId: "claude_code", purpose: .answer, instanceIndex: 0),
                .init(id: "w_bad", modelId: "m", modelName: "Opus 5", sourceId: "claude_code", purpose: .answer, instanceIndex: 1),
            ],
            answers: [
                .init(agentId: "w_ok", status: .done, markdown: "ok"),
                .init(agentId: "w_bad", status: .failed,
                      error: .init(code: "AGENT_FAILED", message: "boom", requiresManual: false, retryable: true)),
            ],
            answer: nil,
            stages: [.init(id: "s_plan", purpose: .plan, status: .failed)],
            plan: nil,
            usage: .init(cliCalls: 2),
            audit: .init(traceId: "t")
        )
        let p = TeamRunJSONPresenter(run: json)

        XCTAssertFalse(p.hasPlan)                             // failed plan -> no plan rendered
        XCTAssertFalse(p.hasAnswer)
        XCTAssertEqual(p.failedAgents.count, 1)              // failure is visible, not hidden
        XCTAssertEqual(p.failedAgents.first?.failureReason, "boom")
        XCTAssertTrue(p.failedAgents.first?.didFail ?? false)
        // The failed plan stage is still exposed to the GUI.
        XCTAssertTrue(p.stageSummaries.contains { $0.contains("plan") && $0.contains("failed") })
    }
}
