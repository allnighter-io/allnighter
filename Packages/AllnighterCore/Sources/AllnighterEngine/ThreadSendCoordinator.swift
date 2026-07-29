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
        public var fileReferences: [FileReferenceInput]
        public var requestedWorkerId: String?
        public var contextOptions: ThreadContextBuilder.Options

        public init(
            message: String,
            draftIds: [String] = [],
            images: [ImageInput] = [],
            fileReferences: [FileReferenceInput] = [],
            requestedWorkerId: String? = nil,
            contextOptions: ThreadContextBuilder.Options = .init()
        ) {
            self.message = message
            self.draftIds = draftIds
            self.images = images
            self.fileReferences = fileReferences
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
        /// User-send attachment ids for this turn (CIA law — unchanged meaning).
        public var attachmentIds: [String]
        public var deliveries: [IncludedAttachmentDelivery]
        public var fileReferenceIds: [String]
        public var fileReferences: [IncludedFileReferenceDelivery]
        /// Agent-produced image attachment ids when capture lands (WIO).
        public var workerAttachmentIds: [String]
        public var workerDeliveries: [IncludedAttachmentDelivery]
        public var outcome: WorkerRunOutcome?
        public var awaitingManualPaste: Bool
        public var manualNoteTurnId: String?
        public var stageWarnings: [String]
    }

    /// Optimistic turns are persisted; invoke has not started yet.
    public struct PendingSend: Sendable, Equatable {
        public var threadId: String
        public var workerId: String
        public var userTurnId: String
        public var workerTurn: ThreadTurn
        public var contextPacketId: String
        public var prompt: String
        public var attachmentIds: [String]
        public var deliveries: [IncludedAttachmentDelivery]
        public var fileReferenceRefs: [TurnFileReferenceRef]
        public var fileReferences: [IncludedFileReferenceDelivery]
        public var invokeProfile: ChatImageIntent.Profile
        public var userMessage: String
        public var workingDir: String?
        public var stageWarnings: [String]
    }

    /// After `beginSend`, either invoke is still pending or manual-paste finished synchronously.
    public enum SendCheckpoint: Sendable, Equatable {
        case awaitingInvoke(PendingSend)
        case finished(Result)
    }

    /// A throttled live streaming partial flushed from `runStreamingText`. GUI surfaces
    /// overlay this onto published turns without a full `ThreadStore.list()` reload.
    public struct LivePartialUpdate: Sendable, Equatable {
        public var threadId: String
        public var turnId: String
        public var answerText: String
        public var reasoningText: String
        public var truncated: Bool

        public init(
            threadId: String,
            turnId: String,
            answerText: String,
            reasoningText: String,
            truncated: Bool
        ) {
            self.threadId = threadId
            self.turnId = turnId
            self.answerText = answerText
            self.reasoningText = reasoningText
            self.truncated = truncated
        }
    }

    /// Mutable Sendable sink so a MainActor view model can attach a handler after
    /// construction (the coordinator is created during `init` before `self` is usable).
    public final class LivePartialObserver: @unchecked Sendable {
        public var handler: (@Sendable (LivePartialUpdate) -> Void)?

        public init(handler: (@Sendable (LivePartialUpdate) -> Void)? = nil) {
            self.handler = handler
        }

        public func notify(_ update: LivePartialUpdate) {
            handler?(update)
        }
    }

    private let store: ThreadStore
    private let runner: any WorkerInvoking
    private let imageInvoker: WorkerImageInvoker
    private let registry: DriverRegistry
    private let contextBuilder: ThreadContextBuilder
    private let seedResolver: ThreadImageSeedResolver
    private let models: [Model]
    private let defaultDriverWorkerId: String?
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let livePartialObserver: LivePartialObserver?

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
        livePartialObserver: LivePartialObserver? = nil
    ) {
        self.store = store
        self.runner = runner
        self.imageInvoker = imageInvoker ?? WorkerImageInvoker(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()), now: now)
        self.registry = registry
        self.contextBuilder = contextBuilder
        self.seedResolver = seedResolver
        self.models = models
        self.defaultDriverWorkerId = defaultDriverWorkerId
        self.idFactory = idFactory
        self.now = now
        self.livePartialObserver = livePartialObserver
    }

    /// Test/production wiring: share one `CommandRunner` between text and image invoke paths.
    public init(
        store: ThreadStore,
        commandRunner: CommandRunner,
        invocations: [String: ToolInvocation] = [:],
        registry: DriverRegistry,
        models: [Model],
        defaultDriverWorkerId: String? = nil,
        contextBuilder: ThreadContextBuilder = ThreadContextBuilder(),
        seedResolver: ThreadImageSeedResolver = ThreadImageSeedResolver(),
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init,
        livePartialObserver: LivePartialObserver? = nil
    ) {
        self.init(
            store: store,
            runner: WorkerInvokerFactory.makeWorkerInvoker(
                commandRunner: (commandRunner as? StreamingCommandRunner) ?? CommandRunnerAsStreaming(commandRunner), invocations: invocations, now: now),
            imageInvoker: WorkerImageInvoker(commandRunner: commandRunner, invocations: invocations, now: now),
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

    public func send(request: Request, toThreadId threadId: String) async throws -> Result {
        switch try beginSend(request: request, toThreadId: threadId) {
        case .finished(let result):
            return result
        case .awaitingInvoke(let pending):
            return try await completeSend(pending)
        }
    }

    public func beginSend(request: Request, toThreadId threadId: String) throws -> SendCheckpoint {
        let prepared = try prepareSend(request: request, toThreadId: threadId)

        guard let model = models.first(where: { $0.id == prepared.workerId }),
              let manifest = registry.manifest(for: model),
              manifest.kind == .headlessCLI else {
            let result = try enterManualPaste(
                threadId: threadId, workerId: prepared.workerId, userTurnId: prepared.userTurnId,
                workerTurnId: prepared.workerTurn.id, packetId: prepared.contextPacketId,
                attachmentIds: prepared.attachmentIds, deliveries: prepared.deliveries,
                fileReferenceRefs: prepared.fileReferenceRefs, fileReferences: prepared.fileReferences,
                stageWarnings: prepared.stageWarnings
            )
            return .finished(result)
        }

        return .awaitingInvoke(PendingSend(
            threadId: threadId,
            workerId: prepared.workerId,
            userTurnId: prepared.userTurnId,
            workerTurn: prepared.workerTurn,
            contextPacketId: prepared.contextPacketId,
            prompt: prepared.prompt,
            attachmentIds: prepared.attachmentIds,
            deliveries: prepared.deliveries,
            fileReferenceRefs: prepared.fileReferenceRefs,
            fileReferences: prepared.fileReferences,
            invokeProfile: prepared.invokeProfile,
            userMessage: prepared.userMessage,
            workingDir: prepared.workingDir,
            stageWarnings: prepared.stageWarnings
        ))
    }

    public func completeSend(_ pending: PendingSend) async throws -> Result {
        guard let model = models.first(where: { $0.id == pending.workerId }),
              let manifest = registry.manifest(for: model),
              manifest.kind == .headlessCLI else {
            throw AgentChatCoordinator.ChatError.noWorkerAvailable
        }

        switch pending.invokeProfile {
        case .regularText:
            // STR-S07: stream live partials onto the running turn as they arrive.
            // `DefaultWorkerRunner` (inside the composed `runner`) degrades internally
            // to a terminal-only stream for a driver with no parser / that can't stream,
            // so there is no separate stream-capable-vs-not branch to maintain here
            // anymore — one call always drives the live-partial path, and settlement
            // (which reloads the latest turn) is identical either way (F2_B.3c).
            let outcome = await runStreamingText(
                pending: pending, model: model, manifest: manifest)
            let thread = try settleStreamingAware(
                turnId: pending.workerTurn.id, fallback: pending.workerTurn,
                with: outcome, inThreadId: pending.threadId
            )
            try? PendingCapacityResumeWriter.applyLinkedCapacity(
                store: PendingStore(),
                threadId: pending.threadId,
                outcome: outcome,
                now: now()
            )
            return Result(
                thread: thread, workerId: pending.workerId, userTurnId: pending.userTurnId,
                workerTurnId: pending.workerTurn.id, contextPacketId: pending.contextPacketId,
                attachmentIds: pending.attachmentIds, deliveries: pending.deliveries,
                fileReferenceIds: pending.fileReferenceRefs.map(\.referenceId),
                fileReferences: pending.fileReferences,
                workerAttachmentIds: [], workerDeliveries: [],
                outcome: outcome, awaitingManualPaste: false, manualNoteTurnId: nil,
                stageWarnings: pending.stageWarnings
            )

        case .imageGen:
            guard let imageGen = manifest.imageGen else {
                throw AgentChatCoordinator.ChatError.noWorkerAvailable
            }
            let threadDir = try store.threadDirectory(forThreadId: pending.threadId)
            let scratch = threadDir.appendingPathComponent("worker_scratch/\(pending.workerTurn.id)", isDirectory: true)
            let imageOut = scratch.appendingPathComponent("worker_reply.png")
            let designPrompt = Self.imageGenDesignPrompt(
                userMessage: pending.userMessage,
                deliveries: pending.deliveries,
                hasSeedDelivery: pending.deliveries.count > pending.attachmentIds.count
            )

            let invokeOutcome = await imageInvoker.invoke(
                model: model, manifest: manifest, designPrompt: designPrompt,
                scratchDir: scratch, imageOut: imageOut, workingDirectoryOverride: pending.workingDir
            )

            var outcome = Self.outcome(from: invokeOutcome)
            var workerAttachmentIds: [String] = []
            var workerDeliveries: [IncludedAttachmentDelivery] = []
            var captionText: String?
            var workerRefs: [TurnAttachmentRef] = []

            if outcome.status == .done {
                let capture = WorkerImageCapture.capture(
                    imageGen: imageGen, stdout: invokeOutcome.stdout, intendedOut: imageOut
                )
                captionText = capture.captionText ?? outcome.output
                if let url = capture.normalizedImageURL {
                    let committed = try commitWorkerImage(
                        threadId: pending.threadId, imageURL: url, workerTurnId: pending.workerTurn.id
                    )
                    workerAttachmentIds = [committed.ref.attachmentId]
                    workerDeliveries = [committed.delivery]
                    workerRefs = [committed.ref]
                    outcome.output = captionText
                } else if let reason = capture.failureReason {
                    let note = "[Image capture failed: \(reason)]"
                    captionText = [captionText, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                    outcome.output = captionText
                }
            }

            let thread = try settle(
                workerTurn: pending.workerTurn,
                with: outcome,
                inThreadId: pending.threadId,
                captionText: captionText,
                workerAttachmentRefs: workerRefs
            )
            return Result(
                thread: thread, workerId: pending.workerId, userTurnId: pending.userTurnId,
                workerTurnId: pending.workerTurn.id, contextPacketId: pending.contextPacketId,
                attachmentIds: pending.attachmentIds, deliveries: pending.deliveries,
                fileReferenceIds: pending.fileReferenceRefs.map(\.referenceId),
                fileReferences: pending.fileReferences,
                workerAttachmentIds: workerAttachmentIds, workerDeliveries: workerDeliveries,
                outcome: outcome, awaitingManualPaste: false, manualNoteTurnId: nil,
                stageWarnings: pending.stageWarnings
            )
        }
    }

    // MARK: - Prepare send

    private struct PreparedSend {
        var workerId: String
        var userTurnId: String
        var workerTurn: ThreadTurn
        var contextPacketId: String
        var prompt: String
        var attachmentIds: [String]
        var deliveries: [IncludedAttachmentDelivery]
        var fileReferenceRefs: [TurnFileReferenceRef]
        var fileReferences: [IncludedFileReferenceDelivery]
        var invokeProfile: ChatImageIntent.Profile
        var userMessage: String
        var workingDir: String?
        var stageWarnings: [String]
    }

    private struct CommittedWorkerImage {
        var ref: TurnAttachmentRef
        var delivery: IncludedAttachmentDelivery
    }

    private func prepareSend(request: Request, toThreadId threadId: String) throws -> PreparedSend {
        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !request.draftIds.isEmpty || !request.images.isEmpty || !request.fileReferences.isEmpty else {
            throw AttachmentError.decodeFailed
        }

        guard var priorThread = store.get(threadId) else {
            throw AgentChatCoordinator.ChatError.threadNotFound(threadId)
        }
        guard let workerId = resolveWorkerId(for: priorThread, requested: request.requestedWorkerId) else {
            throw AgentChatCoordinator.ChatError.noWorkerAvailable
        }

        let fileInputs = (request.fileReferences + FileReferenceTokenParser.parse(message: trimmed))
            .dedupedPreservingOrder()
        let resolvedFileReferences = fileInputs.isEmpty ? [] : try ProjectFileReferenceResolver().resolve(
            inputs: fileInputs,
            rootPath: priorThread.workingDir,
            projectId: priorThread.projectId,
            idFactory: idFactory
        )

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

        let manifest = models.first { $0.id == workerId }.flatMap { registry.manifest(for: $0) }
        let hasPriorImage = seedResolver.hasPriorImageContext(thread: priorThread, attachmentStore: attachmentStore)
        let invokeProfile: ChatImageIntent.Profile
        if let manifest {
            invokeProfile = ChatImageIntent.decide(
                message: trimmed, manifest: manifest, hasPriorImageContext: hasPriorImage
            )
        } else {
            invokeProfile = .regularText
        }

        var seedDeliveries: [IncludedAttachmentDelivery] = []
        if invokeProfile == .imageGen,
           let seed = seedResolver.resolveSeed(thread: priorThread, attachmentStore: attachmentStore) {
            switch seed.source {
            case .existingAttachment(let ref, let attachment):
                try attachmentStore.verifyHash(for: attachment)
                let canonical = attachmentStore.canonicalURL(for: attachment).path
                seedDeliveries.append(IncludedAttachmentDelivery(
                    attachmentId: ref.attachmentId,
                    sequence: deliveries.count,
                    canonicalPath: canonical,
                    deliveredPathUsed: canonical,
                    storedSha256: attachment.storedSha256
                ))
            case .boardImage(let runId, let chosenWorkerId, let imageURL):
                let ingested = try attachmentStore.ingestor.ingest(
                    fileURL: imageURL, sourceKind: .workerGenerated, originalName: imageURL.lastPathComponent
                )
                let attachmentId = idFactory()
                let (record, ref) = try attachmentStore.commitIngested(
                    ingested: ingested,
                    attachmentId: attachmentId,
                    threadId: threadId,
                    sourceKind: .workerGenerated,
                    sequence: 0,
                    originalName: imageURL.lastPathComponent,
                    now: timestamp
                )
                let decisionId = idFactory()
                let decisionTurn = ThreadTurn(
                    id: decisionId, threadId: threadId, kind: .userDecision, status: .done,
                    createdAt: timestamp, completedAt: timestamp, author: .user,
                    text: "Picked design option \(chosenWorkerId) as the reference image.",
                    runId: runId,
                    attachmentRefs: [ref]
                )
                priorThread = try store.appendTurn(decisionTurn, toThreadId: threadId, now: timestamp)
                let canonical = attachmentStore.canonicalURL(for: record).path
                seedDeliveries.append(IncludedAttachmentDelivery(
                    attachmentId: ref.attachmentId,
                    sequence: deliveries.count,
                    canonicalPath: canonical,
                    deliveredPathUsed: canonical,
                    storedSha256: record.storedSha256
                ))
                _ = chosenWorkerId
            }
        }

        deliveries.append(contentsOf: seedDeliveries)
        for offset in deliveries.indices {
            deliveries[offset].sequence = offset
        }

        try attachmentStore.verifyHashes(for: committedAttachments)

        var stageWarnings: [String] = []
        if let workingDir = priorThread.workingDir, !workingDir.isEmpty, !deliveries.isEmpty {
            let stagedAttachments = deliveries.compactMap { attachmentStore.attachment(for: $0.attachmentId) }
            stageWarnings = try WorkspaceAttachmentStaging.stage(
                attachments: stagedAttachments,
                deliveries: &deliveries,
                threadId: threadId,
                workingDir: workingDir,
                canonicalURL: attachmentStore.canonicalURL(for:)
            )
        }

        let workerTurnId = idFactory()
        let packetId = idFactory()
        var contextOptions = request.contextOptions
        if !resolvedFileReferences.isEmpty {
            contextOptions.attachedFiles.append(contentsOf: resolvedFileReferences.map(\.attachedFile))
            contextOptions.fileByteCap = max(
                contextOptions.fileByteCap,
                FileReferencePolicy.default.maxDeliveredBytesPerFile
            )
            contextOptions.byteCap = max(
                contextOptions.byteCap,
                FileReferencePolicy.default.maxTotalDeliveredBytes + 16_000
            )
            contextOptions.attachedFilesTotalByteCap = FileReferencePolicy.default.maxTotalDeliveredBytes
        }
        var packet = contextBuilder.build(
            thread: priorThread,
            latestMessage: trimmed,
            turnId: workerTurnId,
            packetId: packetId,
            now: timestamp,
            options: contextOptions
        )

        let readsImages = manifest?.canReadImages ?? false
        packet.includedAttachments = deliveries
        packet.text = try AttachmentDeliveryRenderer.protectedPrompt(
            baseText: packet.text,
            deliveries: deliveries,
            readsImages: invokeProfile == .imageGen ? true : readsImages,
            byteCap: contextOptions.byteCap
        )

        try store.savePacket(packet)

        let userTurnId = idFactory()
        let userTurn = ThreadTurn(
            id: userTurnId, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: timestamp, completedAt: timestamp, author: .user,
            text: trimmed.isEmpty ? nil : trimmed,
            attachmentRefs: refs,
            fileReferenceRefs: resolvedFileReferences.map(\.turnRef)
        )
        try store.appendTurn(userTurn, toThreadId: threadId, now: timestamp)

        let workerTurn = ThreadTurn(
            id: workerTurnId, threadId: threadId, kind: .workerChat, status: .running,
            createdAt: timestamp, author: .worker, workerId: workerId, contextPacketId: packetId
        )
        try store.appendTurn(workerTurn, toThreadId: threadId, now: timestamp)

        return PreparedSend(
            workerId: workerId,
            userTurnId: userTurnId,
            workerTurn: workerTurn,
            contextPacketId: packetId,
            prompt: packet.text,
            attachmentIds: refs.map(\.attachmentId),
            deliveries: deliveries,
            fileReferenceRefs: resolvedFileReferences.map(\.turnRef),
            fileReferences: packet.includedFileReferences,
            invokeProfile: invokeProfile,
            userMessage: trimmed,
            workingDir: priorThread.workingDir,
            stageWarnings: stageWarnings
        )
    }

    private func commitWorkerImage(
        threadId: String,
        imageURL: URL,
        workerTurnId: String
    ) throws -> CommittedWorkerImage {
        let threadDir = try store.threadDirectory(forThreadId: threadId)
        let attachmentStore = ThreadAttachmentStore(threadDirectory: threadDir)
        let flock = try ThreadFlockLock.acquire(lockURL: attachmentStore.lockURL)
        defer { _ = flock }

        let timestamp = now()
        let ingested = try attachmentStore.ingestor.ingest(
            fileURL: imageURL, sourceKind: .workerGenerated, originalName: imageURL.lastPathComponent
        )
        let attachmentId = idFactory()
        let (record, ref) = try attachmentStore.commitIngested(
            ingested: ingested,
            attachmentId: attachmentId,
            threadId: threadId,
            sourceKind: .workerGenerated,
            sequence: 0,
            originalName: imageURL.lastPathComponent,
            now: timestamp
        )
        try attachmentStore.verifyHash(for: record)
        let canonical = attachmentStore.canonicalURL(for: record).path
        let delivery = IncludedAttachmentDelivery(
            attachmentId: ref.attachmentId,
            sequence: ref.sequence,
            canonicalPath: canonical,
            deliveredPathUsed: canonical,
            storedSha256: record.storedSha256
        )
        _ = workerTurnId
        return CommittedWorkerImage(ref: ref, delivery: delivery)
    }

    private func resolveWorkerId(for thread: WorkThread, requested: String?) -> String? {
        if let requested, !requested.isEmpty {
            // MR-S04: explicit --model is honor-or-fail; never fall through to a default.
            switch ExactIdResolver.resolveWorker(requested, flag: "--model", models: models) {
            case .success(let model):
                return model.id
            case .failure:
                return nil
            }
        }
        if let d = thread.defaultWorkerId, models.contains(where: { $0.id == d }) { return d }
        if let last = thread.lastWorkerId, models.contains(where: { $0.id == last }) { return last }
        if let global = defaultDriverWorkerId, models.contains(where: { $0.id == global }) { return global }
        return models.first { $0.enabled && registry.manifest(for: $0)?.kind == .headlessCLI }?.id
    }

    private func settle(
        workerTurn: ThreadTurn,
        with outcome: WorkerRunOutcome,
        inThreadId threadId: String,
        captionText: String? = nil,
        workerAttachmentRefs: [TurnAttachmentRef] = []
    ) throws -> WorkThread {
        var settled = workerTurn
        settled.status = chatStatus(for: outcome.status)
        settled.completedAt = outcome.timing.finishedAt ?? now()
        switch settled.status {
        case .done:
            settled.text = captionText ?? outcome.output
            if !workerAttachmentRefs.isEmpty {
                settled.attachmentRefs = workerAttachmentRefs
            }
        case .failed, .timedOut, .cancelled: settled.text = outcome.errorReason
        case .draft, .queued, .running: break
        }
        return try store.updateTurn(settled, inThreadId: threadId, now: now())
    }

    /// Drives the composed `WorkerInvoking` stack, flushing visible partial text onto
    /// the running worker turn at a throttled cadence (≥2 KB OR ≥~150 ms), and returns
    /// the terminal outcome. The buffer caps visible text at 64 KB. Each flush RELOADS
    /// the latest running turn before writing so a concurrent settle can't be lost.
    /// The old "empty stream -> retry via a second non-streaming invoke" fallback is
    /// dropped: `DefaultWorkerRunner` is now the ONE code path (no separate streaming
    /// vs non-streaming spawn), so a second call would deterministically reproduce the
    /// same result, not a different degraded path (F2_B.3c).
    private func runStreamingText(
        pending: PendingSend, model: Model, manifest: DriverManifest
    ) async -> WorkerRunOutcome {
        var buffer = StreamingPartialBuffer()
        var reasoning = ""
        var lastFlush = now()
        let flushInterval: TimeInterval = 0.1
        var terminal: WorkerRunOutcome?

        func flush() {
            guard let latest = store.get(pending.threadId)?.turn(id: pending.workerTurn.id),
                  latest.status == .running else { return }
            let answerText = buffer.visibleText
            let truncated = buffer.isTruncated
            var updated = latest
            updated.text = answerText
            updated.partialOutputTruncated = truncated
            if !reasoning.isEmpty { updated.reasoningText = reasoning }
            _ = try? store.updateTurn(updated, inThreadId: pending.threadId, now: now())
            buffer.markFlushed()
            lastFlush = now()
            // Notify GUI overlay AFTER durable flush so in-memory UI can skip a second write.
            livePartialObserver?.notify(LivePartialUpdate(
                threadId: pending.threadId,
                turnId: pending.workerTurn.id,
                answerText: answerText,
                reasoningText: reasoning,
                truncated: truncated
            ))
        }

        do {
            for try await event in runner.invoke(WorkerInvocation(
                model: model, manifest: manifest, prompt: pending.prompt,
                workingDirectory: pending.workingDir
            )) {
                switch event {
                case .answerDelta(let text, _, _):
                    let byteDue = buffer.append(text)
                    if byteDue || now().timeIntervalSince(lastFlush) >= flushInterval { flush() }
                case .reasoningDelta(let text, _):
                    reasoning += text
                    if now().timeIntervalSince(lastFlush) >= flushInterval { flush() }
                case .completed(let outcome), .failed(let outcome):
                    terminal = outcome
                case .started, .rawEvent, .toolActivity:
                    break
                }
            }
        } catch {
            // A stream-level throw is not run-truth; settle from the terminal we have
            // (or a generic failure) and keep whatever partial was flushed.
        }
        // Final flush so the last sub-threshold delta is visible before settlement.
        flush()
        return terminal ?? WorkerRunOutcome(
            status: .failed, errorKind: .emptyOutput,
            errorReason: "stream ended without a terminal event")
    }

    /// Settles a worker turn by RELOADING the latest stored turn first (the
    /// stale-turn trap): a streamed run has already persisted partial text on the
    /// running turn, so we must not settle the stale optimistic copy. On success the
    /// complete normalized answer replaces the partial; on failure/timeout/cancel a
    /// real non-empty partial is preserved (the status conveys the error) and the
    /// error string is only used as text when no partial ever arrived. For the
    /// non-streaming path the reloaded turn equals the optimistic turn, so behavior
    /// is unchanged.
    private func settleStreamingAware(
        turnId: String, fallback: ThreadTurn, with outcome: WorkerRunOutcome, inThreadId threadId: String
    ) throws -> WorkThread {
        var settled = store.get(threadId)?.turn(id: turnId) ?? fallback
        let partial = settled.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        settled.status = chatStatus(for: outcome.status)
        settled.completedAt = outcome.timing.finishedAt ?? now()
        switch settled.status {
        case .done:
            settled.text = outcome.output
            settled.partialOutputTruncated = false
        case .failed, .timedOut, .cancelled:
            if let partial, !partial.isEmpty {
                // Keep the real partial; the terminal status communicates the error.
            } else {
                settled.text = outcome.output ?? outcome.errorReason
            }
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
        case .skipped: return .failed
        }
    }

    private func enterManualPaste(
        threadId: String, workerId: String,
        userTurnId: String, workerTurnId: String, packetId: String,
        attachmentIds: [String], deliveries: [IncludedAttachmentDelivery],
        fileReferenceRefs: [TurnFileReferenceRef], fileReferences: [IncludedFileReferenceDelivery],
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
            fileReferenceIds: fileReferenceRefs.map(\.referenceId), fileReferences: fileReferences,
            workerAttachmentIds: [], workerDeliveries: [],
            outcome: nil, awaitingManualPaste: true, manualNoteTurnId: noteId,
            stageWarnings: stageWarnings
        )
    }

    private static func imageGenDesignPrompt(
        userMessage: String,
        deliveries: [IncludedAttachmentDelivery],
        hasSeedDelivery: Bool
    ) -> String {
        var parts: [String] = []
        let block = AttachmentDeliveryRenderer.pathBlock(deliveries: deliveries)
        if !block.isEmpty { parts.append(block) }
        var message = userMessage
        if hasSeedDelivery {
            message += "\n\nUse the attached reference image when present."
        }
        if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(message)
        }
        return parts.joined(separator: "\n\n")
    }

    private static func outcome(from invoke: WorkerImageInvokeOutcome) -> WorkerRunOutcome {
        var outcome = WorkerRunOutcome(status: .running, exitCode: invoke.exitCode.map(Int.init))
        outcome.timing.startedAt = invoke.startedAt
        outcome.timing.finishedAt = invoke.finishedAt
        outcome.timing.durationMs = invoke.durationMs
        if let launchError = invoke.launchError {
            outcome.status = .failed
            outcome.errorKind = .missingCLI
            outcome.errorReason = launchError
            return outcome
        }
        if invoke.cancelled {
            outcome.status = .cancelled
            outcome.errorKind = .cancelled
            return outcome
        }
        if invoke.timedOut {
            outcome.status = .timedOut
            outcome.errorKind = .timedOut
            outcome.errorReason = "image generation timed out"
            return outcome
        }
        if let code = invoke.exitCode, code != 0 {
            outcome.status = .failed
            outcome.errorKind = .nonzeroExit
            let stderr = invoke.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome.errorReason = stderr.isEmpty ? "exit code \(code)" : stderr
            return outcome
        }
        let cleaned = TextUtil.stripANSI(invoke.stdout)
        outcome.status = .done
        outcome.output = cleaned.isEmpty ? nil : cleaned
        return outcome
    }
}
