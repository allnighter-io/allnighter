import AppKit
import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// The Work Threads surface's observable truth. Owns a `ThreadStore` and a
/// `WorkerChatCoordinator`, mirrors `AppModel`'s pattern (@Observable +
/// @MainActor, engine work in detached Tasks). UI reads this; it never mutates
/// thread truth directly — every change goes through the store/coordinator.
@MainActor
@Observable
final class ThreadsViewModel {
    private(set) var threads: [WorkThread] = []
    private(set) var selectedThreadId: String?

    /// The active project new threads bind to (PRJ-S14). Kept in sync from
    /// `ProjectsViewModel.activeProjectId` by RootView.
    var currentProjectId: String?

    /// Pending text from a global quick-capture hotkey (⌥⌘Space or menu "Quick capture").
    /// The currently-visible RoutingComposer will adopt it into its editor (only if
    /// that editor is empty), then clear the pending. Quick capture creates a new
    /// thread by default per the threads phase spec.
    var pendingQuickCaptureText: String?

    let models: [Model]
    private let store: ThreadStore
    private let runStore: RunStore
    private let coordinator: WorkerChatCoordinator
    private let registry: DriverRegistry
    private let commandRunner: CommandRunner
    /// Cached health truth (loaded once at launch, never probed here) — drives the
    /// ready bench the team resolver may draw from. Empty until setup has run.
    private let toolStatuses: [ToolProbeRecord]
    /// Process-wide mutating-run gate (Unified Run Model). Shared with `RunService`
    /// so concurrent mutating runs on one repo root are refused honestly.
    private let writeLock: RunWriteLockRegistry
    private let projectStore: ProjectStore
    /// Scroll target set on thread select when unread exists (cleared after scroll).
    private(set) var pendingScrollToTurnId: String?
    private var readClearDebounceTask: Task<Void, Never>?
    private let isAppActiveForReadClear: () -> Bool
    private var notificationSnapshots: [String: ThreadNotificationSnapshot]?
    private var notificationPolicy: NotificationPolicy
    private let notificationPolicyStore: NotificationPolicyStore
    private let notificationDelivery: any ThreadNotificationDelivering
    private let floorStatus: FloorManagerStatus?
    private var latestVisibleTurnIds: [String: Set<String>] = [:]

    private static let readClearDebounceNs: UInt64 = 200_000_000

    private struct FileReferenceSendContext {
        var turnRefs: [TurnFileReferenceRef] = []
        var contextPacketId: String?
        var packetText: String?
    }

    /// Production init: self-sufficient, loads the same config as AppModel and
    /// invokes real CLIs. GUI fixtures use an isolated temp store.
    convenience init(floorStatus: FloorManagerStatus? = nil) {
        let config = AppConfig.loadConfiguration()
        // Cached health (no probing): lets team runs resolve through the SAME
        // invocations that passed the health probe (health == runs).
        let records = SetupStore().load().records
        let invocations = AppSetupModel.invocations(from: records)
        let store: ThreadStore
        let runStore: RunStore
        #if DEBUG
        if GUIFixture.isActive {
            let name = GUIFixture.active ?? "fixture"
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("allnighter-gui-fixture-\(name)", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = ThreadStore(rootDirectory: root)
            runStore = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        } else {
            store = ThreadStore()
            runStore = RunStore()
        }
        #else
        store = ThreadStore()
        runStore = RunStore()
        #endif
        let commandRunner = SubprocessCommandRunner()
        self.init(
            store: store,
            runStore: runStore,
            registry: config.registry,
            models: config.models,
            toolStatuses: records,
            runner: WorkerRunner(commandRunner: commandRunner, invocations: invocations),
            imageInvoker: WorkerImageInvoker(commandRunner: commandRunner, invocations: invocations),
            floorStatus: floorStatus,
            notificationDelivery: MacNotificationDelivery.shared
        )
        #if DEBUG
        if let fixture = GUIFixture.active {
            applyFixture(fixture)
        }
        #endif
    }

    /// Designated init — tests inject temp stores, cached health, and a mock runner.
    init(
        store: ThreadStore,
        runStore: RunStore,
        registry: DriverRegistry,
        models: [Model],
        toolStatuses: [ToolProbeRecord] = [],
        runner: WorkerRunner,
        commandRunner: CommandRunner? = nil,
        imageInvoker: WorkerImageInvoker? = nil,
        writeLock: RunWriteLockRegistry = .shared,
        projectStore: ProjectStore = ProjectStore(),
        isAppActiveForReadClear: @escaping () -> Bool = {
            NSApplication.shared.isActive && NSApplication.shared.keyWindow != nil
        },
        floorStatus: FloorManagerStatus? = nil,
        notificationPolicyStore: NotificationPolicyStore = NotificationPolicyStore(),
        notificationDelivery: (any ThreadNotificationDelivering)? = nil
    ) {
        self.store = store
        self.runStore = runStore
        self.registry = registry
        self.models = models
        self.toolStatuses = toolStatuses
        self.commandRunner = commandRunner ?? SubprocessCommandRunner()
        self.writeLock = writeLock
        self.projectStore = projectStore
        self.isAppActiveForReadClear = isAppActiveForReadClear
        self.floorStatus = floorStatus
        self.notificationPolicyStore = notificationPolicyStore
        self.notificationPolicy = notificationPolicyStore.load()
        self.notificationDelivery = notificationDelivery ?? NoOpThreadNotificationDelivery()
        self.coordinator = WorkerChatCoordinator(
            store: store, runner: runner, imageInvoker: imageInvoker,
            registry: registry, models: models
        )
        reload()
    }

    // MARK: - Derived

    /// Threads in triage order for the list.
    var triagedThreads: [WorkThread] { ThreadsPresenter.triagedActive(threads) }

    var archivedThreads: [WorkThread] { ThreadsPresenter.triagedArchived(threads) }

    /// Active rail vs archive browser (07).
    var showingArchive = false

    var selectedThread: WorkThread? {
        guard let id = selectedThreadId else { return nil }
        return threads.first { $0.id == id }
    }

    func driverName(for workerId: String) -> String {
        guard let model = models.first(where: { $0.id == workerId }) else { return workerId }
        return registry.manifest(for: model)?.displayName ?? model.driverId
    }

    // MARK: - List / selection

    func reload() {
        let beforeSnapshots = notificationSnapshots
        threads = store.list()
        if let id = selectedThreadId, !threads.contains(where: { $0.id == id }) {
            selectedThreadId = threads.first?.id
        }
        let afterSnapshots = NotificationCandidateDetection.snapshots(from: threads)
        notificationSnapshots = afterSnapshots
        floorStatus?.update(from: threads)
        Task { await processNotificationTransitions(before: beforeSnapshots, after: afterSnapshots) }
    }

    func select(_ thread: WorkThread) {
        selectedThreadId = thread.id
        pendingScrollToTurnId = ThreadsPresenter.firstUnreadTurnId(thread)
        // Cursor-style: opening a thread clears its unread dot immediately. A reply
        // that lands while it's already open is cleared by the timeline-visibility path.
        markReadOnOpen(thread)
    }

    private func markReadOnOpen(_ thread: WorkThread) {
        guard let lastTurnId = thread.turns.last?.id else { return }
        let before = store.get(thread.id)
        guard let updated = try? store.markRead(threadId: thread.id, throughTurnId: lastTurnId, now: Date()) else { return }
        if before?.readCursor != updated.readCursor || before?.hasUnread != updated.hasUnread { reload() }
    }

    /// Consumes the pending first-unread scroll target after the timeline mounts.
    func consumePendingScrollTarget() -> String? {
        defer { pendingScrollToTurnId = nil }
        return pendingScrollToTurnId
    }

    // MARK: - Timeline visibility / read clear (06 S05)

    /// Timeline reports geometrically visible turn ids; debounced read-clear goes through
    /// `ThreadStore.markReadToLatestVisible` — never GUI-only unread truth.
    func reportTimelineVisibility(threadId: String, visibleTurnIds: [String]) {
        latestVisibleTurnIds[threadId] = Set(visibleTurnIds)
        guard threadId == selectedThreadId else { return }
        readClearDebounceTask?.cancel()
        readClearDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.readClearDebounceNs)
            guard !Task.isCancelled else { return }
            applyReadClearIfNeeded(threadId: threadId, visibleTurnIds: visibleTurnIds)
        }
    }

    private func applyReadClearIfNeeded(threadId: String, visibleTurnIds: [String]) {
        guard isAppActiveForReadClear() else { return }
        let before = store.get(threadId)
        guard let updated = try? store.markReadToLatestVisible(
            threadId: threadId, visibleTurnIds: visibleTurnIds, now: Date()
        ) else { return }
        if before?.readCursor != updated.readCursor || before?.hasUnread != updated.hasUnread {
            reload()
        }
    }

    // MARK: - Rail controls (07)

    func renameThread(_ threadId: String, title: String) {
        guard (try? store.renameThread(threadId: threadId, title: title)) != nil else { return }
        reload()
    }

    func setPinned(_ threadId: String, pinned: Bool) {
        guard (try? store.setPinned(threadId: threadId, pinned: pinned, now: Date())) != nil else { return }
        reload()
    }

    func archiveThread(_ threadId: String) {
        guard (try? store.archiveThread(threadId: threadId)) != nil else { return }
        reload()
        if selectedThreadId == threadId, showingArchive == false {
            selectedThreadId = triagedThreads.first?.id
        }
    }

    func unarchiveThread(_ threadId: String) {
        guard (try? store.unarchiveThread(threadId: threadId)) != nil else { return }
        reload()
    }

    func togglePin(for thread: WorkThread) {
        guard !thread.isArchived else { return }
        setPinned(thread.id, pinned: !thread.isPinned)
    }

    @discardableResult
    func newThread(title: String = "New thread", workingDir: String? = nil) -> WorkThread? {
        guard let scope = projectScope(fallbackWorkingDir: workingDir) else {
            #if DEBUG
            if GUIFixture.isActive {
                return fixtureThread(title: title, workingDir: workingDir)
            }
            #endif
            return nil
        }
        let thread = try? store.create(
            id: UUID().uuidString, title: title, now: Date(), workingDir: scope.root
        )
        if let thread {
            bindThread(thread.id, to: scope, snapshot: workingDir)
        }
        reload()
        if let thread { selectedThreadId = thread.id }
        return thread
    }

    private struct ProjectScope {
        var projectId: String
        var root: String
    }

    private func bindThread(_ threadId: String, to scope: ProjectScope, snapshot: String? = nil) {
        _ = try? store.bindProject(
            threadId: threadId,
            projectId: scope.projectId,
            localRootPathSnapshot: snapshot
        )
    }

    private func projectScope(preferredProjectId: String? = nil, fallbackWorkingDir: String? = nil) -> ProjectScope? {
        if let preferredProjectId, let scope = scope(forProjectId: preferredProjectId) {
            return scope
        }

        if let rawPath = fallbackWorkingDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty,
           let projects = try? projectStore.activeProjects() {
            switch ProjectBinding.resolve(rawPath: rawPath, projects: projects) {
            case .existing(let projectId):
                if let scope = scope(forProjectId: projectId) { return scope }
            case .repoRoot(let path):
                guard let project = try? projectStore.add(path: path), project.rootState == .available else {
                    return nil
                }
                currentProjectId = project.id
                return ProjectScope(projectId: project.id, root: project.normalizedRootPath)
            case .unassigned:
                break
            }
        }

        if let projectId = currentProjectId {
            if let scope = scope(forProjectId: projectId) { return scope }
        }
        return nil
    }

    private func scope(forProjectId projectId: String) -> ProjectScope? {
        guard let project = try? projectStore.load(id: projectId),
              project.rootState == .available else {
            return nil
        }
        let root = project.normalizedRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        return ProjectScope(projectId: project.id, root: root)
    }

    #if DEBUG
    private func fixtureThread(title: String, workingDir: String?) -> WorkThread? {
        let thread = try? store.create(
            id: UUID().uuidString, title: title, now: Date(), workingDir: workingDir
        )
        reload()
        if let thread { selectedThreadId = thread.id }
        return thread
    }
    #endif

    /// Empty thread for the "Start a run" flow.
    func newRun() {
        _ = newThread(title: "New Chat")
    }

    // MARK: - Routing composer (CR4a user turn; CR4b chat runs the model)

    /// Global quick capture (hotkey / menu bar): create a fresh thread (by default,
    /// per Persistent_Work_Threads) and stage clipboard content for the composer
    /// that will mount for it. If clipboardText is empty this still surfaces the
    /// composer for a new run.
    func applyQuickCapture(clipboardText: String?) {
        let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = clip.isEmpty ? "New Chat" : Self.title(from: clip)
        _ = newThread(title: title)
        if !clip.isEmpty {
            pendingQuickCaptureText = clip
        }
    }

    /// Send from the unified routing composer. Runs go through `RunService` in a
    /// bound Project root; rootless legacy threads are refused honestly.
    func sendRouting(_ routing: ComposeRouting, createThread: Bool = false) {
        let message = routing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        let threadId: String
        if createThread || selectedThreadId == nil {
            guard let thread = newThread(title: Self.title(from: message)) else { return }
            threadId = thread.id
        } else if let id = selectedThreadId {
            guard store.get(id)?.isArchived != true else { return }
            threadId = id
        } else {
            return
        }

        if let scope = repoRoot(for: threadId) {
            let userTurnId = UUID().uuidString
            do {
                let preparedRefs = try prepareFileReferenceContext(
                    inputs: (routing.fileReferences + FileReferenceTokenParser.parse(message: message))
                        .dedupedPreservingOrder(),
                    message: message,
                    threadId: threadId,
                    userTurnId: userTurnId,
                    projectId: scope.projectId,
                    repoRoot: scope.root
                )
                // Commit pasted/picked images AND captured long-paste text into the
                // thread's attachment store + workspace mirror, so EVERY worker (single or
                // team) gets them as files to open by path — images via a vision-gated
                // block, text via an always-readable read-paths block. Image refs ride on
                // the user turn (thumbnail in the thread).
                let staged = stageRunAttachments(
                    routing.attachments, threadId: threadId, repoRoot: scope.root
                )
                appendUserTurn(
                    message,
                    toThreadId: threadId,
                    id: userTurnId,
                    fileReferenceRefs: preparedRefs.turnRefs,
                    attachmentRefs: staged.refs,
                    contextPacketId: preparedRefs.contextPacketId
                )
                runViaRunService(
                    routing,
                    toThreadId: threadId,
                    projectId: scope.projectId,
                    repoRoot: scope.root,
                    context: preparedRefs.packetText,
                    deliveries: staged.deliveries
                )
            } catch {
                appendFailedRun(fileReferenceFailureText(error), kind: .systemEvent, toThreadId: threadId)
            }
        } else {
            appendFailedRun("Select a project with an available local root before starting a run.", kind: .systemEvent, toThreadId: threadId)
        }
    }

    private func repoRoot(for threadId: String) -> (projectId: String?, root: String)? {
        guard let thread = store.get(threadId) else { return nil }
        guard let scope = projectScope(preferredProjectId: thread.projectId, fallbackWorkingDir: thread.workingDir) else {
            return nil
        }
        if thread.projectId != scope.projectId {
            bindThread(threadId, to: scope, snapshot: thread.workingDir)
        }
        return (scope.projectId, scope.root)
    }

    private func makeRunService() -> RunService {
        RunService(
            models: readyModels,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock,
            invocations: AppSetupModel.invocations(from: toolStatuses)
        )
    }

    /// Unified run primitive — answer teams and mutating execution share one path.
    private func runViaRunService(
        _ routing: ComposeRouting,
        toThreadId threadId: String,
        projectId: String?,
        repoRoot: String,
        context: String? = nil,
        deliveries: [IncludedAttachmentDelivery] = []
    ) {
        let preset = routing.team.flatMap { TeamCatalog.get($0) } ?? TeamCatalog.defaultRunTeam()
        guard let preset else {
            appendFailedRun("No team configured.", kind: .teamRun, toThreadId: threadId)
            return
        }

        let effort = EffortLevel(rawValue: routing.effort.rawValue) ?? preset.defaultEffort
        let turnKind: ThreadTurnKind = preset.mutating ? .mutatingRun : (routing.lane == .design ? .designBoard : .teamRun)
        let runId = UUID().uuidString
        let startedAt = Date()
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: turnKind, status: .running,
            createdAt: startedAt, author: .worker,
            workerId: preset.mutating && !routing.to.isEmpty ? routing.to : nil,
            runId: runId
        )
        guard (try? store.appendTurn(turn, toThreadId: threadId, now: startedAt)) != nil else { return }
        reload()

        let request = RunRequest(
            message: routing.text.trimmingCharacters(in: .whitespacesAndNewlines),
            repoRoot: repoRoot,
            projectId: projectId,
            presetId: routing.team,
            workerId: routing.to.isEmpty ? nil : routing.to,
            effort: effort,
            lane: routing.lane.workLane,
            context: context,
            deliveries: deliveries
        )
        let service = makeRunService()
        let threadStore = store
        let turnId = turn.id

        Task { @MainActor in
            // Consume live answer-delta events so the running turn shows streamed text
            // before the worker exits (mirrors the worker_chat streaming path).
            let (events, continuation) = AsyncStream<RunEvent>.makeStream()
            let consumer = Task { @MainActor in
                for await event in events {
                    let isAnswer = event.kind == RunEventKind.workerAnswerDelta
                    let isReasoning = event.kind == RunEventKind.workerReasoningDelta
                    guard isAnswer || isReasoning,
                          let text = event.payload["text"]?.stringValue,
                          var running = threadStore.get(threadId)?.turn(id: turnId),
                          running.status == .running else { continue }
                    if isAnswer {
                        running.text = text
                        running.partialOutputTruncated = event.payload["truncated"]?.boolValue ?? false
                    } else {
                        running.reasoningText = text
                    }
                    _ = try? threadStore.updateTurn(running, inThreadId: threadId, now: Date())
                    reload()
                }
            }
            let result = await service.run(request, origin: .gui, runId: runId, events: continuation)
            await consumer.value

            var settled = threadStore.get(threadId)?.turn(id: turnId) ?? turn
            settled.completedAt = Date()
            switch result {
            case .success(let run):
                settled.status = Self.turnStatus(for: run.status)
                if preset.mutating, let stage = run.stages.last(where: { $0.purpose == .plan }) {
                    settled.stageId = stage.id
                }
            case .failure(let error):
                settled.status = .failed
                settled.text = error.description
                settled.runId = nil
            }
            _ = try? threadStore.updateTurn(settled, inThreadId: threadId, now: Date())
            reload()
        }
    }

    /// Models whose driver is confirmed ready (cached health) — the only bench the
    /// team resolver may draw from. Never probes.
    var readyModels: [Model] {
        let readyDriverIds = Set(toolStatuses.filter { $0.status.isReady }.map(\.driverId))
        return models.filter { $0.enabled && readyDriverIds.contains($0.driverId) }
    }

    /// The durable TeamRun behind a board turn (by `runId`), for the board view.
    /// In-memory cache of decoded runs. Terminal runs are immutable, so caching them
    /// turns the repeated `run.json` decode (SwiftUI re-reads `ThreadBoardRow.run` many
    /// times per draw → a 5–10s stall on a big run) into a dict lookup. Not @Observable —
    /// writes here must never trigger a re-render during body evaluation.
    private let runCache = RunDecodeCache()

    func teamRun(forRunId runId: String) -> TeamRun? {
        if let cached = runCache.get(runId) { return cached }
        guard let run = runStore.load(runId: runId) else { return nil }
        // Only cache terminal (immutable) runs; a running run still changes.
        if run.status.isTerminal { runCache.set(runId, run) }
        return run
    }

    /// Drop a run from the decode cache (e.g. after it's updated/persisted).
    func invalidateRunCache(_ runId: String) { runCache.clear(runId) }

    private func appendFailedRun(_ reason: String, kind: ThreadTurnKind, toThreadId threadId: String) {
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: kind, status: .failed,
            createdAt: Date(), completedAt: Date(), author: .system, text: reason
        )
        try? store.appendTurn(turn, toThreadId: threadId, now: Date())
        reload()
    }

    /// A board turn is `.done` whenever the run produced something to show (complete
    /// OR partial — the board itself shows which workers failed); only a fully
    /// failed/interrupted run with no board is a failed turn.
    private static func turnStatus(for status: RunStatus) -> ThreadTurnStatus {
        switch status {
        case .complete, .partial: return .done
        case .cancelled: return .cancelled
        case .failed, .interrupted: return .failed
        case .draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        }
    }

    /// Chat: hand the message to the chosen model via the coordinator, which
    /// persists the user turn + an optimistic running `workerChat` turn, invokes
    /// the worker through the cached invocation (health == runs), and settles the
    /// reply in place.
    private func runChat(
        message: String,
        toThreadId threadId: String,
        workerId: String,
        fileReferences: [FileReferenceInput] = []
    ) {
        Task { @MainActor in
            do {
                let checkpoint = try await coordinator.beginSend(
                    message: message,
                    toThreadId: threadId,
                    requestedWorkerId: workerId,
                    fileReferences: fileReferences
                )
                reload()
                switch checkpoint {
                case .finished:
                    break
                case .awaitingInvoke(let pending):
                    // While the worker streams, poll-reload so the running turn's
                    // partial text updates live; cancel + final reload at settlement.
                    let livePoll = Task { @MainActor in
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(150))
                            if Task.isCancelled { break }
                            reload()
                        }
                    }
                    defer { livePoll.cancel() }
                    _ = try await coordinator.completeSend(pending)
                    livePoll.cancel()
                    reload()
                }
            } catch {
                reload()
            }
        }
    }

    private func prepareFileReferenceContext(
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

    private func fileReferenceFailureText(_ error: Error) -> String {
        if let fileError = error as? FileReferenceError {
            return "\(fileError.code): \(fileError.description)"
        }
        return error.localizedDescription
    }

    private func appendUserTurn(
        _ message: String,
        toThreadId threadId: String,
        id: String = UUID().uuidString,
        fileReferenceRefs: [TurnFileReferenceRef] = [],
        attachmentRefs: [TurnAttachmentRef] = [],
        contextPacketId: String? = nil
    ) {
        let turn = ThreadTurn(
            id: id, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user, text: message,
            attachmentRefs: attachmentRefs,
            fileReferenceRefs: fileReferenceRefs,
            contextPacketId: contextPacketId
        )
        try? store.appendTurn(turn, toThreadId: threadId, now: Date())
        reload()
    }

    /// Commit composer images AND captured long-paste text into the thread's attachment
    /// store + workspace mirror, returning the combined deliveries (for the run) and
    /// image refs (for the user turn). Failures degrade to no-attachment rather than
    /// blocking the send.
    private func stageRunAttachments(
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

    private static func title(from text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }

    // MARK: - GUI fixtures

    func applyFixture(_ fixture: String) {
        #if DEBUG
        if fixture == "thread-empty" {
            _ = newThread(title: "New Chat")
            return
        }
        ThreadsFixtureSeeder(
            store: store,
            runStore: runStore,
            models: models,
            registry: registry,
            reload: { self.reload() },
            select: { self.select($0) },
            setSelectedThreadId: { self.selectedThreadId = $0 },
            threads: { self.threads }
        ).apply(fixture)
        #endif
    }

    // MARK: - Notifications (02 + UNR-S06)

    func isThreadNotificationsMuted(_ threadId: String) -> Bool {
        notificationPolicy.isThreadMuted(threadId)
    }

    func setThreadNotificationsMuted(_ threadId: String, muted: Bool) {
        notificationPolicy.setThreadMuted(threadId, muted: muted)
        try? notificationPolicyStore.save(notificationPolicy)
    }

    func shouldSuppressNotification(candidate: NotificationCandidate) -> Bool {
        guard let thread = threads.first(where: { $0.id == candidate.threadId }) else { return true }
        return NotificationSuppression.shouldSuppress(
            candidate: candidate,
            thread: thread,
            visibility: notificationVisibilityContext()
        )
    }

    func notificationVisibilityContext() -> NotificationVisibilityContext {
        NotificationVisibilityContext(
            selectedThreadId: selectedThreadId,
            visibleTurnIdsByThread: latestVisibleTurnIds,
            isAppActive: isAppActiveForReadClear()
        )
    }

    func openFromNotification(threadId: String, turnId: String) {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return }
        select(thread)
        pendingScrollToTurnId = turnId
    }

    func openPriorityThreadFromMenuBar() {
        guard let id = floorStatus?.priorityThreadId,
              let thread = threads.first(where: { $0.id == id }) else { return }
        select(thread)
    }

    private func processNotificationTransitions(
        before: [String: ThreadNotificationSnapshot]?,
        after: [String: ThreadNotificationSnapshot]
    ) async {
        let now = Date()
        let candidates = NotificationCandidateDetection.candidates(before: before, after: after, now: now)
        guard !candidates.isEmpty, notificationPolicy.enabled else { return }
        _ = await MacNotificationDelivery.shared.requestAuthorizationIfNeeded()
        for candidate in candidates {
            guard let thread = threads.first(where: { $0.id == candidate.threadId }) else { continue }
            if NotificationSuppression.shouldSuppress(
                candidate: candidate,
                thread: thread,
                visibility: notificationVisibilityContext()
            ) { continue }
            if !NotificationDeliveryFilter.shouldDeliver(
                candidate: candidate, policy: notificationPolicy, now: now
            ) { continue }
            let workerName = candidate.workerId.map { driverName(for: $0) }
            await notificationDelivery.deliver(candidate: candidate, workerDisplayName: workerName)
            NotificationDeliveryFilter.recordDelivery(
                candidate: candidate, policy: &notificationPolicy, now: now
            )
            try? notificationPolicyStore.save(notificationPolicy)
        }
    }
}
