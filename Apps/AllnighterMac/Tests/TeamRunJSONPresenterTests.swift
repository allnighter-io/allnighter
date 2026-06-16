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
        XCTAssertEqual(p.workerRows.count, run.workers.count)
        XCTAssertTrue(p.workerRows.allSatisfy { !$0.modelName.isEmpty })   // model name straight from `workers`
        XCTAssertTrue(p.hasPlan)
        XCTAssertEqual(p.planWriterWorkerId, run.plan?.writerWorkerId)     // plan-writer invariant, GUI-side
        XCTAssertFalse(p.stageSummaries.isEmpty)
        // Worker answers come from `workerAnswers` (new vocab), keyed by workerId.
        XCTAssertTrue(p.workerRows.contains { $0.answerMarkdown != nil })
    }

    /// A run with a failed worker and a failed plan renders failures honestly —
    /// the GUI surfaces the failure and shows no plan, straight from TeamRunJSON.
    func testRendersFailedWorkersHonestly() {
        let json = TeamRunJSON(
            contractVersion: "1.0.0",
            teamRun: .init(id: "run_x", status: .done, origin: .cli, prompt: "p",
                           promptSource: .init(kind: .positional), createdAt: "2026-06-15T00:00:00Z"),
            models: [.init(id: "m", displayName: "Opus 4.8", sourceId: "claude_code", status: .ready)],
            workers: [
                .init(id: "w_ok", modelId: "m", modelName: "Opus 4.8", sourceId: "claude_code", purpose: .answer, instanceIndex: 0),
                .init(id: "w_bad", modelId: "m", modelName: "Opus 4.8", sourceId: "claude_code", purpose: .answer, instanceIndex: 1),
            ],
            workerAnswers: [
                .init(workerId: "w_ok", status: .done, markdown: "ok"),
                .init(workerId: "w_bad", status: .failed,
                      error: .init(code: "WORKER_FAILED", message: "boom", requiresManual: false, retryable: true)),
            ],
            stages: [.init(id: "s_plan", purpose: .plan, status: .failed)],
            plan: nil,
            usage: .init(cliCalls: 2),
            audit: .init(traceId: "t", runJournalPath: "/tmp/run.json")
        )
        let p = TeamRunJSONPresenter(run: json)

        XCTAssertFalse(p.hasPlan)                             // failed plan -> no plan rendered
        XCTAssertEqual(p.failedWorkers.count, 1)              // failure is visible, not hidden
        XCTAssertEqual(p.failedWorkers.first?.failureReason, "boom")
        XCTAssertTrue(p.failedWorkers.first?.didFail ?? false)
        // The failed plan stage is still exposed to the GUI.
        XCTAssertTrue(p.stageSummaries.contains { $0.contains("plan") && $0.contains("failed") })
    }
}
