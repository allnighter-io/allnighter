import XCTest
@testable import AllnighterCore

final class NotificationCandidateDetectionTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 900_000)

    func testColdStartEmitsNoCandidates() {
        let after = NotificationCandidateDetection.snapshots(from: [sampleThread(workerStatus: .done)])
        let candidates = NotificationCandidateDetection.candidates(before: nil, after: after, now: now)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testWorkerReplyTransitionEmitsCompleted() {
        let beforeThread = sampleThread(workerStatus: .running)
        let afterThread = sampleThread(workerStatus: .done)
        let before = NotificationCandidateDetection.snapshots(from: [beforeThread])
        let after = NotificationCandidateDetection.snapshots(from: [afterThread])
        let candidates = NotificationCandidateDetection.candidates(before: before, after: after, now: now)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].event, .turnCompleted)
        XCTAssertEqual(candidates[0].turnId, "w1")
    }

    func testFailedWorkerEmitsFailedAndNeedsAttention() {
        let beforeThread = sampleThread(workerStatus: .running)
        let afterThread = sampleThread(workerStatus: .failed)
        let before = NotificationCandidateDetection.snapshots(from: [beforeThread])
        let after = NotificationCandidateDetection.snapshots(from: [afterThread])
        let candidates = NotificationCandidateDetection.candidates(before: before, after: after, now: now)
        XCTAssertTrue(candidates.contains { $0.event == .turnFailed })
        XCTAssertTrue(candidates.contains { $0.event == .threadNeedsAttention })
    }

    func testRelayEscalatedTransitionEmitsRelayNeedsAnswerWithoutDuplicateAttention() {
        var beforeThread = sampleThread(workerStatus: .done)
        beforeThread.turns = [userTurn()]
        var afterThread = sampleThread(workerStatus: .done)
        afterThread.turns = [userTurn(), relayEscalatedTurn()]
        let before = NotificationCandidateDetection.snapshots(from: [beforeThread])
        let after = NotificationCandidateDetection.snapshots(from: [afterThread])
        let candidates = NotificationCandidateDetection.candidates(before: before, after: after, now: now)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].event, .relayNeedsAnswer)
        XCTAssertEqual(candidates[0].turnId, "relay_escalate1")
        XCTAssertFalse(candidates.contains { $0.event == .threadNeedsAttention })
    }

    func testRelayStoppedLandedTurnEmitsRelayStopped() {
        var beforeThread = sampleThread(workerStatus: .done)
        beforeThread.turns = [userTurn()]
        var afterThread = sampleThread(workerStatus: .done)
        afterThread.turns = [userTurn(), relayStoppedTurn()]
        let before = NotificationCandidateDetection.snapshots(from: [beforeThread])
        let after = NotificationCandidateDetection.snapshots(from: [afterThread])
        let candidates = NotificationCandidateDetection.candidates(before: before, after: after, now: now)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].event, .relayStopped)
        XCTAssertEqual(candidates[0].turnId, "relay_stopped")
    }

    func testRelayStoppedColdLoadEmitsNoCandidate() {
        var afterThread = sampleThread(workerStatus: .done)
        afterThread.turns = [userTurn(), relayStoppedTurn()]
        let after = NotificationCandidateDetection.snapshots(from: [afterThread])
        let candidates = NotificationCandidateDetection.candidates(before: nil, after: after, now: now)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testRelayStreamStallEmitsOnceOnTransition() {
        let before = ["relay_1": RelayStreamNotificationSnapshot(
            loopId: "relay_1", threadTitle: "Smoke", devModelId: "model_dev", streamSilenceWarning: false
        )]
        let after = ["relay_1": RelayStreamNotificationSnapshot(
            loopId: "relay_1", threadTitle: "Smoke", devModelId: "model_dev", streamSilenceWarning: true
        )]
        let candidates = NotificationCandidateDetection.relayStreamCandidates(
            before: before, after: after, now: now
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].event, .relayStreamStalled)
    }

    func testLoopParkCandidatesEmitParkAndResumeOnTransition() {
        let before = ["relay_park": LoopParkNotificationSnapshot(
            loopId: "relay_park",
            threadTitle: "QABC park",
            devModelId: "model_dev",
            parked: false
        )]
        let parked = ["relay_park": LoopParkNotificationSnapshot(
            loopId: "relay_park",
            threadTitle: "QABC park",
            devModelId: "model_dev",
            parked: true,
            wakeAfter: now.addingTimeInterval(600),
            source: "claude_code"
        )]
        let parkCandidates = NotificationCandidateDetection.loopParkCandidates(
            before: before, after: parked, now: now
        )
        XCTAssertEqual(parkCandidates.count, 1)
        XCTAssertEqual(parkCandidates[0].event, .loopParked)
        XCTAssertEqual(parkCandidates[0].vendorDisplayName, "Claude")
        XCTAssertEqual(parkCandidates[0].wakeAfter, now.addingTimeInterval(600))

        let resumed = ["relay_park": LoopParkNotificationSnapshot(
            loopId: "relay_park",
            threadTitle: "QABC park",
            devModelId: "model_dev",
            parked: false
        )]
        let resumeCandidates = NotificationCandidateDetection.loopParkCandidates(
            before: parked, after: resumed, now: now
        )
        XCTAssertEqual(resumeCandidates.count, 1)
        XCTAssertEqual(resumeCandidates[0].event, .loopResumed)

        let cold = NotificationCandidateDetection.loopParkCandidates(
            before: nil, after: parked, now: now
        )
        XCTAssertTrue(cold.isEmpty)
    }

    func testTeamRunCompleteEvent() {
        var before = sampleThread(workerStatus: .done)
        var after = sampleThread(workerStatus: .done)
        before.turns = [userTurn()]
        after.turns = [userTurn(), teamTurn(status: .running)]
        let beforeSnap = NotificationCandidateDetection.snapshots(from: [before])
        var afterRunning = after
        afterRunning.turns = [userTurn(), teamTurn(status: .running)]
        var afterDone = after
        afterDone.turns = [userTurn(), teamTurn(status: .done)]
        let mid = NotificationCandidateDetection.snapshots(from: [afterRunning])
        let done = NotificationCandidateDetection.snapshots(from: [afterDone])
        _ = NotificationCandidateDetection.candidates(before: beforeSnap, after: mid, now: now)
        let candidates = NotificationCandidateDetection.candidates(before: mid, after: done, now: now)
        XCTAssertEqual(candidates.first?.event, .teamRunCompleted)
    }

    private func sampleThread(workerStatus: ThreadTurnStatus) -> WorkThread {
        WorkThread(
            id: "t1",
            title: "Notifications strategy",
            status: .active,
            createdAt: now,
            updatedAt: now,
            readCursor: .empty(at: now),
            turns: [userTurn(), workerTurn(status: workerStatus)]
        )
    }

    private func userTurn() -> ThreadTurn {
        ThreadTurn(
            id: "u1", threadId: "t1", kind: .userMessage, status: .done,
            createdAt: now, completedAt: now, author: .user, text: "hi"
        )
    }

    private func workerTurn(status: ThreadTurnStatus) -> ThreadTurn {
        ThreadTurn(
            id: "w1", threadId: "t1", kind: .workerChat, status: status,
            createdAt: now, completedAt: status.isTerminal ? now : nil,
            author: .worker, text: "reply", modelId: "model_opus"
        )
    }

    private func teamTurn(status: ThreadTurnStatus) -> ThreadTurn {
        ThreadTurn(
            id: "team1", threadId: "t1", kind: .teamRun, status: status,
            createdAt: now, completedAt: status.isTerminal ? now : nil,
            author: .worker, runId: "run1"
        )
    }

    private func relayEscalatedTurn() -> ThreadTurn {
        ThreadTurn(
            id: "relay_escalate1", threadId: "t1", kind: .systemEvent, status: .running,
            createdAt: now, author: .system, text: "PM escalated (round 1).",
            systemEvent: .relayEscalated
        )
    }

    private func relayStoppedTurn() -> ThreadTurn {
        ThreadTurn(
            id: "relay_stopped", threadId: "t1", kind: .systemEvent, status: .done,
            createdAt: now, completedAt: now, author: .system, text: "Relay stopped.",
            systemEvent: .relayStopped
        )
    }
}
