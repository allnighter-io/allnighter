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
    case busy                   // a turn is already in flight (single-lane guard)
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

/// One warm conversation driver, independent of wire dialect. `ACPSession` (grok/cursor ACP) and
/// `CodexSession` (codex app-server) both conform, so `WarmWorker`/`WarmWorkerPool`/the transport are
/// dialect-agnostic. Single-lane: one turn at a time.
public protocol WarmSessionDriver: Sendable {
    /// Handshake + open a session bound to `cwd` (the one-time index). Called lazily on turn 1.
    func start(cwd: String) async throws
    /// Submit one user turn, streaming its events; finishes when the agent completes the turn.
    func prompt(_ text: String) async -> AsyncThrowingStream<ACPTurnEvent, Error>
    /// Tear down the session (process kill happens in the transport). Idempotent.
    func shutdown() async
    /// The vendor session id this driver established on `start` (nil before turn 1). Surfaced so
    /// the warm run path can persist it for durable resume after the warm worker dies, and so the
    /// image harvest can map a Codex run to its rollout. (Without this the warm path captured no
    /// id — continuity worked only while the in-memory worker stayed alive.)
    var vendorSessionId: String? { get async }
}

/// Drives ONE warm ACP conversation over an `ACPTransport`: `initialize` → [`authenticate`] →
/// `session/new {cwd}` → `session/prompt` per turn, routing `session/update` to the active turn and
/// acking any server→client request so the agent never blocks. The dialect deltas (grok vs cursor)
/// come from the injected `ACPTransportProfile`.
public actor ACPSession: WarmSessionDriver {
    private let transport: ACPTransport
    private let profile: ACPTransportProfile
    private var nextId = 0
    private var sessionId: String?
    private var readerTask: Task<Void, Never>?
    private var started = false

    /// In-flight request/response waiters (initialize, session/new), keyed by JSON-RPC id.
    private var pending: [Int: CheckedContinuation<ACP.Inbound, Error>] = [:]
    /// The single active prompt turn: its request id + the stream it feeds.
    private var activeTurn: (id: Int, continuation: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation)?

    public init(transport: ACPTransport, profile: ACPTransportProfile) {
        self.transport = transport
        self.profile = profile
    }

    public var vendorSessionId: String? { sessionId }

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
        if profile.requiresAuthenticate {
            _ = try await request { ACP.authenticate(id: $0) }
        }
        let params = profile.sessionNewParams(cwd: cwd)
        let reply = try await request { ACP.sessionNew(id: $0, params: params) }
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
        transport.terminate()
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
        // Single-lane guard: never clobber an in-flight turn. The write lock serializes mutating
        // chat already; this is the backstop for any caller that doesn't.
        guard activeTurn == nil else { continuation.finish(throwing: ACPError.busy); return }
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

        case let .permissionRequest(id, options):
            // Approve using an option the agent ACTUALLY offered (falls back to allow-once).
            let optionId = ACP.chooseAllowOption(options) ?? "allow-once"
            transport.send(ACP.permissionResult(id: id, optionId: optionId))

        case let .serverRequest(id, _):
            // Other server→client requests (cursor/ask_question, etc.): minimal ack so we don't
            // deadlock. Real answers for blocking plan-mode extensions are S5.
            transport.send(ACP.emptyResult(id: id))

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
