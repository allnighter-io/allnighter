import Foundation
import AllnighterCore

/// Canonical thread send transaction (law §2). CLI, MCP, and GUI must route here.
public struct ThreadSendCoordinator: Sendable {
    public struct ImageInput: Sendable, Equatable {
        public var frozenFileURL: URL
        public var sourceKind: AttachmentSourceKind
        public var originalName: String?
        public var sourceSha256: String?

        public init(
            frozenFileURL: URL,
            sourceKind: AttachmentSourceKind,
            originalName: String? = nil,
            sourceSha256: String? = nil
        ) {
            self.frozenFileURL = frozenFileURL
            self.sourceKind = sourceKind
            self.originalName = originalName
            self.sourceSha256 = sourceSha256
        }
    }

    public struct Request: Sendable {
        public var message: String
        public var draftIds: [String]
        public var images: [ImageInput]
        public var requestedWorkerId: String?
        public var contextOptions: ThreadContextBuilder.Options

        public init(
            message: String,
            draftIds: [String] = [],
            images: [ImageInput] = [],
            requestedWorkerId: String? = nil,
            contextOptions: ThreadContextBuilder.Options = .init()
        ) {
            self.message = message
            self.draftIds = draftIds
            self.images = images
            self.requestedWorkerId = requestedWorkerId
            self.contextOptions = contextOptions
        }
    }

    public struct Result: Sendable, Equatable {
        public var thread: WorkThread
        public var workerId: String
        public var userTurnId: String
        public var workerTurnId: String
        public var contextPacketId: String
        public var attachmentIds: [String]
        public var deliveries: [IncludedAttachmentDelivery]
        public var outcome: WorkerRunOutcome?
        public var awaitingManualPaste: Bool
        public var manualNoteTurnId: String?
        public var stageWarnings: [String]
    }

    private let store: ThreadStore
    private let runner: WorkerRunner
    private let registry: DriverRegistry
    private let contextBuilder: ThreadContextBuilder
    private let models: [Model]
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

    public func send(request: Request, toThreadId threadId: String) async throws -> Result {
        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !request.draftIds.isEmpty || !request.images.isEmpty else {
            throw AttachmentError.decodeFailed
        }

        guard let priorThread = store.get(threadId) else {
            throw WorkerChatCoordinator.ChatError.threadNotFound(threadId)
        }
        guard let workerId = resolveWorkerId(for: priorThread, requested: request.requestedWorkerId) else {
            throw WorkerChatCoordinator.ChatError.noWorkerAvailable
        }

        let threadDir = try store.threadDirectory(forThreadId: threadId)
        let attachmentStore = ThreadAttachmentStore(threadDirectory: threadDir)
        let flock = try ThreadFlockLock.acquire(lockURL: attachmentStore.lockURL)
        defer { _ = flock }

        let timestamp = now()
        var committedAttachments: [TurnAttachment] = []
        var refs: [TurnAttachmentRef] = []
        var nextSequence = attachmentStore.loadDraftIndex().nextSequence

        if !request.draftIds.isEmpty {
            let promoted = try attachmentStore.promoteDrafts(
                draftIds: request.draftIds, threadId: threadId, now: timestamp
            )
            committedAttachments.append(contentsOf: promoted.attachments)
            refs.append(contentsOf: promoted.refs)
            nextSequence = attachmentStore.loadDraftIndex().nextSequence
        }

        for image in request.images {
            let ingested = try attachmentStore.ingestor.ingest(
                fileURL: image.frozenFileURL,
                sourceKind: image.sourceKind,
                originalName: image.originalName
            )
            let attachmentId = idFactory()
            let (record, ref) = try attachmentStore.commitIngested(
                ingested: ingested,
                attachmentId: attachmentId,
                threadId: threadId,
                sourceKind: image.sourceKind,
                sequence: nextSequence,
                originalName: image.originalName,
                now: timestamp
            )
            nextSequence += 1
            committedAttachments.append(record)
            refs.append(ref)
        }

        refs.sort { $0.sequence < $1.sequence }

        var deliveries: [IncludedAttachmentDelivery] = refs.compactMap { ref in
            guard let attachment = committedAttachments.first(where: { $0.id == ref.attachmentId }) else {
                return nil
            }
            let canonical = attachmentStore.canonicalURL(for: attachment).path
            return IncludedAttachmentDelivery(
                attachmentId: ref.attachmentId,
                sequence: ref.sequence,
                canonicalPath: canonical,
                deliveredPathUsed: canonical,
                storedSha256: attachment.storedSha256
            )
        }

        try attachmentStore.verifyHashes(for: committedAttachments)

        var stageWarnings: [String] = []
        if let workingDir = priorThread.workingDir, !workingDir.isEmpty, !deliveries.isEmpty {
            stageWarnings = try WorkspaceAttachmentStaging.stage(
                attachments: committedAttachments,
                deliveries: &deliveries,
                threadId: threadId,
                workingDir: workingDir,
                canonicalURL: attachmentStore.canonicalURL(for:)
            )
        }

        let workerTurnId = idFactory()
        let packetId = idFactory()
        var packet = contextBuilder.build(
            thread: priorThread,
            latestMessage: trimmed,
            turnId: workerTurnId,
            packetId: packetId,
            now: timestamp,
            options: request.contextOptions
        )

        let manifest = models.first { $0.id == workerId }.flatMap { registry.manifest(for: $0) }
        let readsImages = manifest?.canReadImages ?? false
        packet.includedAttachments = deliveries
        packet.text = try AttachmentDeliveryRenderer.protectedPrompt(
            baseText: packet.text,
            deliveries: deliveries,
            readsImages: readsImages,
            byteCap: request.contextOptions.byteCap
        )

        try store.savePacket(packet)

        let userTurnId = idFactory()
        let userTurn = ThreadTurn(
            id: userTurnId, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: timestamp, completedAt: timestamp, author: .user,
            text: trimmed.isEmpty ? nil : trimmed,
            attachmentRefs: refs
        )
        try store.appendTurn(userTurn, toThreadId: threadId, now: timestamp)

        let workerTurn = ThreadTurn(
            id: workerTurnId, threadId: threadId, kind: .workerChat, status: .running,
            createdAt: timestamp, author: .worker, workerId: workerId, contextPacketId: packetId
        )
        try store.appendTurn(workerTurn, toThreadId: threadId, now: timestamp)

        guard let model = models.first(where: { $0.id == workerId }),
              let manifest, manifest.kind == .headlessCLI else {
            return try enterManualPaste(
                threadId: threadId, workerId: workerId, userTurnId: userTurnId,
                workerTurnId: workerTurnId, packetId: packetId,
                attachmentIds: refs.map(\.attachmentId), deliveries: deliveries,
                stageWarnings: stageWarnings
            )
        }

        let outcome = await runner.invoke(worker: model, manifest: manifest, prompt: packet.text)
        let thread = try settle(workerTurn: workerTurn, with: outcome, inThreadId: threadId)
        return Result(
            thread: thread, workerId: workerId, userTurnId: userTurnId,
            workerTurnId: workerTurnId, contextPacketId: packetId,
            attachmentIds: refs.map(\.attachmentId), deliveries: deliveries,
            outcome: outcome, awaitingManualPaste: false, manualNoteTurnId: nil,
            stageWarnings: stageWarnings
        )
    }

    private func resolveWorkerId(for thread: WorkThread, requested: String?) -> String? {
        if let requested, models.contains(where: { $0.id == requested }) { return requested }
        if let d = thread.defaultWorkerId, models.contains(where: { $0.id == d }) { return d }
        if let last = thread.lastWorkerId, models.contains(where: { $0.id == last }) { return last }
        if let global = defaultDriverWorkerId, models.contains(where: { $0.id == global }) { return global }
        return models.first { $0.enabled && registry.manifest(for: $0)?.kind == .headlessCLI }?.id
    }

    private func settle(workerTurn: ThreadTurn, with outcome: WorkerRunOutcome, inThreadId threadId: String) throws -> WorkThread {
        var settled = workerTurn
        settled.status = chatStatus(for: outcome.status)
        settled.completedAt = outcome.finishedAt ?? now()
        switch settled.status {
        case .done: settled.text = outcome.output
        case .failed, .timedOut, .cancelled: settled.text = outcome.errorReason
        case .draft, .queued, .running: break
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
        case .skipped: return .failed
        }
    }

    private func enterManualPaste(
        threadId: String, workerId: String,
        userTurnId: String, workerTurnId: String, packetId: String,
        attachmentIds: [String], deliveries: [IncludedAttachmentDelivery],
        stageWarnings: [String]
    ) throws -> Result {
        let noteId = idFactory()
        let note = ThreadTurn(
            id: noteId, threadId: threadId, kind: .systemEvent, status: .running,
            createdAt: now(), author: .system,
            text: "Paste \(workerId)'s reply to complete this turn.",
            systemEvent: .manualPaste
        )
        let thread = try store.appendTurn(note, toThreadId: threadId, now: now())
        return Result(
            thread: thread, workerId: workerId, userTurnId: userTurnId,
            workerTurnId: workerTurnId, contextPacketId: packetId,
            attachmentIds: attachmentIds, deliveries: deliveries,
            outcome: nil, awaitingManualPaste: true, manualNoteTurnId: noteId,
            stageWarnings: stageWarnings
        )
    }
}
