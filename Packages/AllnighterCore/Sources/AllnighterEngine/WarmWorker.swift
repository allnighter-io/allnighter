import Foundation
import AllnighterCore

/// One warm, persistent worker for a single-lane chat thread (Warm_Single_Lane_Chat §4b / §5 S1).
/// Wraps an `ACPSession` over a transport (grok = `ProcessACPTransport`): the process spawns and
/// indexes the repo ONCE on the first turn (`session/new`), then every later turn is model-time only.
/// Keyed by the same identity as conversation continuity — one warm worker per (thread, source,
/// model, repo). Single-lane: callers drive one turn at a time.
public actor WarmWorker {
    public let key: ExternalWorkerSession.Key
    private let session: ACPSession
    private let transport: ACPTransport
    private let profile: ACPTransportProfile
    private let cwd: String
    private var started = false
    public private(set) var isDead = false
    /// Last time a turn was requested — drives idle teardown in the pool.
    public private(set) var lastUsedAt: Date

    public init(
        key: ExternalWorkerSession.Key,
        transport: ACPTransport,
        profile: ACPTransportProfile,
        cwd: String,
        now: Date = Date()
    ) {
        self.key = key
        self.transport = transport
        self.profile = profile
        self.session = ACPSession(transport: transport)
        self.cwd = cwd
        self.lastUsedAt = now
    }

    /// Submit one user turn, streaming its events. Lazily performs the ACP handshake + `session/new`
    /// on the first call (the one-time index). Throws if the worker is dead or the handshake fails.
    public func prompt(_ text: String, now: Date = Date()) async throws -> AsyncThrowingStream<ACPTurnEvent, Error> {
        guard !isDead else { throw ACPError.disconnected }
        if !started {
            do { try await session.start(cwd: cwd, profile: profile); started = true }
            catch { isDead = true; throw error }
        }
        lastUsedAt = now
        return await session.prompt(text)
    }

    /// True if no turn has been requested since `cutoff` (idle teardown candidate).
    public func isIdle(since cutoff: Date) -> Bool { lastUsedAt < cutoff }

    /// Kill the warm process and tear down the session. Idempotent.
    public func shutdown() async {
        guard !isDead else { return }
        isDead = true
        transport.terminate()
        await session.shutdown()
    }
}
