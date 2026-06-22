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
        await registry.waitToAcquire(key)   // holder takes it immediately

        let order = OrderRecorder()
        let w1 = Task { await registry.waitToAcquire(key); await order.record(1) }
        // Give w1 time to enqueue before w2, so arrival order is deterministic.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let w2 = Task { await registry.waitToAcquire(key); await order.record(2) }
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
}

private actor OrderRecorder {
    private(set) var values: [Int] = []
    var isEmpty: Bool { values.isEmpty }
    func record(_ n: Int) { values.append(n) }
}
