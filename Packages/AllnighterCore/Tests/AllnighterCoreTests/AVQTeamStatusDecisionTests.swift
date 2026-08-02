import XCTest
@testable import AllnighterCore

/// AVQ-S01 — progress-stale / write-lock truth that survived the ORS-S03b
/// deletion of `TeamStatusResponse` decision helpers. Queue-ticket and stall
/// presentation now live on `TeamRunJSON` / `alln show`; this suite keeps the
/// RunActivity budget and inspect helpers that remain product surface.
final class AVQTeamStatusDecisionTests: XCTestCase {

    func testProgressStaleUsesRunActivityBudgetNotSecondArbiter() {
        let now = Date()
        let fresh = now.addingTimeInterval(-10)
        XCTAssertEqual(RunActivity.progressStale(lastActivityAt: fresh, now: now), false)
        let stale = now.addingTimeInterval(-(RunActivity.defaultIdleBudgetSeconds + 1))
        XCTAssertEqual(RunActivity.progressStale(lastActivityAt: stale, now: now), true)
        XCTAssertNil(RunActivity.progressStale(lastActivityAt: nil, now: now))
    }

    func testInspectStallAndInspectBlockerHelpers() {
        let stall = AsyncTeamNextAction.inspectStall(runId: "r1")
        XCTAssertEqual(stall.kind, "inspectStall")
        XCTAssertTrue(stall.command.contains("alln show r1 --json"),
                      "stall inspect must reattach via show, not fleet ps alone (got: \(stall.command))")
        XCTAssertFalse(stall.label.contains("progressStale"),
                       "ORS: progressStale is not the public stall label")
        let block = AsyncTeamNextAction.inspectBlocker(runId: "r1")
        XCTAssertEqual(block.kind, "inspectBlocker")
    }

    func testLiveStatusQueuedWhenFanningOutWithNoActiveWorker() {
        var run = TeamRun(
            id: "run_avq", prompt: "p", status: .fanningOut,
            createdAt: Date(), repoRoot: "/tmp/repo"
        )
        run.answers = []
        XCTAssertEqual(AsyncTeamStatusMapper.liveStatus(for: run), .queued)
    }
}
