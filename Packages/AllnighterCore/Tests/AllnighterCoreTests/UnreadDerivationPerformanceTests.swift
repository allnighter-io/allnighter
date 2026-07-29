import XCTest
@testable import AllnighterCore

/// PERF-S06 / S03: unread derivation must stay linear in turn count (cursor index
/// resolved once — not O(turns²) via per-candidate `firstIndex`).
final class UnreadDerivationPerformanceTests: XCTestCase {

    private func thread(turnCount: Int) -> WorkThread {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var turns: [ThreadTurn] = [
            ThreadTurn(
                id: "u0", threadId: "t", kind: .userMessage, status: .done,
                createdAt: t0, completedAt: t0, author: .user, text: "start"
            )
        ]
        for i in 1...turnCount {
            let at = t0.addingTimeInterval(Double(i))
            turns.append(ThreadTurn(
                id: "w\(i)", threadId: "t", kind: .workerChat, status: .done,
                createdAt: at, completedAt: at, author: .worker,
                text: "reply \(i)", modelId: "model_opus"
            ))
        }
        return WorkThread(
            id: "t", title: "long", createdAt: t0, updatedAt: t0,
            readCursor: ThreadReadCursor(
                lastReadTurnId: "u0", lastReadTurnCreatedAt: t0, readAt: t0
            ),
            turns: turns
        )
    }

    private func timeUnread(turnCount: Int, iterations: Int) -> CFAbsoluteTime {
        let fixture = thread(turnCount: turnCount)
        // Warm the path once so the timed loop is steady-state.
        _ = UnreadDerivation.unreadTurnIds(thread: fixture)
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            let ids = UnreadDerivation.unreadTurnIds(thread: fixture)
            XCTAssertEqual(ids.count, turnCount)
        }
        return CFAbsoluteTimeGetCurrent() - start
    }

    func testUnreadDerivationIsLinearInTurnCount() {
        let iterations = 30
        let small = timeUnread(turnCount: 200, iterations: iterations)
        let large = timeUnread(turnCount: 800, iterations: iterations)
        // 4× turns. Linear ≈ 4×; quadratic ≈ 16×. Allow headroom for scheduler noise.
        let ratio = large / max(small, 0.000_050)
        XCTAssertLessThan(ratio, 10.0,
                          "unread derivation grew \(String(format: "%.1f", ratio))× from 200→800 turns (want <10×; quadratic ≈16×)")
        // Absolute budget: even 800×30 must stay snappy on CI.
        XCTAssertLessThan(large, 1.0, "800-turn unread derivation took \(large)s for \(iterations) iters")
    }
}
