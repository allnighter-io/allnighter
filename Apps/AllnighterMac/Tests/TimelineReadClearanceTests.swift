import XCTest
import AllnighterCore
@testable import AllnighterMac

final class TimelineReadClearanceTests: XCTestCase {

    func testWorkerChatCountsTowardReadClear() {
        let turn = ThreadTurn(
            id: "w", threadId: "a", kind: .workerChat, status: .done,
            createdAt: .now, completedAt: .now, author: .worker, text: "hi"
        )
        XCTAssertTrue(TimelineReadClearance.countsTowardReadClear(turn))
    }

    func testTeamRunDoesNotCountTowardReadClear() {
        let turn = ThreadTurn(
            id: "t", threadId: "a", kind: .teamRun, status: .done,
            createdAt: .now, completedAt: .now, author: .worker
        )
        XCTAssertFalse(TimelineReadClearance.countsTowardReadClear(turn))
    }

    func testUnreadEligibleRichTurnExcludedFromVisibleReadClearList() {
        let thread = WorkThread(
            id: "a", title: "t", status: .active, createdAt: .now, updatedAt: .now,
            readCursor: ThreadReadCursor(lastReadTurnId: "u", lastReadTurnCreatedAt: .now, readAt: .now),
            turns: [
                ThreadTurn(
                    id: "u", threadId: "a", kind: .userMessage, status: .done,
                    createdAt: .now, completedAt: .now, author: .user, text: "q"
                ),
                ThreadTurn(
                    id: "w", threadId: "a", kind: .workerChat, status: .done,
                    createdAt: .now, completedAt: .now, author: .worker, text: "r", modelId: "m"
                ),
                ThreadTurn(
                    id: "b", threadId: "a", kind: .teamRun, status: .done,
                    createdAt: .now, completedAt: .now, author: .worker, runId: "run"
                ),
            ]
        )
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 600)
        let frames: [String: CGRect] = [
            "u": CGRect(x: 0, y: 0, width: 400, height: 80),
            "w": CGRect(x: 0, y: 90, width: 400, height: 120),
            "b": CGRect(x: 0, y: 220, width: 400, height: 100),
        ]
        let visible = TimelineReadClearance.visibleTurnIdsForReadClear(
            thread: thread, frames: frames, viewport: viewport
        )
        XCTAssertEqual(visible, ["u", "w"])
        XCTAssertFalse(visible.contains("b"))
    }
}
