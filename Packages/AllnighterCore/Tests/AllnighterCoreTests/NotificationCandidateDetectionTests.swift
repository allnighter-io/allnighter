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
            author: .worker, text: "reply", workerId: "model_opus"
        )
    }

    private func teamTurn(status: ThreadTurnStatus) -> ThreadTurn {
        ThreadTurn(
            id: "team1", threadId: "t1", kind: .teamRun, status: status,
            createdAt: now, completedAt: status.isTerminal ? now : nil,
            author: .worker, runId: "run1"
        )
    }
}
