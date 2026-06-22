import Foundation
import AllnighterCore

/// One warm, persistent worker for a single-lane chat thread (Warm_Single_Lane_Chat §4b / §5 S1).
/// Wraps a `WarmSessionDriver` (ACP for grok/cursor, app-server for codex): the process spawns and
/// indexes the repo ONCE on the first turn, then every later turn is model-time only. Keyed by the
/// same identity as conversation continuity — one warm worker per (thread, source, model, repo).
/// Dialect-agnostic: the driver owns the wire protocol + its transport. Single-lane: one turn at a time.
public actor WarmWorker {
    public let key: ExternalWorkerSession.Key
    private let driver: any WarmSessionDriver
    private let cwd: String
    private var started = false
    public private(set) var isDead = false
    /// Last time a turn was requested — drives idle teardown in the pool.
    public private(set) var lastUsedAt: Date

    public init(key: ExternalWorkerSession.Key, driver: any WarmSessionDriver, cwd: String, now: Date = Date()) {
        self.key = key
        self.driver = driver
        self.cwd = cwd
        self.lastUsedAt = now
    }

    /// Submit one user turn, streaming its events. Lazily performs the handshake + session open on
    /// the first call (the one-time index). Throws if the worker is dead or the handshake fails.
    public func prompt(_ text: String, now: Date = Date()) async throws -> AsyncThrowingStream<ACPTurnEvent, Error> {
        guard !isDead else { throw ACPError.disconnected }
        if !started {
            do { try await driver.start(cwd: cwd); started = true }
            catch { isDead = true; throw error }
        }
        lastUsedAt = now
        return await driver.prompt(text)
    }

    /// The vendor session id the driver established (for durable resume + image harvest).
    public func vendorSessionId() async -> String? { await driver.vendorSessionId }

    /// True if no turn has been requested since `cutoff` (idle teardown candidate).
    public func isIdle(since cutoff: Date) -> Bool { lastUsedAt < cutoff }

    /// Kill the warm process and tear down the session. Idempotent.
    public func shutdown() async {
        guard !isDead else { return }
        isDead = true
        await driver.shutdown()
    }
}
