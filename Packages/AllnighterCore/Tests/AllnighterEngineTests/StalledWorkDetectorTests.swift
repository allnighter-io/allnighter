import XCTest
import AgentOSTeam
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
                    modelId: "model_opus"
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
                    modelId: "model_opus"
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

    func testWaitingForVendorIsQuietByDesignWithoutPendingTicket() {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "limited",
            observedAt: old
        )
        let run = TeamRun(
            id: "parked-run",
            prompt: "Continue",
            status: .queued,
            phase: .waitingForVendor,
            createdAt: old,
            mutating: true,
            executionSourceId: "claude_code",
            threadId: "t1",
            blocker: RunBlocker(
                resource: .vendorBackoff,
                quotaScope: "claude_code",
                wakeAfter: now.addingTimeInterval(3_600),
                capacityObservation: observation
            )
        )
        let thread = WorkThread(
            id: "t1",
            title: "Parked",
            createdAt: old,
            updatedAt: old,
            projectId: "projA"
        )
        let input = StalledWorkScanInput(
            threads: [thread],
            runs: [run],
            pendingItems: [],
            now: now
        )
        XCTAssertTrue(StalledWorkDetector.scan(input: input).isEmpty)
        XCTAssertFalse(StalledWorkDetector.isStillStalledAfterRefresh(
            thread: nil,
            turn: nil,
            run: run,
            input: input
        ))
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
                    modelId: "model_opus"
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
                    modelId: "model_opus"
                )
            ]
        )
        let turn = thread.turns[0]
        let input = StalledWorkScanInput(threads: [thread], runs: [], pendingItems: [], now: now)
        XCTAssertFalse(StalledWorkDetector.isStillStalledAfterRefresh(thread: thread, turn: turn, run: nil, input: input))
    }

    func testAdvisoryRunBelowLongThresholdDoesNotStall() {
        let run = TeamRun(
            id: "run-advisory",
            prompt: "READ-ONLY advisory review for CR-07",
            status: .fanningOut,
            answers: [
                TeamAnswer(
                    memberId: "model_glm",
                    modelId: "model_glm",
                    role: "answer",
                    result: WorkerRunResult(status: .running, timing: RunTiming(startedAt: old))
                )
            ],
            createdAt: old,
            threadId: "t1"
        )
        let thread = WorkThread(
            id: "t1",
            title: "CR-07",
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
                    text: "Reviewing...",
                    modelId: "model_glm",
                    runId: "run-advisory"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [run], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertTrue(episodes.isEmpty, "33 min idle advisory run should stay below 90 min threshold")
    }

    func testAdvisoryRunPastLongThresholdStalls() {
        let veryOld = Date(timeIntervalSince1970: 1_699_994_600) // 5400s (~90 min) ago
        let run = TeamRun(
            id: "run-advisory",
            prompt: "READ-ONLY advisory review for CR-07",
            status: .fanningOut,
            answers: [
                TeamAnswer(
                    memberId: "model_glm",
                    modelId: "model_glm",
                    role: "answer",
                    result: WorkerRunResult(status: .running, timing: RunTiming(startedAt: veryOld))
                )
            ],
            createdAt: veryOld,
            threadId: "t1"
        )
        let thread = WorkThread(
            id: "t1",
            title: "CR-07",
            createdAt: veryOld,
            updatedAt: veryOld,
            projectId: "projA",
            turns: [
                ThreadTurn(
                    id: "turn1",
                    threadId: "t1",
                    kind: .workerChat,
                    status: .running,
                    createdAt: veryOld,
                    author: .worker,
                    modelId: "model_glm",
                    runId: "run-advisory"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [run], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        let workerEpisodes = episodes.filter { $0.targetKind == .workerTurn }
        XCTAssertEqual(workerEpisodes.count, 1)
        XCTAssertEqual(workerEpisodes[0].thresholdSeconds, 90 * 60)
        XCTAssertEqual(workerEpisodes[0].reason, StallReason.runningNoProgress)
    }

    func testDefaultChatStillStallsAtDefaultThreshold() {
        let thread = WorkThread(
            id: "t1",
            title: "Chat",
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
                    text: "Thinking...",
                    modelId: "model_opus"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].thresholdSeconds, 30 * 60)
    }

    func testLinkedRunHeartbeatResetsStallClock() {
        let recentRunActivity = now.addingTimeInterval(-600) // 10 min ago
        let run = TeamRun(
            id: "run1",
            prompt: "Build feature",
            status: .fanningOut,
            answers: [
                TeamAnswer(
                    memberId: "model_opus",
                    modelId: "model_opus",
                    role: "answer",
                    result: WorkerRunResult(status: .running, timing: RunTiming(startedAt: recentRunActivity))
                )
            ],
            createdAt: old,
            threadId: "t1"
        )
        let thread = WorkThread(
            id: "t1",
            title: "Build",
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
                    modelId: "model_opus",
                    runId: "run1"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [run], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertTrue(episodes.isEmpty, "recent run worker activity should reset stall clock")
    }

    func testQueuedTurnWaitingOnActiveRunDoesNotStall() {
        let run = TeamRun(
            id: "run1",
            prompt: "Build feature",
            status: .fanningOut,
            answers: [
                TeamAnswer(
                    memberId: "model_opus",
                    modelId: "model_opus",
                    role: "answer",
                    result: WorkerRunResult(status: .running, timing: RunTiming(startedAt: old))
                )
            ],
            createdAt: old,
            threadId: "t1"
        )
        let thread = WorkThread(
            id: "t1",
            title: "Build",
            createdAt: old,
            updatedAt: old,
            projectId: "projA",
            turns: [
                ThreadTurn(
                    id: "turn1",
                    threadId: "t1",
                    kind: .workerChat,
                    status: .queued,
                    createdAt: old,
                    author: .worker,
                    modelId: "model_opus",
                    runId: "run1"
                )
            ]
        )
        let input = StalledWorkScanInput(threads: [thread], runs: [run], pendingItems: [], now: now)
        let episodes = StalledWorkDetector.scan(input: input)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testSliceIdPrefixUsesLongThreshold() {
        XCTAssertTrue(
            StalledWorkDetector.isLongRunningWorkerContext(
                run: TeamRun(
                    id: "slice_CR-07_abc",
                    prompt: "advisory review CR-07: stalled detector",
                    status: .draft,
                    createdAt: old
                )
            )
        )
    }
}
