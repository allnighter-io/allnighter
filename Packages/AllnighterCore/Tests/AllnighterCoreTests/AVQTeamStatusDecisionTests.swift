import XCTest
@testable import AllnighterCore

/// AVQ-S01 — honest run decision: queue ticket, progressStale, nextAction precedence.
final class AVQTeamStatusDecisionTests: XCTestCase {

    private func baseRun(
        id: String = "run_avq",
        status: RunStatus = .running,
        phase: RunPhase? = .working,
        lastActivityAt: Date? = nil,
        blocker: RunBlocker? = nil,
        endReason: RunEndReason? = nil
    ) -> TeamRun {
        var run = TeamRun(
            id: id, prompt: "p", status: status, phase: phase,
            createdAt: Date().addingTimeInterval(-120), repoRoot: "/tmp/repo"
        )
        run.lastActivityAt = lastActivityAt
        run.blocker = blocker
        run.endReason = endReason
        run.mutating = true
        return run
    }

    func testQueuedProjectsWriteLockTicket() {
        let acquired = Date().addingTimeInterval(-90)
        let blocker = RunBlocker(
            resource: .repoWriteLock,
            scopeRoot: "/tmp/repo",
            holderId: "run_holder",
            holderKind: "run",
            ticketPosition: 2,
            holderAcquiredAt: acquired
        )
        let run = baseRun(status: .queued, phase: .waitingForWriteLock, blocker: blocker)
        let response = AsyncTeamStatusMapper.statusResponse(for: run)
        let guided = AsyncTeamStatusMapper.withWaitGuidance(response)

        XCTAssertEqual(guided.status, .queued)
        XCTAssertEqual(guided.blocker?.resource, "repoWriteLock")
        XCTAssertEqual(guided.blocker?.holderId, "run_holder")
        XCTAssertEqual(guided.blocker?.ticketPosition, 2)
        XCTAssertNotNil(guided.blocker?.heldSinceSeconds)
        XCTAssertGreaterThanOrEqual(guided.blocker?.heldSinceSeconds ?? 0, 80)
        XCTAssertEqual(guided.nextAction?.kind, "waitForStatus")
        // Never implies this queued run holds the lock.
        XCTAssertNotEqual(guided.blocker?.holderId, run.id)
    }

    func testStalledNextActionIsInspectStallNotWait() {
        let stale = Date().addingTimeInterval(-(RunActivity.defaultIdleBudgetSeconds + 30))
        let run = baseRun(status: .running, lastActivityAt: stale)
        var response = AsyncTeamStatusMapper.statusResponse(for: run)
        response.lastProgressAt = stale
        response.progressStale = true
        response.silenceStatus = "alive, no stream for 90s"
        let guided = AsyncTeamStatusMapper.withWaitGuidance(response)

        XCTAssertEqual(guided.nextAction?.kind, "inspectStall")
        XCTAssertEqual(guided.waitHintSeconds, 0)
        XCTAssertNotEqual(guided.nextAction?.kind, "waitForStatus")
    }

    func testBeforeFirstProgressPreservesUnknownStale() {
        let run = baseRun(status: .running, lastActivityAt: nil)
        var response = AsyncTeamStatusMapper.statusResponse(for: run)
        // Mirror service: progressStale nil before first activity.
        response.progressStale = RunActivity.progressStale(
            lastActivityAt: nil, now: Date()
        )
        XCTAssertNil(response.progressStale)
        let guided = AsyncTeamStatusMapper.withWaitGuidance(response)
        XCTAssertEqual(guided.nextAction?.kind, "waitForStatus")
        XCTAssertNil(guided.progressStale)
    }

    func testTerminalFetchResult() {
        var run = baseRun(status: .done, phase: nil, endReason: .completed)
        run.blocker = nil
        let guided = AsyncTeamStatusMapper.withWaitGuidance(
            AsyncTeamStatusMapper.statusResponse(for: run)
        )
        XCTAssertEqual(guided.nextAction?.kind, "fetchResult")
        XCTAssertEqual(guided.waitHintSeconds, 0)
        XCTAssertNil(guided.blocker)
    }

    func testReadOnlyRunHasNoWriteLockBlocker() {
        var run = baseRun(status: .running)
        run.mutating = false
        run.blocker = nil
        let response = AsyncTeamStatusMapper.statusResponse(for: run)
        XCTAssertNil(response.blocker)
    }

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
        XCTAssertTrue(stall.command.contains("ps"))
        let block = AsyncTeamNextAction.inspectBlocker(runId: "r1")
        XCTAssertEqual(block.kind, "inspectBlocker")
    }
}
