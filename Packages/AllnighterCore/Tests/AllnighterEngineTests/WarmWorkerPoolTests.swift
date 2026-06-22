import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Warm_Single_Lane_Chat §5 S1: the warm-worker registry — get-or-create, dead-replacement, the
/// concurrency cap (LRU eviction), and idle teardown. WarmWorker is a reference type (actor), so
/// `===` proves whether an instance was reused, evicted, or recreated.
final class WarmWorkerPoolTests: XCTestCase {

    /// No-op transport: the pool tests exercise lifecycle, not the ACP wire.
    final class NoopACPTransport: ACPTransport, @unchecked Sendable {
        func send(_ line: String) {}
        func inboundLines() -> AsyncStream<String> { AsyncStream { $0.finish() } }
        func terminate() {}
    }

    private func key(_ thread: String) -> ExternalWorkerSession.Key {
        .init(threadId: thread, sourceId: "grok", modelId: "grok-build", repoRoot: "/repo")
    }
    /// static so factory closures capture nothing non-Sendable (Swift 6 `@Sendable` factory).
    private static func makeWorker(_ key: ExternalWorkerSession.Key, at t: TimeInterval) -> WarmWorker {
        WarmWorker(
            key: key,
            driver: ACPSession(transport: NoopACPTransport(), profile: .grok(model: "grok-build")),
            cwd: "/repo",
            now: Date(timeIntervalSince1970: t))
    }

    func testSameKeyReusesTheWarmWorker() async throws {
        let pool = WarmWorkerPool(maxWorkers: 3)
        let w1 = try await pool.worker(for: key("t1")) { Self.makeWorker($0, at: 1) }
        let w2 = try await pool.worker(for: key("t1")) { Self.makeWorker($0, at: 2) }
        XCTAssertTrue(w1 === w2, "same key returns the SAME warm worker (warm reuse)")
        let count = await pool.count(); XCTAssertEqual(count, 1)
    }

    func testDeadWorkerIsReplaced() async throws {
        let pool = WarmWorkerPool(maxWorkers: 3)
        let w1 = try await pool.worker(for: key("t1")) { Self.makeWorker($0, at: 1) }
        await w1.shutdown()
        let w2 = try await pool.worker(for: key("t1")) { Self.makeWorker($0, at: 2) }
        XCTAssertFalse(w1 === w2, "a dead worker is recreated")
    }

    func testCapEvictsLeastRecentlyUsed() async throws {
        let pool = WarmWorkerPool(maxWorkers: 2)
        let a = try await pool.worker(for: key("a")) { Self.makeWorker($0, at: 100) }  // LRU
        _ = try await pool.worker(for: key("b")) { Self.makeWorker($0, at: 200) }
        _ = try await pool.worker(for: key("c")) { Self.makeWorker($0, at: 300) }      // evicts "a"
        let count = await pool.count(); XCTAssertEqual(count, 2, "cap holds at 2")
        let a2 = try await pool.worker(for: key("a")) { Self.makeWorker($0, at: 400) }
        XCTAssertFalse(a === a2, "the LRU worker was evicted and recreated on next request")
    }

    func testReapIdleShutsDownStaleWorkers() async throws {
        let pool = WarmWorkerPool(maxWorkers: 5)
        _ = try await pool.worker(for: key("t1")) { Self.makeWorker($0, at: 1000) }
        await pool.reapIdle(ttl: 60, now: Date(timeIntervalSince1970: 2000))  // idle since 1940 > used 1000
        let count = await pool.count(); XCTAssertEqual(count, 0, "idle worker reaped")
    }

    func testReapKeepsRecentWorkers() async throws {
        let pool = WarmWorkerPool(maxWorkers: 5)
        _ = try await pool.worker(for: key("t1")) { Self.makeWorker($0, at: 1990) }
        await pool.reapIdle(ttl: 60, now: Date(timeIntervalSince1970: 2000))  // used 1990 > cutoff 1940
        let count = await pool.count(); XCTAssertEqual(count, 1, "recently-used worker kept")
    }
}
