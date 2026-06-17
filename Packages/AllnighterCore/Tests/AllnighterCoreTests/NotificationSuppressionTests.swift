import XCTest
@testable import AllnighterCore

final class NotificationSuppressionTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 910_000)
    private let t1 = Date(timeIntervalSinceReferenceDate: 910_100)

    func testSuppressesWhenTurnAlreadyRead() {
        var thread = threadWithUnreadWorker()
        _ = try? markReadThroughWorker(&thread)
        let candidate = NotificationCandidate(
            threadId: thread.id, turnId: "w1", event: .turnCompleted,
            threadTitle: thread.title, occurredAt: t1
        )
        XCTAssertTrue(NotificationSuppression.shouldSuppress(
            candidate: candidate,
            thread: thread,
            visibility: NotificationVisibilityContext()
        ))
    }

    func testSuppressesWhenTurnVisibleInActiveWindow() {
        let thread = threadWithUnreadWorker()
        let candidate = NotificationCandidate(
            threadId: thread.id, turnId: "w1", event: .turnCompleted,
            threadTitle: thread.title, occurredAt: t1
        )
        let visibility = NotificationVisibilityContext(
            selectedThreadId: thread.id,
            visibleTurnIdsByThread: [thread.id: ["w1"]],
            isAppActive: true
        )
        XCTAssertTrue(NotificationSuppression.shouldSuppress(
            candidate: candidate,
            thread: thread,
            visibility: visibility
        ))
    }

    func testDoesNotSuppressWhenUnreadAndNotVisible() {
        let thread = threadWithUnreadWorker()
        let candidate = NotificationCandidate(
            threadId: thread.id, turnId: "w1", event: .turnCompleted,
            threadTitle: thread.title, occurredAt: t1
        )
        XCTAssertFalse(NotificationSuppression.shouldSuppress(
            candidate: candidate,
            thread: thread,
            visibility: NotificationVisibilityContext(isAppActive: false)
        ))
    }

    private func threadWithUnreadWorker() -> WorkThread {
        WorkThread(
            id: "t1",
            title: "Test",
            status: .active,
            createdAt: t0,
            updatedAt: t1,
            readCursor: ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0),
            turns: [
                ThreadTurn(
                    id: "u1", threadId: "t1", kind: .userMessage, status: .done,
                    createdAt: t0, completedAt: t0, author: .user, text: "q"
                ),
                ThreadTurn(
                    id: "w1", threadId: "t1", kind: .workerChat, status: .done,
                    createdAt: t1, completedAt: t1, author: .worker, text: "a", workerId: "m"
                ),
            ]
        )
    }

    private func markReadThroughWorker(_ thread: inout WorkThread) throws {
        thread.readCursor = ThreadReadCursor(lastReadTurnId: "w1", lastReadTurnCreatedAt: t1, readAt: t1)
    }
}
