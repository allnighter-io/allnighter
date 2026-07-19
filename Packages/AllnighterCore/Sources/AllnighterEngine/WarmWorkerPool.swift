import Foundation
import AllnighterCore

/// The registry of warm single-lane chat workers (Warm_Single_Lane_Chat §5 S1). One warm worker per
/// (thread, source, model, repo); bounded so N idle threads never mean N live processes — the same
/// discipline IDEs use for language servers: cap concurrent workers, LRU-evict, idle-teardown.
public actor WarmWorkerPool {
    /// Process-global pool: warm workers must outlive the per-turn `RunService` instances the app
    /// creates, or there is no warmth. Tests inject a fresh pool instead.
    public static let shared = WarmWorkerPool()

    private var workers: [ExternalWorkerSession.Key: WarmWorker] = [:]
    private let maxWorkers: Int

    public init(maxWorkers: Int = 3) {
        self.maxWorkers = max(1, maxWorkers)
    }

    /// The live warm worker for `key`, creating it via `factory` if absent or dead. Enforces the
    /// concurrency cap by evicting the least-recently-used worker first.
    public func worker(
        for key: ExternalWorkerSession.Key,
        now: Date = Date(),
        factory: @Sendable (ExternalWorkerSession.Key) throws -> WarmWorker
    ) async throws -> WarmWorker {
        if let existing = workers[key] {
            if await existing.isDead { workers[key] = nil } else { return existing }
        }
        if workers.count >= maxWorkers { await evictLRU() }
        let created = try factory(key)
        workers[key] = created
        return created
    }

    /// Shut down + drop workers untouched since `now - ttl`.
    public func reapIdle(ttl: TimeInterval, now: Date = Date()) async {
        let cutoff = now.addingTimeInterval(-ttl)
        for (key, worker) in workers where await worker.isIdle(since: cutoff) {
            await worker.shutdown()
            workers[key] = nil
        }
    }

    public func shutdownAll() async {
        for (_, worker) in workers { await worker.shutdown() }
        workers.removeAll()
    }

    /// A parked run keeps only its durable vendor session id. Never retain a
    /// warm transport across a multi-minute/hour vendor capacity wait.
    public func shutdown(key: ExternalWorkerSession.Key) async {
        guard let worker = workers.removeValue(forKey: key) else { return }
        await worker.shutdown()
    }

    public func count() -> Int { workers.count }

    // MARK: - internals

    private func evictLRU() async {
        var oldestKey: ExternalWorkerSession.Key?
        var oldest = Date.distantFuture
        for (key, worker) in workers {
            let used = await worker.lastUsedAt
            if used < oldest { oldest = used; oldestKey = key }
        }
        if let oldestKey, let victim = workers[oldestKey] {
            await victim.shutdown()
            workers[oldestKey] = nil
        }
    }
}
