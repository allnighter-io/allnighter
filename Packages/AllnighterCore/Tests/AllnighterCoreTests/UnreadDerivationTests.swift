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
            modelId: author == .worker ? "model_opus" : nil,
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

    // MARK: - ATL-S05 relay attention quieting

    func testRelayEscalatedNeedsAttention() {
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let wt = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertEqual(
            UnreadDerivation.railAttention(thread: wt, relayStatus: .escalated),
            .needsYou
        )
        XCTAssertTrue(UnreadDerivation.unreadNeedsAttention(thread: wt, relayStatus: .escalated))
        XCTAssertEqual(
            ThreadStateDerivation.displayState(thread: wt, hasPendingItem: false, relayStatus: .escalated),
            .replied
        )
    }

    func testRelayAwaitingPMNeedsAttention() {
        let wt = thread(turns: [turn("w1", createdAt: t1, completedAt: t1)], cursor: .empty(at: t0))
        XCTAssertEqual(
            UnreadDerivation.railAttention(thread: wt, relayStatus: .awaitingPM),
            .needsYou
        )
        XCTAssertTrue(UnreadDerivation.unreadNeedsAttention(thread: wt, relayStatus: .awaitingPM))
    }

    func testRelayRunningHasNoAttentionColour() {
        let w1 = turn("w1", status: .running, createdAt: t1)
        let wt = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertEqual(
            UnreadDerivation.railAttention(thread: wt, relayStatus: .running),
            .none
        )
        XCTAssertFalse(UnreadDerivation.unreadNeedsAttention(thread: wt, relayStatus: .running))
        XCTAssertEqual(
            ThreadStateDerivation.displayState(thread: wt, hasPendingItem: false, relayStatus: .running),
            .running
        )
    }

    func testRelayDoneHasNoAttentionColour() {
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let wt = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertTrue(UnreadDerivation.hasUnread(thread: wt))
        XCTAssertEqual(
            UnreadDerivation.railAttention(thread: wt, relayStatus: .done),
            .none
        )
        XCTAssertFalse(UnreadDerivation.unreadNeedsAttention(thread: wt, relayStatus: .done))
        XCTAssertEqual(
            ThreadStateDerivation.displayState(thread: wt, hasPendingItem: false, relayStatus: .done),
            .idle
        )
    }

    /// The actual ATL-S05 bug: founder-stopped historical rows kept amber forever
    /// because unread turns still lit the rail. Terminal status must win.
    func testRelayStoppedWithUnreadTurnsHasNoAttentionColour() {
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let openEscalation = turn(
            "esc", kind: .systemEvent, status: .running, author: .system,
            createdAt: t2, systemEvent: .relayEscalated
        )
        let wt = thread(turns: [w1, openEscalation], cursor: .empty(at: t0))
        XCTAssertTrue(UnreadDerivation.hasUnread(thread: wt))
        XCTAssertTrue(wt.needsAttention) // turn-level still true; rail must not follow it
        XCTAssertEqual(
            UnreadDerivation.railAttention(thread: wt, relayStatus: .stopped),
            .none
        )
        XCTAssertFalse(UnreadDerivation.unreadNeedsAttention(thread: wt, relayStatus: .stopped))
        // Open escalation would look "running" without the relay gate — product is quiet.
        XCTAssertEqual(
            ThreadStateDerivation.displayState(thread: wt, hasPendingItem: false, relayStatus: .stopped),
            .running
        )
    }

    func testNonRelayUnreadBehaviourUnchanged() {
        let w1 = turn("w1", createdAt: t1, completedAt: t1)
        let wt = thread(turns: [w1], cursor: .empty(at: t0))
        XCTAssertEqual(UnreadDerivation.railAttention(thread: wt), .ordinaryUnread)
        XCTAssertFalse(UnreadDerivation.unreadNeedsAttention(thread: wt))
        XCTAssertEqual(
            ThreadStateDerivation.displayState(thread: wt, hasPendingItem: false),
            .replied
        )

        let failed = turn("f1", status: .failed, createdAt: t1, completedAt: t1)
        let failedThread = thread(turns: [failed], cursor: .empty(at: t0))
        XCTAssertTrue(UnreadDerivation.unreadNeedsAttention(thread: failedThread))
        XCTAssertEqual(UnreadDerivation.railAttention(thread: failedThread), .ordinaryUnread)
    }

    func testNonRelayRunningBeatsOrdinaryUnread() {
        let done = turn("w1", createdAt: t1, completedAt: t1)
        let live = turn("w2", status: .running, createdAt: t2)
        let wt = thread(turns: [done, live], cursor: .empty(at: t0))
        XCTAssertEqual(UnreadDerivation.railAttention(thread: wt), .ordinaryUnread)
        XCTAssertEqual(
            ThreadStateDerivation.displayState(thread: wt, hasPendingItem: false),
            .running
        )
    }

    func testLoopsNeedingYouRollup() {
        XCTAssertNil(UnreadDerivation.loopsNeedingYouLabel(count: 0))
        XCTAssertEqual(UnreadDerivation.loopsNeedingYouLabel(count: 1), "1 loop needs you")
        XCTAssertEqual(UnreadDerivation.loopsNeedingYouLabel(count: 3), "3 loops need you")
        XCTAssertEqual(
            UnreadDerivation.loopsNeedingYouCount(statuses: [.escalated, .running, .awaitingPM, .stopped, .done]),
            2
        )
    }

    // MARK: - Eligibility matrix

    func testTeamRunDoneIsUnreadEligible() {
        let team = turn("tr1", kind: .teamRun, status: .done, author: .system, createdAt: t1, completedAt: t1)
        XCTAssertTrue(UnreadDerivation.isUnreadEligible(team))
    }

    func testMutatingRunDoneIsUnreadEligible() {
        let run = turn("mr1", kind: .mutatingRun, status: .done, author: .worker, createdAt: t1, completedAt: t1)
        XCTAssertTrue(UnreadDerivation.isUnreadEligible(run))
    }
}
