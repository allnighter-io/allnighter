import Foundation
import AllnighterCore

/// Drives one-worker chat turns inside a thread: it saves the user turn and an
/// optimistic `running` worker turn immediately, assembles + persists the exact
/// context packet, invokes the worker, and settles the worker turn to its
/// terminal state. When the worker can't be invoked (manual-paste driver, or no
/// runnable manifest) it falls back to a manual-paste flow that reveals the
/// exact context and stores the pasted reply as the worker turn.
///
/// `TeamRun` is never touched here; chat turns own their text.
public actor WorkerChatCoordinator {
    public enum ChatError: Error, Equatable, CustomStringConvertible {
        case threadNotFound(String)
        case noWorkerAvailable
        case turnNotFound(String)

        public var description: String {
            switch self {
            case .threadNotFound(let id): return "Thread not found: \(id)"
            case .noWorkerAvailable: return "No worker available to send to"
            case .turnNotFound(let id): return "Turn not found: \(id)"
            }
        }
    }

    /// The outcome of a `send`, with everything the UI needs to focus the turn.
    public struct ChatResult: Sendable, Equatable {
        public var thread: WorkThread
        public var workerId: String
        public var userTurnId: String
        public var workerTurnId: String
        public var contextPacketId: String
        /// The runner outcome for a headless send; nil when manual-paste.
        public var outcome: WorkerRunOutcome?
        /// True when the worker turn is awaiting a pasted reply.
        public var awaitingManualPaste: Bool
        /// The open `manual_paste` system note, when awaiting paste.
        public var manualNoteTurnId: String?
    }

    private let store: ThreadStore
    private let runner: WorkerRunner
    private let registry: DriverRegistry
    private let contextBuilder: ThreadContextBuilder
    private let models: [Model]
    /// Global daily-driver fallback when the thread has no default/last worker.
    private let defaultDriverWorkerId: String?
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(
        store: ThreadStore,
        runner: WorkerRunner,
        registry: DriverRegistry,
        models: [Model],
        defaultDriverWorkerId: String? = nil,
        contextBuilder: ThreadContextBuilder = ThreadContextBuilder(),
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.runner = runner
        self.registry = registry
        self.models = models
        self.defaultDriverWorkerId = defaultDriverWorkerId
        self.contextBuilder = contextBuilder
        self.idFactory = idFactory
        self.now = now
    }

    // MARK: - Model resolution (Composer Contract)

    /// Resolve the worker for a turn: explicit choice → thread default →
    /// thread's last worker → global daily driver → first healthy headless CLI.
    public func resolveWorkerId(for thread: WorkThread, requested: String? = nil) -> String? {
        if let requested, hasRunnableOrManual(requested) { return requested }
        if let d = thread.defaultWorkerId, hasRunnableOrManual(d) { return d }
        if let last = thread.lastWorkerId, hasRunnableOrManual(last) { return last }
        if let global = defaultDriverWorkerId, hasRunnableOrManual(global) { return global }
        return models.first { model in
            model.enabled && registry.manifest(for: model)?.kind == .headlessCLI
        }?.id
    }

    private func hasRunnableOrManual(_ workerId: String) -> Bool {
        models.contains { $0.id == workerId }
    }

    // MARK: - Send

    /// Send a chat message to one worker. Persists optimistic turns before the
    /// invoke so a concurrent reader sees `running` immediately.
    @discardableResult
    public func send(
        message: String,
        toThreadId threadId: String,
        requestedWorkerId: String? = nil,
        contextOptions: ThreadContextBuilder.Options = ThreadContextBuilder.Options()
    ) async throws -> ChatResult {
        guard let priorThread = store.get(threadId) else { throw ChatError.threadNotFound(threadId) }
        guard let workerId = resolveWorkerId(for: priorThread, requested: requestedWorkerId) else {
            throw ChatError.noWorkerAvailable
        }

        // Assemble the packet from the thread state BEFORE the new user turn, so
        // the message is not duplicated (it lands as "Latest user message").
        let workerTurnId = idFactory()
        let packetId = idFactory()
        let packet = contextBuilder.build(
            thread: priorThread,
            latestMessage: message,
            turnId: workerTurnId,
            packetId: packetId,
            now: now(),
            options: contextOptions
        )
        try store.savePacket(packet)

        // 1. User turn — saved and renderable immediately.
        let userTurnId = idFactory()
        let userTurn = ThreadTurn(
            id: userTurnId, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: now(), completedAt: now(), author: .user, text: message
        )
        try store.appendTurn(userTurn, toThreadId: threadId, now: now())

        // 2. Optimistic worker turn — created `running` immediately.
        let workerTurn = ThreadTurn(
            id: workerTurnId, threadId: threadId, kind: .workerChat, status: .running,
            createdAt: now(), author: .worker, workerId: workerId, contextPacketId: packetId
        )
        try store.appendTurn(workerTurn, toThreadId: threadId, now: now())

        let model = models.first { $0.id == workerId }
        let manifest = model.flatMap { registry.manifest(for: $0) }

        // Manual-paste path: no runnable manifest, or an explicit manual driver.
        guard let model, let manifest, manifest.kind == .headlessCLI else {
            return try enterManualPaste(
                threadId: threadId, workerId: workerId,
                userTurnId: userTurnId, workerTurnId: workerTurnId, packetId: packetId
            )
        }

        // Headless path: invoke and settle the worker turn.
        let outcome = await runner.invoke(worker: model, manifest: manifest, prompt: packet.text)
        let thread = try settle(workerTurn: workerTurn, with: outcome, inThreadId: threadId)
        return ChatResult(
            thread: thread, workerId: workerId, userTurnId: userTurnId,
            workerTurnId: workerTurnId, contextPacketId: packetId,
            outcome: outcome, awaitingManualPaste: false, manualNoteTurnId: nil
        )
    }

    private func settle(workerTurn: ThreadTurn, with outcome: WorkerRunOutcome, inThreadId threadId: String) throws -> WorkThread {
        var settled = workerTurn
        settled.status = chatStatus(for: outcome.status)
        settled.completedAt = outcome.finishedAt ?? now()
        switch settled.status {
        case .done:
            settled.text = outcome.output
        case .failed, .timedOut, .cancelled:
            settled.text = outcome.errorReason
        case .draft, .queued, .running:
            break
        }
        return try store.updateTurn(settled, inThreadId: threadId, now: now())
    }

    private func chatStatus(for answer: WorkerAnswerStatus) -> ThreadTurnStatus {
        switch answer {
        case .done: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .queued, .running: return .running
        case .skipped: return .failed   // headless worker should not skip
        }
    }

    private func enterManualPaste(
        threadId: String, workerId: String,
        userTurnId: String, workerTurnId: String, packetId: String
    ) throws -> ChatResult {
        // An OPEN manual-paste note pulls the thread into needs-attention until
        // the user pastes; the worker turn stays `running` (awaiting).
        let noteId = idFactory()
        let note = ThreadTurn(
            id: noteId, threadId: threadId, kind: .systemEvent, status: .running,
            createdAt: now(), author: .system,
            text: "Paste \(workerId)'s reply to complete this turn.",
            systemEvent: .manualPaste
        )
        let thread = try store.appendTurn(note, toThreadId: threadId, now: now())
        return ChatResult(
            thread: thread, workerId: workerId, userTurnId: userTurnId,
            workerTurnId: workerTurnId, contextPacketId: packetId,
            outcome: nil, awaitingManualPaste: true, manualNoteTurnId: noteId
        )
    }

    /// Completes a manual-paste turn: stores the pasted reply on the worker turn
    /// and resolves the open manual-paste note so attention clears.
    @discardableResult
    public func completeManualPaste(
        threadId: String,
        workerTurnId: String,
        manualNoteTurnId: String?,
        reply: String
    ) throws -> WorkThread {
        guard let thread = store.get(threadId) else { throw ChatError.threadNotFound(threadId) }
        guard var workerTurn = thread.turn(id: workerTurnId) else { throw ChatError.turnNotFound(workerTurnId) }
        workerTurn.status = .done
        workerTurn.text = reply
        workerTurn.completedAt = now()
        var updated = try store.updateTurn(workerTurn, inThreadId: threadId, now: now())

        if let manualNoteTurnId, var note = updated.turn(id: manualNoteTurnId), !note.status.isTerminal {
            note.status = .done
            note.completedAt = now()
            updated = try store.updateTurn(note, inThreadId: threadId, now: now())
        }
        return updated
    }

    /// The exact context a worker turn was given, for the context reveal.
    public func revealContext(threadId: String, packetId: String) -> ThreadContextPacket? {
        store.packet(threadId: threadId, packetId: packetId)
    }
}
