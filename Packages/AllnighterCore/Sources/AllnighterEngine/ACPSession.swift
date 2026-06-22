import Foundation
import AllnighterCore

/// One streamed event from a warm ACP turn (Warm_Single_Lane_Chat §4b).
public enum ACPTurnEvent: Sendable, Equatable {
    case answerDelta(String)      // agent_message_chunk — visible answer text
    case reasoningDelta(String)   // agent_thought_chunk — visible reasoning
    case toolActivity(String)     // tool_call title — "read_file", "git status", …
}

public enum ACPError: Error, Equatable {
    case noSession              // session/new returned no sessionId
    case disconnected           // the agent process closed the stream mid-flight
    case agentError(code: Int, message: String)
}

/// The bidirectional line transport an `ACPSession` drives. Abstracted so the session logic is
/// unit-testable with a scripted fake; the real transport spawns `grok agent stdio` (next slice).
public protocol ACPTransport: Sendable {
    /// Write one newline-framed JSON-RPC line to the agent's stdin. Synchronous (a pipe write).
    func send(_ line: String)
    /// Newline-delimited JSON-RPC lines from the agent's stdout; finishes when the process exits.
    func inboundLines() -> AsyncStream<String>
    /// Stop the underlying worker (kill the process / close the stream). Idempotent.
    func terminate()
}

/// Drives ONE warm ACP conversation over an `ACPTransport`: `initialize` → `session/new {cwd}` →
/// `session/prompt` per turn, routing `session/update` notifications to the active turn's stream and
/// acking any server→client request so the agent never blocks. One session = one warm worker process
/// (the index/runtime load once; every turn is model-time only). Single-lane: one turn at a time.
public actor ACPSession {
    private let transport: ACPTransport
    private var nextId = 0
    private var sessionId: String?
    private var readerTask: Task<Void, Never>?
    private var started = false

    /// In-flight request/response waiters (initialize, session/new), keyed by JSON-RPC id.
    private var pending: [Int: CheckedContinuation<ACP.Inbound, Error>] = [:]
    /// The single active prompt turn: its request id + the stream it feeds.
    private var activeTurn: (id: Int, continuation: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation)?

    public init(transport: ACPTransport) {
        self.transport = transport
    }

    /// Spawn-side already running; perform the ACP handshake and open a session bound to `cwd`.
    public func start(cwd: String) async throws {
        guard !started else { return }
        started = true
        readerTask = Task { [weak self] in
            guard let self else { return }
            for await line in transport.inboundLines() {
                if let inbound = ACP.parse(line) { await self.handle(inbound) }
            }
            await self.handleDisconnect()
        }
        _ = try await request { ACP.initialize(id: $0) }
        let reply = try await request { ACP.sessionNew(id: $0, cwd: cwd) }
        guard case let .result(_, sid?) = reply else { throw ACPError.noSession }
        sessionId = sid
    }

    /// Submit one user turn; stream its events; finish when the agent completes the turn.
    public func prompt(_ text: String) -> AsyncThrowingStream<ACPTurnEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.beginTurn(text: text, continuation: continuation) }
        }
    }

    public func shutdown() {
        readerTask?.cancel()
        handleDisconnect()
    }

    // MARK: - internals

    private func allocId() -> Int { nextId += 1; return nextId }

    /// Register the waiter BEFORE sending, so a fast reply can never arrive before we're listening.
    private func request(_ make: (Int) -> String) async throws -> ACP.Inbound {
        let id = allocId()
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            transport.send(make(id))
        }
    }

    private func beginTurn(text: String, continuation: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation) {
        guard let sessionId else { continuation.finish(throwing: ACPError.noSession); return }
        let id = allocId()
        activeTurn = (id, continuation)
        transport.send(ACP.sessionPrompt(id: id, sessionId: sessionId, text: text))
    }

    private func handle(_ inbound: ACP.Inbound) {
        switch inbound {
        case let .update(update):
            guard let turn = activeTurn else { return }
            switch update.kind {
            case .message: if let t = update.text, !t.isEmpty { turn.continuation.yield(.answerDelta(t)) }
            case .thought: if let t = update.text, !t.isEmpty { turn.continuation.yield(.reasoningDelta(t)) }
            case .toolCall: if let t = update.title, !t.isEmpty { turn.continuation.yield(.toolActivity(t)) }
            case .toolCallUpdate, .plan, .none: break
            }

        case let .result(id, _):
            if let turn = activeTurn, turn.id == id {
                turn.continuation.finish()
                activeTurn = nil
            } else if let cont = pending.removeValue(forKey: id) {
                cont.resume(returning: inbound)
            }

        case let .failure(id, code, message):
            if let turn = activeTurn, turn.id == id {
                turn.continuation.finish(throwing: ACPError.agentError(code: code, message: message))
                activeTurn = nil
            } else if let cont = pending.removeValue(forKey: id) {
                cont.resume(throwing: ACPError.agentError(code: code, message: message))
            }

        case let .serverRequest(id, _):
            transport.send(ACP.emptyResult(id: id))  // ack so the agent never deadlocks on us

        case .other:
            break
        }
    }

    /// The agent stream ended (process exit/crash): fail every outstanding waiter + the active turn.
    private func handleDisconnect() {
        if let turn = activeTurn {
            turn.continuation.finish(throwing: ACPError.disconnected)
            activeTurn = nil
        }
        for (_, cont) in pending { cont.resume(throwing: ACPError.disconnected) }
        pending.removeAll()
    }
}
