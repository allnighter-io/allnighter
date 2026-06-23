import XCTest
@testable import AllnighterEngine

final class RunWriteLockTests: XCTestCase {
    func testNormalizeCollapsesTrailingSlash() {
        XCTAssertEqual(RunWriteLock.normalize("/tmp/repo/"), "/tmp/repo")
        XCTAssertEqual(RunWriteLock.normalize("/tmp/repo"), "/tmp/repo")
    }

    func testKeyIsStableForEquivalentPaths() {
        let a = RunWriteLock.key(repoRoot: "/tmp/repo")
        let b = RunWriteLock.key(repoRoot: "/tmp/repo/")
        XCTAssertEqual(a, b)
    }

    func testRegistryRefusesSecondAcquire() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:test"
        let first = await registry.acquire(key)
        let second = await registry.acquire(key)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        await registry.release(key)
        let third = await registry.acquire(key)
        XCTAssertTrue(third)
    }

    /// FIFO: a free key is granted immediately; a held key suspends `waitToAcquire` until the
    /// holder releases, and waiters are granted in arrival order (one writer at a time).
    func testWaitToAcquireGrantsInFIFOOrder() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:fifo"
        let first = await registry.waitToAcquire(key, timeout: .seconds(5))   // holder takes it immediately
        XCTAssertTrue(first)

        let order = OrderRecorder()
        let w1 = Task { if await registry.waitToAcquire(key, timeout: .seconds(5)) { await order.record(1) } }
        // Give w1 time to enqueue before w2, so arrival order is deterministic.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let w2 = Task { if await registry.waitToAcquire(key, timeout: .seconds(5)) { await order.record(2) } }
        try? await Task.sleep(nanoseconds: 50_000_000)

        let emptyWhileHeld = await order.isEmpty
        XCTAssertTrue(emptyWhileHeld, "both waiters suspend while the key is held")

        await registry.release(key)         // → grants w1
        await w1.value
        await registry.release(key)         // → grants w2
        await w2.value

        let finalOrder = await order.values
        XCTAssertEqual(finalOrder, [1, 2], "waiters run in arrival order")
    }

    /// A wedged holder must not hang later runs forever: a waiter that outlives the timeout
    /// returns `false` (no ownership) while the holder keeps the key.
    func testWaitTimesOutWhenHolderNeverReleases() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:timeout"
        let first = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertTrue(first)

        let granted = await registry.waitToAcquire(key, timeout: .milliseconds(100))
        XCTAssertFalse(granted, "the queued waiter gives up after the timeout")
        let stillHeld = await registry.isHeld(key)
        XCTAssertTrue(stillHeld, "the original holder still owns the key")
    }

    /// A cancelled queued waiter returns `false`, frees its slot, and does NOT block the next
    /// waiter from being granted when the holder releases.
    func testCancelledWaiterUnblocksTheQueue() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:cancel"
        let first = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertTrue(first)

        let cancelledFlag = OrderRecorder()
        let cancelled = Task {
            let got = await registry.waitToAcquire(key, timeout: .seconds(30))
            await cancelledFlag.record(got ? 1 : 0)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel()
        await cancelled.value
        let cancelledResult = await cancelledFlag.values
        XCTAssertEqual(cancelledResult, [0], "cancelled waiter returns false")

        // A fresh waiter still gets granted once the holder releases — the queue isn't wedged.
        let next = Task { await registry.waitToAcquire(key, timeout: .seconds(5)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await registry.release(key)
        let granted = await next.value
        XCTAssertTrue(granted, "the next waiter is granted; a cancelled waiter didn't strand the queue")
    }
}

private actor OrderRecorder {
    private(set) var values: [Int] = []
    var isEmpty: Bool { values.isEmpty }
    func record(_ n: Int) { values.append(n) }
}
