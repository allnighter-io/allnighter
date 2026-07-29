import XCTest
import AllnighterCore
@testable import AllnighterMac

/// PERF-S06 / S02: rail search and row facts use precomputed summaries — not a
/// per-keystroke walk of every turn on every full `WorkThread`.
@MainActor
final class ThreadRailPerformanceTests: XCTestCase {

    func testRailRowsUseSummariesWithoutTurnTextScans() {
        let now = Date()
        let huge = String(repeating: "needle-in-haystack ", count: 5_000)
        let thread = WorkThread(
            id: "rail-1", title: "Rate limiter", status: .active,
            createdAt: now, updatedAt: now,
            readCursor: .empty(at: now),
            turns: [
                ThreadTurn(
                    id: "u1", threadId: "rail-1", kind: .userMessage, status: .done,
                    createdAt: now, completedAt: now, author: .user, text: "hi"
                ),
                ThreadTurn(
                    id: "w1", threadId: "rail-1", kind: .workerChat, status: .done,
                    createdAt: now, completedAt: now, author: .worker,
                    text: huge, modelId: "model_opus"
                ),
            ]
        )
        let row = ThreadsPresenter.railRow(from: thread)
        XCTAssertTrue(row.searchText.contains("needle-in-haystack"))
        XCTAssertTrue(row.matchesSearch("NEEDLE"))
        XCTAssertFalse(row.matchesSearch("missing-token"))
        // matchesSearch only consults the precomputed summary string — it does not
        // take a WorkThread, so rail filtering cannot re-walk turns at query time.
        XCTAssertTrue(row.matchesSearch("rate"))
    }
}
