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

    func testSymlinkAliasProducesSameKey() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("runlock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let alias = base.deletingLastPathComponent()
            .appendingPathComponent("runlock-alias-\(UUID().uuidString)", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: base)

        let directKey = RunWriteLock.key(repoRoot: base.path)
        let aliasKey = RunWriteLock.key(repoRoot: alias.path)
        XCTAssertEqual(directKey, aliasKey)
    }

    func testVarAndPrivateVarCollapseToSameKey() {
        let viaVar = RunWriteLock.key(repoRoot: "/var/tmp")
        let viaPrivateVar = RunWriteLock.key(repoRoot: "/private/var/tmp")
        XCTAssertEqual(viaVar, viaPrivateVar)
    }

    // MARK: - RLR-S02b root isolation (RLR-L4 / Works Test 3)

    /// Probe verdict, frozen as a regression: on the case-insensitive macOS FS,
    /// `normalize`'s `resolvingSymlinksInPath` already canonicalizes the case of an
    /// EXISTING path to its real on-disk casing, so two case-spellings of one root
    /// collapse to one lane key. (No case-folding was added to `normalize` — doing so
    /// would re-key in-flight paths against the frozen cross-process key formula.)
    func testCaseVariantOfExistingRootSharesOneLockKey() throws {
        let name = "RunLockCase-\(UUID().uuidString.prefix(8))"
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(name), isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // Alternate spelling: last component upper-cased. Same inode (case-insensitive FS).
        let variant = base.deletingLastPathComponent()
            .appendingPathComponent(base.lastPathComponent.uppercased(), isDirectory: true).path
        XCTAssertNotEqual(variant, base.path, "the two spellings must differ byte-for-byte")
        XCTAssertEqual(RunWriteLock.normalize(variant), RunWriteLock.normalize(base.path),
                       "normalize resolves both spellings to the real on-disk casing")
        XCTAssertEqual(RunWriteLock.key(repoRoot: variant), RunWriteLock.key(repoRoot: base.path),
                       "two case-spellings of one existing root share one lane key")
    }

    /// True different roots never collide — their keys differ, so they never serialize.
    func testTrueDifferentRootsProduceDifferentKeys() {
        let a = RunWriteLock.key(repoRoot: "/tmp/project-a")
        let b = RunWriteLock.key(repoRoot: "/tmp/project-b")
        XCTAssertNotEqual(a, b, "distinct roots must map to distinct lane keys")
    }

    /// Risk #2 (frozen cross-process key formula): a byte-identical spelling must map to
    /// exactly the key it produced before S02b. Case-canonicalization is a property of the
    /// FS for existing paths only; a NON-existent path keeps today's byte-preserving
    /// behavior (no re-keying of in-flight foreign holders).
    func testNonExistentPathKeyIsByteIdenticalFallback() {
        let canonical = "/tmp/does-not-exist-\(UUID().uuidString)"
        // Same spelling → same key (the frozen fallback: fnv1a over the standardized string).
        XCTAssertEqual(RunWriteLock.key(repoRoot: canonical), RunWriteLock.key(repoRoot: canonical))
        // A case-variant of a NON-existent path is NOT force-folded (no key formula change),
        // so it stays a distinct key — we did not re-key existing canonical spellings.
        let variant = canonical.uppercased()
        XCTAssertNotEqual(RunWriteLock.normalize(variant), RunWriteLock.normalize(canonical),
                          "a non-existent path is not case-folded — the frozen fallback is preserved")
    }

    func testRegistryRefusesSecondAcquire() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:test"
        let first = await registry.acquire(key)
        let second = await registry.acquire(key)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        await registry.release(key, token: first!)
        let third = await registry.acquire(key)
        XCTAssertNotNil(third)
    }

    func testStrayReleaseDoesNotFreeLockOrHandOff() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:stray"
        let otherKey = "v1:other"
        let holder = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertNotNil(holder)
        let otherToken = await registry.acquire(otherKey)
        XCTAssertNotNil(otherToken)

        await registry.release(key, token: otherToken!)

        let stillHeld = await registry.isHeld(key)
        XCTAssertTrue(stillHeld, "stray release must not free the lock")

        let waiter = Task { await registry.waitToAcquire(key, timeout: .milliseconds(100)) }
        let timedOut = await waiter.value
        XCTAssertNil(timedOut, "stray release must not hand off to a waiter")
        await registry.release(key, token: holder!)
        await registry.release(otherKey, token: otherToken!)
    }

    func testDoubleReleaseIsSafe() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:double"
        let holder = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertNotNil(holder)

        let granted = OrderRecorder()
        let waiter = Task {
            if let token = await registry.waitToAcquire(key, timeout: .seconds(5)) {
                await granted.record(1)
                await registry.release(key, token: token)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        await registry.release(key, token: holder!)
        await registry.release(key, token: holder!)

        await waiter.value
        let order = await granted.values
        XCTAssertEqual(order, [1], "only one legitimate handoff")

        let free = await registry.isHeld(key)
        XCTAssertFalse(free, "double release must not leave a phantom holder")
    }

    /// FIFO: a free key is granted immediately; a held key suspends `waitToAcquire` until the
    /// holder releases, and waiters are granted in arrival order (one writer at a time).
    func testWaitToAcquireGrantsInFIFOOrder() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:fifo"
        let first = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertNotNil(first)

        let order = OrderRecorder()
        let w1 = Task {
            if let token = await registry.waitToAcquire(key, timeout: .seconds(5)) {
                await order.record(1)
                await registry.release(key, token: token)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let w2 = Task {
            if let token = await registry.waitToAcquire(key, timeout: .seconds(5)) {
                await order.record(2)
                await registry.release(key, token: token)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        let emptyWhileHeld = await order.isEmpty
        XCTAssertTrue(emptyWhileHeld, "both waiters suspend while the key is held")

        await registry.release(key, token: first!)
        await w1.value
        await w2.value

        let finalOrder = await order.values
        XCTAssertEqual(finalOrder, [1, 2], "waiters run in arrival order")
    }

    /// A wedged holder must not hang later runs forever: a waiter that outlives the timeout
    /// returns `nil` (no ownership) while the holder keeps the key.
    func testWaitTimesOutWhenHolderNeverReleases() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:timeout"
        let first = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertNotNil(first)

        let granted = await registry.waitToAcquire(key, timeout: .milliseconds(100))
        XCTAssertNil(granted, "the queued waiter gives up after the timeout")
        let stillHeld = await registry.isHeld(key)
        XCTAssertTrue(stillHeld, "the original holder still owns the key")
    }

    /// A cancelled queued waiter returns `nil`, frees its slot, and does NOT block the next
    /// waiter from being granted when the holder releases.
    func testCancelledWaiterUnblocksTheQueue() async {
        let registry = RunWriteLockRegistry()
        let key = "v1:cancel"
        let first = await registry.waitToAcquire(key, timeout: .seconds(5))
        XCTAssertNotNil(first)

        let cancelledFlag = OrderRecorder()
        let cancelled = Task {
            let got = await registry.waitToAcquire(key, timeout: .seconds(30))
            await cancelledFlag.record(got == nil ? 0 : 1)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel()
        await cancelled.value
        let cancelledResult = await cancelledFlag.values
        XCTAssertEqual(cancelledResult, [0], "cancelled waiter returns nil")

        let next = Task { await registry.waitToAcquire(key, timeout: .seconds(5)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await registry.release(key, token: first!)
        let granted = await next.value
        XCTAssertNotNil(granted, "the next waiter is granted; a cancelled waiter didn't strand the queue")
        await registry.release(key, token: granted!)
    }
}

private actor OrderRecorder {
    private(set) var values: [Int] = []
    var isEmpty: Bool { values.isEmpty }
    func record(_ n: Int) { values.append(n) }
}
