import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class StalledWorkDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let old = Date(timeIntervalSince1970: 1_699_998_000) // 2000s ago

    func testWorkerChatTurnPastThresholdCreatesEpisode() {
        let thread = WorkThread(
            id: "t1",
            title: "Review",
            createdAt: old,
            updatedAt: old,
            projectId: "projA",
            turns: [
                ThreadTurn(
                    id: "turn1",
                    threadId: "t1",
                    kind: .workerChat,
                    status: .running,
                    createdAt: old,
                    author: .worker,
                    text: "Working...",
                    workerId: "model_opus"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input, thresholds: .init(workerChatSeconds: 1800, teamRunSeconds: 3600))
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].projectId, "projA")
        XCTAssertEqual(episodes[0].targetKind, StallTargetKind.workerTurn)
    }

    func testFutureWakeTicketSuppressesStall() {
        let thread = WorkThread(
            id: "t1",
            title: "Review",
            createdAt: old,
            updatedAt: old,
            projectId: "projA",
            turns: [
                ThreadTurn(
                    id: "turn1",
                    threadId: "t1",
                    kind: .workerChat,
                    status: .running,
                    createdAt: old,
                    author: .worker,
                    workerId: "model_opus"
                )
            ]
        )
        let pending = PendingItem(
            id: "p1",
            threadId: "t1",
            projectId: "projA",
            title: "Review",
            kind: .workerChat,
            status: .pending,
            createdAt: old,
            updatedAt: old,
            prompt: "Review",
            target: PendingTarget(),
            policy: PendingPolicy(),
            resume: PendingResume(reason: .cooldown, wakeAfter: now.addingTimeInterval(3600))
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [], pendingItems: [pending], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testIdlePendingSuppressesStall() {
        let pending = PendingItem(
            id: "p1",
            threadId: "t1",
            projectId: "projA",
            title: "Later",
            kind: .workerChat,
            status: .pending,
            createdAt: old,
            updatedAt: old,
            prompt: "Later",
            target: PendingTarget(),
            policy: PendingPolicy(),
            resume: nil
        )
        XCTAssertTrue(StalledWorkDetector.suppressedByWakeTicket(pending: [pending], threadId: "t1", runId: nil, now: now))
    }

    func testAuthBlockerSuppressesStall() {
        let pending = PendingItem(
            id: "p1",
            threadId: "t1",
            projectId: "projA",
            title: "Sign in",
            kind: .workerChat,
            status: .pending,
            createdAt: old,
            updatedAt: old,
            prompt: "Sign in",
            target: PendingTarget(),
            policy: PendingPolicy(),
            resume: PendingResume(
                reason: .cooldown,
                capacityObservation: CapacityObservation(
                    kind: .authRequired,
                    source: "claude-code",
                    sourceConfidence: .messageFallback,
                    rawSnippet: "sign in",
                    observedAt: old
                )
            )
        )
        XCTAssertTrue(StalledWorkDetector.suppressedByWakeTicket(pending: [pending], threadId: "t1", runId: nil, now: now))
    }

    func testTerminalTeamRunIsNotStalled() {
        let run = TeamRun(
            id: "run1",
            prompt: "Plan",
            status: .complete,
            createdAt: old,
            threadId: "t1"
        )
        let thread = WorkThread(id: "t1", title: "Plan", createdAt: old, updatedAt: old, projectId: "projA")
        let input = StalledWorkScanInput(threads: [thread], runs: [run], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testFailedTurnIsNotStalled() {
        let thread = WorkThread(
            id: "t1",
            title: "Failed",
            createdAt: old,
            updatedAt: old,
            projectId: "projA",
            turns: [
                ThreadTurn(
                    id: "turn1",
                    threadId: "t1",
                    kind: .workerChat,
                    status: .failed,
                    createdAt: old,
                    completedAt: old,
                    author: .worker,
                    text: "boom",
                    workerId: "model_opus"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testRefreshClearsStaleCandidate() {
        let thread = WorkThread(
            id: "t1",
            title: "Done",
            createdAt: old,
            updatedAt: now,
            projectId: "projA",
            turns: [
                ThreadTurn(
                    id: "turn1",
                    threadId: "t1",
                    kind: .workerChat,
                    status: .done,
                    createdAt: old,
                    completedAt: now,
                    author: .worker,
                    text: "ok",
                    workerId: "model_opus"
                )
            ]
        )
        let turn = thread.turns[0]
        let input = StalledWorkScanInput(threads: [thread], runs: [], pendingItems: [], now: now)
        XCTAssertFalse(StalledWorkDetector.isStillStalledAfterRefresh(thread: thread, turn: turn, run: nil, input: input))
    }
}
