import Foundation
import AllnighterCore

/// Warm conversation driver for Codex `app-server` (Warm_Single_Lane_Chat Phase 3). Same shape as
/// `ACPSession` but the Codex dialect: `initialize` → `initialized` (notification) → `thread/start`
/// → `turn/start` per turn, with the turn finishing on a **`turn/completed` notification** (not the
/// request's result). Reuses the stdio transport + `WarmWorker`/`WarmWorkerPool`. Single-lane.
public actor CodexSession: WarmSessionDriver {
    private let transport: ACPTransport
    private let model: String
    private var nextId = 0
    private var threadId: String?
    private var readerTask: Task<Void, Never>?
    private var started = false

    private var pending: [Int: CheckedContinuation<Codex.Inbound, Error>] = [:]
    private var activeTurn: (id: Int, continuation: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation)?

    public init(transport: ACPTransport, model: String) {
        self.transport = transport
        self.model = model
    }

    /// Codex's `thread/start` thread id — the rollout UUID this turn writes to.
    public var vendorSessionId: String? { threadId }

    public func start(cwd: String) async throws {
        guard !started else { return }
        started = true
        readerTask = Task { [weak self] in
            guard let self else { return }
            for await line in transport.inboundLines() {
                if let inbound = Codex.parse(line) { await self.handle(inbound) }
            }
            await self.handleDisconnect()
        }
        _ = try await request { Codex.initialize(id: $0) }
        transport.send(Codex.initialized())   // notification — no response
        let reply = try await request { Codex.threadStart(id: $0, cwd: cwd, model: model) }
        guard case let .result(_, tid?) = reply else { throw ACPError.noSession }
        threadId = tid
    }

    public func prompt(_ text: String) -> AsyncThrowingStream<ACPTurnEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.beginTurn(text: text, continuation: continuation) }
        }
    }

    public func shutdown() {
        readerTask?.cancel()
        transport.terminate()
        handleDisconnect()
    }

    // MARK: - internals

    private func allocId() -> Int { nextId += 1; return nextId }

    private func request(_ make: (Int) -> String) async throws -> Codex.Inbound {
        let id = allocId()
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            transport.send(make(id))
        }
    }

    private func beginTurn(text: String, continuation: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation) {
        guard let threadId else { continuation.finish(throwing: ACPError.noSession); return }
        guard activeTurn == nil else { continuation.finish(throwing: ACPError.busy); return }
        let id = allocId()
        activeTurn = (id, continuation)
        transport.send(Codex.turnStart(id: id, threadId: threadId, text: text))
    }

    private func handle(_ inbound: Codex.Inbound) {
        switch inbound {
        case let .result(id, _):
            // Only handshake requests await results. `turn/start`'s own ack is NOT turn completion —
            // the turn ends on `.turnCompleted`, so an unmatched id here is safely ignored.
            if let cont = pending.removeValue(forKey: id) { cont.resume(returning: inbound) }

        case let .answerDelta(text):
            if let turn = activeTurn, !text.isEmpty { turn.continuation.yield(.answerDelta(text)) }

        case let .reasoningDelta(text):
            if let turn = activeTurn, !text.isEmpty { turn.continuation.yield(.reasoningDelta(text)) }

        case .turnCompleted(let usage):
            if let usage, !usage.isEmpty, let turn = activeTurn { turn.continuation.yield(.reportedUsage(usage)) }
            if let turn = activeTurn { turn.continuation.finish(); activeTurn = nil }

        case let .serverRequest(id):
            transport.send(Codex.emptyResult(id: id))

        case let .failure(id, message):
            let err = ACPError.agentError(code: 0, message: message)
            if let id, let cont = pending.removeValue(forKey: id) {
                cont.resume(throwing: err)
            } else if let turn = activeTurn {
                turn.continuation.finish(throwing: err); activeTurn = nil
            }

        case .other:
            break
        }
    }

    private func handleDisconnect() {
        if let turn = activeTurn {
            turn.continuation.finish(throwing: ACPError.disconnected)
            activeTurn = nil
        }
        for (_, cont) in pending { cont.resume(throwing: ACPError.disconnected) }
        pending.removeAll()
    }
}
