import XCTest
import AllnighterCore
@testable import AllnighterMac

/// RLS-S04 auto-follow: while a worker streams, the LAST turn's text grows without the
/// turn count changing, so the timeline must follow the bottom — but only while the user
/// is already there, never fighting a manual scroll-up.
final class TimelineFollowScrollTests: XCTestCase {

    // MARK: at-bottom gate

    func testAtBottomWhenContentEndIsWithinViewportPlusSlack() {
        // Content bottom just below the viewport bottom but within slack → still following.
        XCTAssertTrue(TimelineScrollPolicy.isAtBottom(contentBottomY: 1000, viewportBottomY: 920, slack: 120))
        // Content bottom at the viewport bottom → at bottom.
        XCTAssertTrue(TimelineScrollPolicy.isAtBottom(contentBottomY: 900, viewportBottomY: 900, slack: 120))
    }

    func testNotAtBottomWhenUserScrolledUp() {
        // User scrolled up: the content bottom is far below the viewport → do not follow.
        XCTAssertFalse(TimelineScrollPolicy.isAtBottom(contentBottomY: 5000, viewportBottomY: 900, slack: 120))
    }

    // MARK: live signal

    private func turn(_ id: String, status: ThreadTurnStatus, text: String?, reasoning: String? = nil) -> ThreadTurn {
        var t = ThreadTurn(id: id, threadId: "th", kind: .workerChat, status: status,
                           createdAt: Date(), author: .worker, text: text)
        t.reasoningText = reasoning
        return t
    }

    private func thread(_ turns: [ThreadTurn]) -> WorkThread {
        WorkThread(id: "th", title: "t", createdAt: Date(), updatedAt: Date(), turns: turns)
    }

    func testLiveSignalGrowsWithRunningTurnText() {
        let a = thread([turn("w1", status: .running, text: "hello")])
        let b = thread([turn("w1", status: .running, text: "hello world", reasoning: "thinking")])
        XCTAssertEqual(TimelineScrollPolicy.liveContentSignal(for: a), 5)
        XCTAssertGreaterThan(TimelineScrollPolicy.liveContentSignal(for: b),
                             TimelineScrollPolicy.liveContentSignal(for: a),
                             "the signal must grow as the running turn streams")
    }

    func testLiveSignalIsZeroOnceSettled() {
        // A settled (done) last turn is not streaming → no follow signal.
        let settled = thread([turn("w1", status: .done, text: "final answer")])
        XCTAssertEqual(TimelineScrollPolicy.liveContentSignal(for: settled), 0)
    }

    // MARK: post-send scroll

    private func userTurn(_ id: String, text: String) -> ThreadTurn {
        ThreadTurn(
            id: id, threadId: "th", kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user, text: text
        )
    }

    func testTurnCountScrollPrefersBottomAfterSendEvenWithUnread() {
        let unreadThread = WorkThread(
            id: "th",
            title: "t",
            createdAt: Date(),
            updatedAt: Date(),
            readCursor: ThreadReadCursor(
                lastReadTurnId: "u1",
                readAt: Date().addingTimeInterval(-60)
            ),
            turns: [
                userTurn("u1", text: "old prompt"),
                turn("w1", status: .done, text: "unread reply"),
                userTurn("u2", text: "just sent"),
            ]
        )
        let action = TimelineScrollPolicy.turnCountScrollAction(
            thread: unreadThread,
            suppressAutoScroll: false,
            forceScrollToBottomAfterSend: true
        )
        XCTAssertEqual(action, .scrollToBottom)
    }

    func testTurnCountScrollUsesFirstUnreadWhenNotAfterSend() {
        let unreadThread = WorkThread(
            id: "th",
            title: "t",
            createdAt: Date(),
            updatedAt: Date(),
            readCursor: ThreadReadCursor(
                lastReadTurnId: "u1",
                readAt: Date().addingTimeInterval(-60)
            ),
            turns: [
                userTurn("u1", text: "old prompt"),
                turn("w1", status: .done, text: "unread reply"),
            ]
        )
        let action = TimelineScrollPolicy.turnCountScrollAction(
            thread: unreadThread,
            suppressAutoScroll: false,
            forceScrollToBottomAfterSend: false
        )
        XCTAssertEqual(action, .scrollToFirstUnread("w1"))
    }
}
