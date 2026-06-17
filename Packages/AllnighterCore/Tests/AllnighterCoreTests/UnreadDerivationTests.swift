import XCTest
@testable import AllnighterCore

/// Pure unread derivation fixtures for 06_Unread_Message_Light (UNR-S01).
final class UnreadDerivationTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)
    private let t3 = Date(timeIntervalSince1970: 4_000)

    private func thread(
        turns: [ThreadTurn],
        cursor: ThreadReadCursor? = nil
    ) -> WorkThread {
        WorkThread(
            id: "t1", title: "T", createdAt: t0, updatedAt: t0,
            readCursor: cursor, turns: turns
        )
    }

    private func turn(
        _ id: String,
        kind: ThreadTurnKind = .workerChat,
        status: ThreadTurnStatus = .done,
        author: TurnAuthor = .worker,
        createdAt: Date? = nil,
        completedAt: Date? = nil,
        systemEvent: SystemEventKind? = nil,
        supersedesTurnId: String? = nil
    ) -> ThreadTurn {
        ThreadTurn(
            id: id,
            threadId: "t1",
            kind: kind,
            status: status,
            createdAt: createdAt ?? t1,
            completedAt: completedAt,
            author: author,
            text: author == .worker ? "reply" : "msg",
            workerId: author == .worker ? "model_opus" : nil,
            supersedesTurnId: supersedesTurnId,
            systemEvent: systemEvent
        )
    }

    private func cursor(
        through turnId: String?,
        createdAt: Date? = nil,
        readAt: Date = Date(timeIntervalSince1970: 1_500)
    ) -> ThreadReadCursor {
        ThreadReadCursor(
            lastReadTurnId: turnId,
            lastReadTurnCreatedAt: createdAt ?? (turnId == nil ? nil : t1),
            readAt: readAt
        )
    }

    // MARK: - Legacy / baseline

    func testLegacyNoCursorHasNoUnread() {
        let thread = thread(turns: [turn("w1")], cursor: nil)
        XCTAssertFalse(UnreadDerivation.hasUnread(thread: thread))
        XCTAssertTrue(UnreadDerivation.unreadTurnIds(thread: thread).isEmpty)
    }

    func testNewEmptyCursorHasNoUnread() {
        let thread = thread(turns: [], cursor: .empty(at: t0))
        XCTAssertFalse(thread.hasUnread)
    }

    // MARK: - Basic unread

    func testWorkerReplyAfterCursorIsUnread() {
        let u1 = turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0)
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let thread = thread(turns: [u1, w1], cursor: cursor(through: "u1", createdAt: t0, readAt: t0))
        XCTAssertTrue(thread.hasUnread)
        XCTAssertEqual(thread.firstUnreadTurnId, "w1")
    }

    func testUserSendDoesNotImplicitlyClearEarlierUnreadWorker() {
        let u1 = turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0)
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let u2 = turn("u2", kind: .userMessage, status: .done, author: .user, createdAt: t2)
        // Cursor remains at u1 because markRead must not advance through u2 while w1 is unseen.
        let thread = thread(turns: [u1, w1, u2], cursor: cursor(through: "u1", createdAt: t0, readAt: t0))
        XCTAssertTrue(thread.hasUnread)
        XCTAssertEqual(thread.firstUnreadTurnId, "w1")
    }

    // MARK: - Landed-after-read / out-of-order

    func testOutOfOrderCompletionBeforeCursorLandsAfterRead() {
        let wRunning = turn("w1", status: .running, createdAt: t0)
        let u1 = turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t1)
        var wDone = wRunning
        wDone.status = .done
        wDone.completedAt = t3
        let thread = thread(
            turns: [wDone, u1],
            cursor: cursor(through: "u1", createdAt: t1, readAt: t2)
        )
        XCTAssertTrue(thread.hasUnread)
        XCTAssertEqual(thread.firstUnreadTurnId, "w1")
    }

    // MARK: - Exclusions

    func testUserMessageNeverUnread() {
        let u1 = turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t1)
        let thread = thread(turns: [u1], cursor: .empty(at: t0))
        XCTAssertFalse(thread.hasUnread)
    }

    func testRunningWorkerNotUnread() {
        let w1 = turn("w1", status: .running, createdAt: t1)
        let thread = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertFalse(thread.hasUnread)
    }

    func testCancelledTurnExcluded() {
        let w1 = turn("w1", status: .cancelled, createdAt: t1)
        let thread = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertFalse(thread.hasUnread)
    }

    func testSupersededTurnExcluded() {
        let wOld = turn("w-old", status: .failed, createdAt: t1)
        let wNew = turn("w-new", status: .done, createdAt: t2, supersedesTurnId: "w-old")
        let thread = thread(turns: [wOld, wNew], cursor: .empty(at: t0))
        XCTAssertFalse(UnreadDerivation.unreadTurnIds(thread: thread).contains("w-old"))
    }

    func testMigrationSystemEventNotUnread() {
        let note = turn("s1", kind: .systemEvent, status: .done, author: .system,
                        createdAt: t1, systemEvent: .migrationImported)
        let thread = thread(turns: [note], cursor: .empty(at: t0))
        XCTAssertFalse(thread.hasUnread)
    }

    func testBlockingSystemEventUnreadWhileOpen() {
        let note = turn("s1", kind: .systemEvent, status: .running, author: .system,
                        createdAt: t1, systemEvent: .signInRequired)
        let thread = thread(turns: [note], cursor: .empty(at: t0))
        XCTAssertTrue(thread.hasUnread)
    }

    // MARK: - Timestamp fallback

    func testMissingCursorIdUsesTimestampFallback() {
        let u1 = turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0)
        let w1 = turn("w1", createdAt: t2, completedAt: t2)
        let thread = thread(
            turns: [u1, w1],
            cursor: ThreadReadCursor(lastReadTurnId: "gone", lastReadTurnCreatedAt: t1, readAt: t1)
        )
        XCTAssertTrue(thread.hasUnread)
        XCTAssertEqual(thread.firstUnreadTurnId, "w1")
    }

    func testIdenticalCreatedAtTieDoesNotMatchFallback() {
        let u1 = turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0)
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let thread = thread(
            turns: [u1, w1],
            cursor: ThreadReadCursor(lastReadTurnId: nil, lastReadTurnCreatedAt: t1, readAt: t2)
        )
        XCTAssertFalse(thread.hasUnread)
    }

    // MARK: - Attention axis

    func testFailedWorkerUnreadAndAttention() {
        let w1 = turn("w1", status: .failed, createdAt: t1, completedAt: t1)
        let thread = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertTrue(thread.hasUnread)
        XCTAssertTrue(thread.unreadNeedsAttention)
        XCTAssertTrue(thread.needsAttention)
    }

    func testArchivedThreadCanBeUnread() {
        var thread = thread(turns: [turn("w1", createdAt: t1, completedAt: t1)], cursor: .empty(at: t0))
        thread.status = .archived
        XCTAssertTrue(thread.hasUnread)
    }

    // MARK: - Eligibility matrix

    func testTeamRunDoneIsUnreadEligible() {
        let team = turn("tr1", kind: .teamRun, status: .done, author: .system, createdAt: t1, completedAt: t1)
        XCTAssertTrue(UnreadDerivation.isUnreadEligible(team))
    }

    func testWorkOrderNeverUnreadEligible() {
        let wo = turn("wo1", kind: .workOrder, status: .done, author: .user, createdAt: t1)
        XCTAssertFalse(UnreadDerivation.isUnreadEligible(wo))
    }
}
