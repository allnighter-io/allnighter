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
public actor AgentChatCoordinator {
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
    private let sendCoordinator: ThreadSendCoordinator
    private let registry: DriverRegistry
    private let contextBuilder: ThreadContextBuilder
    private let models: [Model]
    /// Global daily-driver fallback when the thread has no default/last worker.
    private let defaultDriverWorkerId: String?
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(
        store: ThreadStore,
        runner: any WorkerInvoking,
        imageInvoker: WorkerImageInvoker? = nil,
        registry: DriverRegistry,
        models: [Model],
        defaultDriverWorkerId: String? = nil,
        contextBuilder: ThreadContextBuilder = ThreadContextBuilder(),
        seedResolver: ThreadImageSeedResolver = ThreadImageSeedResolver(),
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init,
        livePartialObserver: ThreadSendCoordinator.LivePartialObserver? = nil
    ) {
        self.store = store
        self.registry = registry
        self.models = models
        self.defaultDriverWorkerId = defaultDriverWorkerId
        self.contextBuilder = contextBuilder
        self.idFactory = idFactory
        self.now = now
        self.sendCoordinator = ThreadSendCoordinator(
            store: store,
            runner: runner,
            imageInvoker: imageInvoker,
            registry: registry,
            models: models,
            defaultDriverWorkerId: defaultDriverWorkerId,
            contextBuilder: contextBuilder,
            seedResolver: seedResolver,
            idFactory: idFactory,
            now: now,
            livePartialObserver: livePartialObserver
        )
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

    /// Persist optimistic turns synchronously, then invoke when ready.
    public func beginSend(
        message: String,
        toThreadId threadId: String,
        requestedWorkerId: String? = nil,
        contextOptions: ThreadContextBuilder.Options = ThreadContextBuilder.Options(),
        draftIds: [String] = [],
        images: [ThreadSendCoordinator.ImageInput] = [],
        fileReferences: [FileReferenceInput] = []
    ) throws -> ThreadSendCoordinator.SendCheckpoint {
        try sendCoordinator.beginSend(
            request: ThreadSendCoordinator.Request(
                message: message,
                draftIds: draftIds,
                images: images,
                fileReferences: fileReferences,
                requestedWorkerId: requestedWorkerId,
                contextOptions: contextOptions
            ),
            toThreadId: threadId
        )
    }

    /// Invoke the worker for a pending send and settle the worker turn.
    public func completeSend(_ pending: ThreadSendCoordinator.PendingSend) async throws -> ChatResult {
        let result = try await sendCoordinator.completeSend(pending)
        return chatResult(from: result)
    }

    /// Send a chat message to one worker. Persists optimistic turns before the
    /// invoke so a concurrent reader sees `running` immediately.
    @discardableResult
    public func send(
        message: String,
        toThreadId threadId: String,
        requestedWorkerId: String? = nil,
        contextOptions: ThreadContextBuilder.Options = ThreadContextBuilder.Options(),
        draftIds: [String] = [],
        images: [ThreadSendCoordinator.ImageInput] = [],
        fileReferences: [FileReferenceInput] = []
    ) async throws -> ChatResult {
        switch try beginSend(
            message: message,
            toThreadId: threadId,
            requestedWorkerId: requestedWorkerId,
            contextOptions: contextOptions,
            draftIds: draftIds,
            images: images,
            fileReferences: fileReferences
        ) {
        case .finished(let result):
            return chatResult(from: result)
        case .awaitingInvoke(let pending):
            return try await completeSend(pending)
        }
    }

    private func chatResult(from result: ThreadSendCoordinator.Result) -> ChatResult {
        ChatResult(
            thread: result.thread,
            workerId: result.workerId,
            userTurnId: result.userTurnId,
            workerTurnId: result.workerTurnId,
            contextPacketId: result.contextPacketId,
            outcome: result.outcome,
            awaitingManualPaste: result.awaitingManualPaste,
            manualNoteTurnId: result.manualNoteTurnId
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
