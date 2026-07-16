import Foundation
import AllnighterCore

/// Warm conversation driver for Claude Code `-p --input-format stream-json` (Warm_Single_Lane_Chat
/// Phase 2). The simplest dialect: NO handshake, NO session id — the warm process IS the session.
/// `start` just launches the reader; each `prompt` sends a `{"type":"user"}` message on stdin and
/// streams `content_block_delta`s until the `{"type":"result"}` turn-end. Reuses the stdio transport
/// + `WarmWorker`/`WarmWorkerPool`. Single-lane: one turn at a time.
public actor ClaudeSession: WarmSessionDriver {
    private let transport: ACPTransport
    private var readerTask: Task<Void, Never>?
    private var started = false
    private var activeTurn: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation?

    public init(transport: ACPTransport) {
        self.transport = transport
    }

    /// No vendor session id — the warm process itself is the session (no handshake id to capture).
    public var vendorSessionId: String? { nil }

    public func start(cwd: String) async throws {
        guard !started else { return }
        started = true
        readerTask = Task { [weak self] in
            guard let self else { return }
            for await line in transport.inboundLines() {
                if let inbound = ClaudeMsg.parse(line) { await self.handle(inbound) }
            }
            await self.handleDisconnect()
        }
        // No handshake: the warm `claude -p --input-format stream-json` process (spawned in `cwd`)
        // is ready to receive user-message turns immediately. The one-time index is paid on turn 1.
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

    private func beginTurn(text: String, continuation: AsyncThrowingStream<ACPTurnEvent, Error>.Continuation) {
        guard activeTurn == nil else { continuation.finish(throwing: ACPError.busy); return }
        activeTurn = continuation
        transport.send(ClaudeMsg.userMessage(text))
    }

    private func handle(_ inbound: ClaudeMsg.Inbound) {
        switch inbound {
        case let .answerDelta(text):
            if let turn = activeTurn, !text.isEmpty { turn.yield(.answerDelta(text)) }
        case let .reasoningDelta(text):
            if let turn = activeTurn, !text.isEmpty { turn.yield(.reasoningDelta(text)) }
        case let .turnCompleted(usage):
            if let usage, !usage.isEmpty, let turn = activeTurn { turn.yield(.reportedUsage(usage)) }
            activeTurn?.finish(); activeTurn = nil
        case let .failure(message):
            activeTurn?.finish(throwing: ACPError.agentError(code: 0, message: message)); activeTurn = nil
        case .other:
            break
        }
    }

    private func handleDisconnect() {
        activeTurn?.finish(throwing: ACPError.disconnected)
        activeTurn = nil
    }
}
