import XCTest
@testable import AllnighterEngine

/// The execution lane is the INVIOLABLE one-at-a-time boundary for Execute orders.
/// These laws fix the two properties that keep it safe: (1) the key is conservative
/// — equivalent dirs share a lane, unknown collapses to one shared lane; (2) the
/// registry never lets two orders hold the same lane at once.
final class ExecutionLaneTests: XCTestCase {

    func testEquivalentDirectoriesShareALane() {
        let a = ExecutionLane.key(workingDirectory: "/Users/me/repo")
        let b = ExecutionLane.key(workingDirectory: "/Users/me/repo/")
        let c = ExecutionLane.key(workingDirectory: "/Users/me/repo/sub/..")
        XCTAssertEqual(a, b, "a trailing slash must not open a second lane")
        XCTAssertEqual(a, c, "a normalizable path must not open a second lane")
    }

    func testDistinctDirectoriesGetDistinctLanes() {
        XCTAssertNotEqual(
            ExecutionLane.key(workingDirectory: "/Users/me/repo-a"),
            ExecutionLane.key(workingDirectory: "/Users/me/repo-b")
        )
    }

    func testUnknownDirectoryCollapsesToOneConservativeLane() {
        // No real dir → all such orders serialize on ONE shared lane (conservative).
        let none = ExecutionLane.key(workingDirectory: nil)
        let blank = ExecutionLane.key(workingDirectory: "   ")
        XCTAssertEqual(none, blank)
        XCTAssertNotEqual(none, ExecutionLane.key(workingDirectory: "/Users/me/repo"))
    }

    func testRegistryAllowsOnlyOneHolderPerLane() async {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(workingDirectory: "/Users/me/repo")

        let first = await reg.acquire(key)
        let second = await reg.acquire(key)
        XCTAssertTrue(first, "the first order acquires the free lane")
        XCTAssertFalse(second, "a second concurrent order on the same lane is refused")

        await reg.release(key)
        let third = await reg.acquire(key)
        XCTAssertTrue(third, "the lane is acquirable again once released")
    }

    func testDistinctLanesAreIndependent() async {
        let reg = ExecutionLaneRegistry()
        let a = ExecutionLane.key(workingDirectory: "/Users/me/repo-a")
        let b = ExecutionLane.key(workingDirectory: "/Users/me/repo-b")
        let gotA = await reg.acquire(a)
        let gotB = await reg.acquire(b)
        XCTAssertTrue(gotA && gotB, "different working dirs run in parallel (RB5: distinct dirs only)")
    }

    /// Concurrency law: under many simultaneous acquires of one lane, exactly one wins.
    func testConcurrentAcquiresElectExactlyOneWinner() async {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(workingDirectory: "/Users/me/repo")
        let wins = await withTaskGroup(of: Bool.self) { group -> Int in
            for _ in 0..<50 { group.addTask { await reg.acquire(key) } }
            var count = 0
            for await won in group where won { count += 1 }
            return count
        }
        XCTAssertEqual(wins, 1, "exactly one of 50 racing orders may hold the lane")
    }
}
