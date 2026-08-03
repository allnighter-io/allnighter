import AppKit
import Foundation
import AllnighterCore
import AllnighterEngine

@MainActor
extension ThreadsViewModel {
    // MARK: - Routing composer (Send & Context prep)

    struct FileReferenceSendContext {
        var turnRefs: [TurnFileReferenceRef] = []
        var contextPacketId: String?
        var packetText: String?
    }

    /// Global quick capture (hotkey / menu bar): create a fresh thread (by default,
    /// per Persistent_Work_Threads) and stage clipboard content for the composer
    /// that will mount for it. If clipboardText is empty this still surfaces the
    /// composer for a new run.
    func applyQuickCapture(clipboardText: String?) {
        let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = clip.isEmpty ? Self.newChatTitle : Self.title(from: clip)
        _ = newThread(title: title)
        if !clip.isEmpty {
            pendingQuickCaptureText = clip
        }
    }

    /// Send from the unified routing composer. Runs go through `RunService` in a
    /// bound Project root; rootless legacy threads are refused honestly.
    func sendRouting(_ routing: ComposeRouting, createThread: Bool = false) {
        let message = routing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An attachment-only send (pasted image, no typed text) is valid — the workers
        // still receive the image. Only refuse a truly empty turn.
        guard !message.isEmpty || !routing.attachments.isEmpty else { return }
        var timing = RunTimingReport()
        timing.stamp(RunTimingKey.composerSubmit)

        let threadId: String
        if createThread || selectedThreadId == nil {
            guard let thread = newThread(title: Self.title(from: message)) else { return }
            threadId = thread.id
        } else if let id = selectedThreadId {
            guard store.get(id)?.isArchived != true else { return }
            threadId = id
            // First real prompt into a still-untitled "New Chat" → title it from the prompt
            // NOW, so the rail stops showing the stale placeholder the moment you send
            // (founder: a sent chat must never still read "New Chat").
            if !message.isEmpty, store.get(id)?.title == Self.newChatTitle {
                renameThread(id, title: Self.title(from: message))
            }
        } else {
            return
        }

        if let scope = repoRoot(for: threadId) {
            let userTurnId = UUID().uuidString
            do {
                let fileReferenceInputs = (routing.fileReferences + FileReferenceTokenParser.parse(message: message))
                    .dedupedPreservingOrder()
                if let currentThread = store.get(threadId) {
                    timing.set(RunTimingKey.contextTurnCount, int: currentThread.turns.count)
                }
                timing.set(RunTimingKey.contextFileReferenceCount, int: fileReferenceInputs.count)
                timing.stamp(RunTimingKey.contextBuildStart)
                let preparedRefs = try prepareFileReferenceContext(
                    inputs: fileReferenceInputs,
                    message: message,
                    threadId: threadId,
                    userTurnId: userTurnId,
                    projectId: scope.projectId,
                    repoRoot: scope.root
                )
                timing.stamp(RunTimingKey.contextBuildEnd)
                timing.set(RunTimingKey.contextBytes, int: preparedRefs.packetText?.utf8.count ?? 0)
                // Commit pasted/picked images AND captured long-paste text into the
                // thread's attachment store + workspace mirror, so EVERY worker (single or
                // team) gets them as files to open by path — images via a vision-gated
                // block, text via an always-readable read-paths block. Image refs ride on
                // the user turn (thumbnail in the thread).
                let staged = stageRunAttachments(
                    routing.attachments, threadId: threadId, repoRoot: scope.root
                )
                if appendUserTurn(
                    message,
                    toThreadId: threadId,
                    id: userTurnId,
                    fileReferenceRefs: preparedRefs.turnRefs,
                    attachmentRefs: staged.refs,
                    contextPacketId: preparedRefs.contextPacketId
                ) {
                    timing.stamp(RunTimingKey.threadUserTurnPersisted)
                    armScrollToBottomAfterSend()
                }
                runViaRunService(
                    routing,
                    toThreadId: threadId,
                    projectId: scope.projectId,
                    repoRoot: scope.root,
                    context: preparedRefs.packetText,
                    deliveries: staged.deliveries,
                    timing: timing
                )
            } catch {
                appendFailedRun(fileReferenceFailureText(error), kind: .systemEvent, toThreadId: threadId)
            }
        } else {
            appendFailedRun("Select a project with an available local root before starting a run.", kind: .systemEvent, toThreadId: threadId)
        }
    }

    func repoRoot(for threadId: String) -> (projectId: String?, root: String)? {
        guard let thread = store.get(threadId) else { return nil }
        guard let scope = projectScope(preferredProjectId: thread.projectId, fallbackWorkingDir: thread.workingDir) else {
            return nil
        }
        if thread.projectId != scope.projectId {
            bindThread(threadId, to: scope, snapshot: thread.workingDir)
        }
        return (scope.projectId, scope.root)
    }

    /// Chat: hand the message to the chosen model via the coordinator, which
    /// persists the user turn + an optimistic running `workerChat` turn, invokes
    /// the worker through the cached invocation (health == runs), and settles the
    /// reply in place. Live partials arrive via `chatLivePartialObserver` →
    /// `applyLiveDelta(persistCheckpoint: false)` — no 150 ms full-reload poll (PERF-S04a).
    func runChat(
        message: String,
        toThreadId threadId: String,
        modelId: String,
        fileReferences: [FileReferenceInput] = []
    ) {
        Task { @MainActor in
            do {
                let checkpoint = try await coordinator.beginSend(
                    message: message,
                    toThreadId: threadId,
                    requestedModelId: modelId,
                    fileReferences: fileReferences
                )
                refreshPublishedThread(threadId)
                reload()
                switch checkpoint {
                case .finished:
                    break
                case .awaitingInvoke(let pending):
                    // Streaming overlays in-memory via LivePartialObserver; settle with one reload.
                    _ = try await coordinator.completeSend(pending)
                    refreshPublishedThread(threadId)
                    reload()
                }
            } catch {
                refreshPublishedThread(threadId)
                reload()
            }
        }
    }

    func prepareFileReferenceContext(
        inputs: [FileReferenceInput],
        message: String,
        threadId: String,
        userTurnId: String,
        projectId: String?,
        repoRoot: String
    ) throws -> FileReferenceSendContext {
        guard !inputs.isEmpty else { return FileReferenceSendContext() }
        guard var thread = store.get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }

        let resolved = try ProjectFileReferenceResolver().resolve(
            inputs: inputs,
            rootPath: repoRoot,
            projectId: projectId,
            idFactory: { UUID().uuidString }
        )
        var options = ThreadContextBuilder.Options(attachedFileInputs: resolved.map(\.attachedFile))
        options.fileByteCap = FileReferencePolicy.default.maxDeliveredBytesPerFile
        options.byteCap = FileReferencePolicy.default.maxTotalDeliveredBytes + 16_000
        options.attachedFilesTotalByteCap = FileReferencePolicy.default.maxTotalDeliveredBytes

        thread.workingDir = repoRoot
        thread.projectId = projectId ?? thread.projectId
        let packetId = UUID().uuidString
        let packet = ThreadContextBuilder().build(
            thread: thread,
            latestMessage: message,
            turnId: userTurnId,
            packetId: packetId,
            now: Date(),
            options: options
        )
        try store.savePacket(packet)
        return FileReferenceSendContext(
            turnRefs: resolved.map(\.turnRef),
            contextPacketId: packetId,
            packetText: packet.text
        )
    }

    func fileReferenceFailureText(_ error: Error) -> String {
        if let fileError = error as? FileReferenceError {
            return "\(fileError.code): \(fileError.description)"
        }
        return error.localizedDescription
    }

    @discardableResult
    func appendUserTurn(
        _ message: String,
        toThreadId threadId: String,
        id: String = UUID().uuidString,
        fileReferenceRefs: [TurnFileReferenceRef] = [],
        attachmentRefs: [TurnAttachmentRef] = [],
        contextPacketId: String? = nil
    ) -> Bool {
        let turn = ThreadTurn(
            id: id, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user, text: message,
            attachmentRefs: attachmentRefs,
            fileReferenceRefs: fileReferenceRefs,
            contextPacketId: contextPacketId
        )
        guard (try? store.appendTurn(turn, toThreadId: threadId, now: Date())) != nil else { return false }
        refreshPublishedThread(threadId)
        reload()
        return true
    }

    /// Commit composer images AND captured long-paste text into the thread's attachment
    /// store + workspace mirror, returning the combined deliveries (for the run) and
    /// image refs (for the user turn). Failures degrade to no-attachment rather than
    /// blocking the send.
    func stageRunAttachments(
        _ attachments: [ComposeAttachment], threadId: String, repoRoot: String
    ) -> RunAttachmentStager.Staged {
        let images = attachments.filter { $0.kind == .image }
        let texts = attachments.filter { $0.kind == .text }
        guard !images.isEmpty || !texts.isEmpty else { return .empty }
        do {
            let dir = try store.threadDirectory(forThreadId: threadId)
            let stager = RunAttachmentStager()
            var deliveries: [IncludedAttachmentDelivery] = []
            var refs: [TurnAttachmentRef] = []
            var warnings: [String] = []

            if !images.isEmpty {
                let inputs = images.map {
                    ThreadSendCoordinator.ImageInput(
                        frozenFileURL: $0.fileURL, sourceKind: .guiAttach, originalName: $0.displayName
                    )
                }
                let s = try stager.stage(
                    images: inputs, threadId: threadId, threadDirectory: dir, workingDir: repoRoot
                )
                deliveries += s.deliveries; refs += s.refs; warnings += s.warnings
            }
            if !texts.isEmpty {
                let snippets = texts.compactMap { att -> RunAttachmentStager.TextSnippet? in
                    guard let body = try? String(contentsOf: att.fileURL, encoding: .utf8),
                          !body.isEmpty else { return nil }
                    return RunAttachmentStager.TextSnippet(title: att.displayName, body: body)
                }
                let s = try stager.stageText(
                    snippets: snippets, threadId: threadId, threadDirectory: dir,
                    workingDir: repoRoot, startSequence: deliveries.count
                )
                deliveries += s.deliveries; warnings += s.warnings
            }
            return RunAttachmentStager.Staged(deliveries: deliveries, refs: refs, warnings: warnings)
        } catch {
            return .empty
        }
    }

    /// The placeholder title a fresh, unsent chat carries until its first prompt names it.
    static let newChatTitle = "New Chat"

    static func title(from text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return newChatTitle }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }
}
