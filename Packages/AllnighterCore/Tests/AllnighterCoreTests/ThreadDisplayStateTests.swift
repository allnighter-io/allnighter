import XCTest
@testable import AllnighterCore

final class ThreadDisplayStateTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)

    private func thread(_ turns: [ThreadTurn] = []) -> WorkThread {
        var t = WorkThread(id: "t1", title: "t", createdAt: epoch, updatedAt: epoch)
        t.turns = turns
        return t
    }

    private func turn(status: ThreadTurnStatus, author: TurnAuthor) -> ThreadTurn {
        ThreadTurn(id: "turn_\(status.rawValue)_\(author.rawValue)", threadId: "t1",
                   kind: .workerChat, status: status, createdAt: epoch, author: author,
                   text: author == .worker ? "reply" : nil,
                   workerId: author == .worker ? "model_opus" : nil)
    }

    func testNewChatIsDraft() {
        let s = ThreadStateDerivation.displayState(thread: thread([]), hasPendingItem: false)
        XCTAssertEqual(s, .draft)
        XCTAssertTrue(thread([]).hasNeverRun)
    }

    func testRunningWinsOverEverything() {
        // A live turn is "the only motion" — it beats a queued pending item.
        let s = ThreadStateDerivation.displayState(
            thread: thread([turn(status: .running, author: .worker)]), hasPendingItem: true)
        XCTAssertEqual(s, .running)
    }

    func testArmedAndNotRunningIsPending() {
        // Has dispatched work (so not draft), not running, but armed in the queue.
        let s = ThreadStateDerivation.displayState(
            thread: thread([turn(status: .done, author: .worker)]), hasPendingItem: true)
        XCTAssertEqual(s, .pending)
    }

    func testDispatchedWorkClearsDraft() {
        XCTAssertFalse(thread([turn(status: .done, author: .worker)]).hasNeverRun)
    }

    func testEnumIsStableRawValues() {
        XCTAssertEqual(ThreadDisplayState.allCases.map(\.rawValue),
                       ["draft", "pending", "running", "replied", "idle"])
    }
}
