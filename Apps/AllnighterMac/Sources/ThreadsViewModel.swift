import AppKit
import Foundation
import Observation
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

/// The Work Threads surface's observable truth. Owns a `ThreadStore` and an
/// `AgentChatCoordinator`, mirrors `AppModel`'s pattern (@Observable +
/// @MainActor, engine work in detached Tasks). UI reads this; it never mutates
/// thread truth directly — every change goes through the store/coordinator.
@MainActor
@Observable
final class ThreadsViewModel {
    private(set) var threads: [WorkThread] = []
    /// Lightweight rail-row summaries the sidebar renders (PERF-S02). Recomputed ONLY in
    /// `reload()` — a live streaming delta mutates `threads` but NOT `railRows`, so the
    /// rail does not invalidate per token.
    private(set) var railRows: [ThreadRailRowState] = []
    var selectedThreadId: String?

    /// The active project new threads bind to (PRJ-S14). Kept in sync from
    /// `ProjectsViewModel.activeProjectId` by RootView.
    var currentProjectId: String?

    /// Conversation-wide answer display mode. When true, agent answers show their raw
    /// markdown source in a fully selectable native text view (drag-select anything,
    /// auto-copy) instead of the rich render. Toggled by the per-answer control or ⌥⌘R.
    var showRawAnswers = false

    /// A synthesis (or other text) handed to the next composer as a visible attachment chip
    /// — set by the Factory Floor "Ask Another Team" / "Continue with Auto" next moves. The
    /// first visible composer adopts it (writes a .txt attachment) and clears it.
    struct PendingComposerContext: Equatable {
        let id: UUID
        let label: String
        let text: String
    }
    var pendingComposerContext: PendingComposerContext?

    /// Pending text from a global quick-capture hotkey (⌥⌘Space or menu "Quick capture").
    /// The currently-visible RoutingComposer will adopt it into its editor (only if
    /// that editor is empty), then clear the pending. Quick capture creates a new
    /// thread by default per the threads phase spec.
    var pendingQuickCaptureText: String?

    /// Bumped after a successful Loop start so composers in Loop mode can clear kickoff text.
    private(set) var loopComposerClearTick: Int = 0
    func markLoopComposerCleared() { loopComposerClearTick += 1 }

    let models: [Model]
    let store: ThreadStore
    let runStore: RunStore
    /// Store-backed relay lifecycle for ATL-S05 rail attention (same owner as
    /// `RelayStatusLoader` — never inferred from thread turn prose).
    private let loopStateStore: LoopStateStore
    private let coordinator: AgentChatCoordinator
    /// Shared sink for default-chat streaming flushes (PERF-S04a). Wired after init.
    private let chatLivePartialObserver = ThreadSendCoordinator.LivePartialObserver()
    let registry: DriverRegistry
    private let commandRunner: CommandRunner
    /// Cached health truth (loaded once at launch, never probed here) — drives the
    /// ready bench the team resolver may draw from. Empty until setup has run.
    private let toolStatuses: [ToolProbeRecord]
    /// Process-wide mutating-run gate (Unified Run Model). Shared with `RunService`
    /// so concurrent mutating runs on one repo root are refused honestly.
    private let writeLock: RunWriteLockRegistry
    let projectStore: ProjectStore
    /// Explicit scroll target (notification deep-link only; cleared after scroll).
    var pendingScrollToTurnId: String?
    /// After composer submit, keep the timeline pinned to the bottom through the brief
    /// burst of user + worker turns so the user sees their message land.
    private var forceScrollToBottomAfterSend = false
    private var forceScrollToBottomClearTask: Task<Void, Never>?
    var readClearDebounceTask: Task<Void, Never>?
    let isAppActiveForReadClear: () -> Bool
    private var notificationSnapshots: [String: ThreadNotificationSnapshot]?
    /// Prior run park/resume snapshots for once-each vendor continuity notices.
    var previousRunNotificationSnapshots: [String: RunNotificationSnapshot]?
    var notificationPolicy: NotificationPolicy
    let notificationPolicyStore: NotificationPolicyStore
    let notificationDelivery: any ThreadNotificationDelivering
    /// Liveness check for `alln serve`'s background `NotificationScheduler`
    /// (URN-S01 "exactly one owner"). When the daemon is `.available` it is
    /// already delivering every transition this view model would also
    /// deliver, so the Mac app suppresses its own delivery rather than
    /// double-firing the same banner.
    let serveDaemonProbe: ServeDaemonProbe
    let floorStatus: FloorManagerStatus?
    var latestVisibleTurnIds: [String: Set<String>] = [:]
    var attachmentThumbCache: [String: NSImage] = [:]

    /// Coalesced-reload state: a burst of streaming deltas must not produce a burst of
    /// full `ThreadStore.list()` decodes (PERF-S01). `requestReload()` schedules at most
    /// one publish per runloop tick.
    private var reloadScheduled = false
    /// Monotonic publish generation (PERF-S04b). Bumped on each full-list reload request
    /// and on live mutations that must win over an in-flight background list. A finishing
    /// list publishes only when its captured generation is still current.
    private var publishGeneration: UInt64 = 0
    /// Serializes off-main `ThreadStore.list()` so overlapping reloads cannot interleave
    /// directory scans (PERF-S04b).
    private static let listQueue = DispatchQueue(
        label: "com.allnighter.mac.threads-reload",
        qos: .userInitiated
    )
    /// Per-running-turn timestamp of the last DURABLE thread.json checkpoint — live text
    /// streams in memory; disk is written only every `liveCheckpointInterval`, never per
    /// token (crash-resume continuity without write amplification).
    private var liveCheckpointAt: [String: Date] = [:]
    private static let liveCheckpointInterval: TimeInterval = 1.5
    /// TRR-S01c — live artifact seat snapshots keyed by run id (cleared on terminal).
    var liveArtifactByRunId: [String: LiveArtifactProjector.State] = [:]

    static let readClearDebounceNs: UInt64 = 200_000_000

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
        let commandRunner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())
        self.init(
            store: store,
            runStore: runStore,
            registry: config.registry,
            models: config.models,
            toolStatuses: records,
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: commandRunner, invocations: invocations),
            imageInvoker: WorkerImageInvoker(commandRunner: commandRunner, invocations: invocations),
            floorStatus: floorStatus,
            notificationDelivery: MacNotificationDelivery.shared
        )
        #if DEBUG
        if let fixture = GUIFixture.active {
            applyFixture(fixture)
        }
        #endif
        reload()
    }

    /// Designated init — tests inject temp stores, cached health, and a mock runner.
    init(
        store: ThreadStore,
        runStore: RunStore,
        registry: DriverRegistry,
        models: [Model],
        toolStatuses: [ToolProbeRecord] = [],
        runner: any WorkerInvoking,
        commandRunner: CommandRunner? = nil,
        imageInvoker: WorkerImageInvoker? = nil,
        writeLock: RunWriteLockRegistry = .shared,
        projectStore: ProjectStore = ProjectStore(),
        isAppActiveForReadClear: @escaping () -> Bool = {
            NSApplication.shared.isActive && NSApplication.shared.keyWindow != nil
        },
        floorStatus: FloorManagerStatus? = nil,
        notificationPolicyStore: NotificationPolicyStore = NotificationPolicyStore(),
        notificationDelivery: (any ThreadNotificationDelivering)? = nil,
        serveDaemonProbe: ServeDaemonProbe = ServeDaemonProbe()
    ) {
        self.store = store
        self.runStore = runStore
        self.loopStateStore = LoopStateStore()
        self.registry = registry
        self.models = models
        self.toolStatuses = toolStatuses
        self.commandRunner = commandRunner ?? SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())
        self.writeLock = writeLock
        self.projectStore = projectStore
        self.isAppActiveForReadClear = isAppActiveForReadClear
        self.floorStatus = floorStatus
        self.notificationPolicyStore = notificationPolicyStore
        self.notificationPolicy = notificationPolicyStore.load()
        self.notificationDelivery = notificationDelivery ?? NoOpThreadNotificationDelivery()
        self.serveDaemonProbe = serveDaemonProbe
        self.coordinator = AgentChatCoordinator(
            store: store, runner: runner, imageInvoker: imageInvoker,
            registry: registry, models: models,
            livePartialObserver: chatLivePartialObserver
        )
        // PERF-S04a: default-chat flushes feed the same in-memory overlay as Team streaming.
        // Coordinator already persists throttled partials to the store — skip duplicate writes.
        chatLivePartialObserver.handler = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.applyChatLivePartial(update)
            }
        }
        // Intentionally no reload() here — callers that need a first snapshot await
        // `reloadAsync()` (tests) or the convenience init schedules `reload()` (app).
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

    func driverName(for modelId: String) -> String {
        guard let model = models.first(where: { $0.id == modelId }) else { return modelId }
        return registry.manifest(for: model)?.displayName ?? model.driverId
    }

    // MARK: - List / selection

    /// Fire-and-forget full-store refresh. List/decode runs off the MainActor; publish is
    /// generation-gated so a stale background read cannot overwrite newer live state.
    func reload() {
        Task { @MainActor in
            await reloadAsync()
        }
    }

    /// Awaitable full-store refresh (tests and callers that need a settled publish).
    func reloadAsync() async {
        let generation = bumpPublishGeneration()
        let store = self.store
        let (listed, listedOffMain): ([WorkThread], Bool) = await withCheckedContinuation { continuation in
            Self.listQueue.async {
                continuation.resume(returning: Self.listThreadsOffMain(store))
            }
        }
        publishListedThreads(listed, generation: generation, listedOffMain: listedOffMain)
    }

    /// Sync helper so `Thread.isMainThread` is not read from an `async` context (Swift 6).
    nonisolated private static func listThreadsOffMain(_ store: ThreadStore) -> ([WorkThread], Bool) {
        (store.list(), !Thread.isMainThread)
    }

    /// Coalesced reload: a burst of events (streaming deltas, rapid mutations) folds into
    /// ONE `reloadAsync()` at the next runloop tick instead of one full list-decode per event.
    func requestReload() {
        PerfCounters.bump(.reloadRequested)
        if reloadScheduled { PerfCounters.bump(.reloadCoalesced); return }
        reloadScheduled = true
        Task { @MainActor in
            reloadScheduled = false
            await reloadAsync()
        }
    }

    /// Current publish generation — tests use this to prove a stale snapshot is discarded.
    var publishGenerationForTesting: UInt64 { publishGeneration }

    /// Test/seam: attempt to publish a list snapshot under an explicit generation.
    func publishListedThreadsForTesting(
        _ listed: [WorkThread],
        generation: UInt64,
        listedOffMain: Bool = true
    ) {
        publishListedThreads(listed, generation: generation, listedOffMain: listedOffMain)
    }

    func bumpPublishGeneration() -> UInt64 {
        publishGeneration &+= 1
        return publishGeneration
    }

    private func publishListedThreads(
        _ listed: [WorkThread],
        generation: UInt64,
        listedOffMain: Bool
    ) {
        guard generation == publishGeneration else {
            PerfCounters.bump(.reloadPublishDiscarded)
            return
        }
        if listedOffMain { PerfCounters.bump(.threadStoreListOffMain) }
        PerfCounters.bump(.threadsReload)
        let beforeSnapshots = notificationSnapshots
        threads = listed
        // Derive the rail summaries once here (PERF-S02/S03), not per render/per delta.
        railRows = threads.map(makeRailRow(from:))
        if let id = selectedThreadId, !threads.contains(where: { $0.id == id }) {
            selectedThreadId = threads.first?.id
        }
        let afterSnapshots = NotificationCandidateDetection.snapshots(from: threads)
        notificationSnapshots = afterSnapshots
        floorStatus?.update(from: threads)
        Task { await processNotificationTransitions(before: beforeSnapshots, after: afterSnapshots) }
    }

    /// Cheap single-thread refresh after a local store mutation so `applyLiveDelta` / UI
    /// selection do not wait on a full off-main `list()`. Follow with `reload()` to
    /// reconcile the rest of the rail from disk.
    func refreshPublishedThread(_ threadId: String) {
        guard let thread = store.get(threadId) else { return }
        upsertPublishedThread(thread)
    }

    private func upsertPublishedThread(_ thread: WorkThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
        if let rowIndex = railRows.firstIndex(where: { $0.id == thread.id }) {
            railRows[rowIndex] = makeRailRow(from: thread)
        } else {
            railRows.insert(makeRailRow(from: thread), at: 0)
        }
    }

    /// Rail summary with store-backed relay lifecycle when this thread is a loop
    /// (thread id == relay id). Same source as `RelayStatusLoader` / ATL-S04 chrome.
    private func makeRailRow(from thread: WorkThread) -> ThreadRailRowState {
        let relayStatus = loopStateStore.load(id: thread.id)?.status
        return ThreadsPresenter.railRow(from: thread, relayStatus: relayStatus)
    }

    /// A live streaming partial for the selected running turn. Updates the published
    /// `threads` IN MEMORY (no `store.list()`, no `thread.json` write) so text streams
    /// cheaply, and writes a DURABLE checkpoint to thread.json at most every
    /// `liveCheckpointInterval` for crash-resume — never per token. Returns true if a
    /// running turn was found and updated.
    /// - Parameter persistCheckpoint: When false, skip the throttled store write (chat path:
    ///   `ThreadSendCoordinator` already flushes durable partials). Team/execution keep the
    ///   default `true`.
    @discardableResult
    func applyLiveDelta(
        threadId: String,
        turnId: String,
        isAnswer: Bool,
        text: String,
        truncated: Bool?,
        persistCheckpoint: Bool = true
    ) -> Bool {
        guard let ti = threads.firstIndex(where: { $0.id == threadId }),
              let tj = threads[ti].turns.firstIndex(where: { $0.id == turnId }),
              threads[ti].turns[tj].status == .running else { return false }
        // Live text must win over any in-flight background list publish (PERF-S04b).
        _ = bumpPublishGeneration()
        if isAnswer {
            threads[ti].turns[tj].text = text
            if let truncated { threads[ti].turns[tj].partialOutputTruncated = truncated }
        } else {
            threads[ti].turns[tj].reasoningText = text
        }
        PerfCounters.bump(.liveDeltaApplied)

        // Throttled durable checkpoint — keep the store's authoritative fields, write only
        // the live ones, and only when the interval has elapsed.
        guard persistCheckpoint else { return true }
        let now = Date()
        if now.timeIntervalSince(liveCheckpointAt[turnId] ?? .distantPast) >= Self.liveCheckpointInterval {
            liveCheckpointAt[turnId] = now
            if var stored = store.get(threadId)?.turn(id: turnId), stored.status == .running {
                stored.text = threads[ti].turns[tj].text
                stored.reasoningText = threads[ti].turns[tj].reasoningText
                stored.partialOutputTruncated = threads[ti].turns[tj].partialOutputTruncated
                _ = try? store.updateTurn(stored, inThreadId: threadId, now: now)
                PerfCounters.bump(.threadJSONWrite)
            }
        }
        return true
    }

    /// PERF-S04a: map a coordinator live-partial flush onto in-memory turns (no reload poll).
    private func applyChatLivePartial(_ update: ThreadSendCoordinator.LivePartialUpdate) {
        applyLiveDelta(
            threadId: update.threadId,
            turnId: update.turnId,
            isAnswer: true,
            text: update.answerText,
            truncated: update.truncated,
            persistCheckpoint: false
        )
        if !update.reasoningText.isEmpty {
            applyLiveDelta(
                threadId: update.threadId,
                turnId: update.turnId,
                isAnswer: false,
                text: update.reasoningText,
                truncated: nil,
                persistCheckpoint: false
            )
        }
    }

    func select(_ thread: WorkThread) {
        selectedThreadId = thread.id
        // Cursor-style: opening a thread clears its unread dot immediately. A reply
        // that lands while it's already open is cleared by the timeline-visibility path.
        markReadOnOpen(thread)
        prefetchTerminalRuns(for: thread)
    }

    private func markReadOnOpen(_ thread: WorkThread) {
        guard let lastTurnId = thread.turns.last?.id else { return }
        let before = store.get(thread.id)
        guard let updated = try? store.markRead(threadId: thread.id, throughTurnId: lastTurnId, now: Date()) else { return }
        if before?.readCursor != updated.readCursor || before?.hasUnread != updated.hasUnread {
            refreshPublishedThread(thread.id)
            reload()
        }
    }

    /// Consumes a notification/deep-link scroll target after the timeline applies it.
    func consumePendingScrollTarget() -> String? {
        defer { pendingScrollToTurnId = nil }
        return pendingScrollToTurnId
    }

    /// True while the timeline should force-follow the bottom after a composer send.
    func forceScrollToBottomAfterSendActive() -> Bool {
        forceScrollToBottomAfterSend
    }

    private func armScrollToBottomAfterSend() {
        forceScrollToBottomAfterSend = true
        forceScrollToBottomClearTask?.cancel()
        forceScrollToBottomClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.forceScrollToBottomWindowNs)
            guard !Task.isCancelled else { return }
            forceScrollToBottomAfterSend = false
        }
    }

    private static let forceScrollToBottomWindowNs: UInt64 = 600_000_000



    // MARK: - Routing composer (CR4a user turn; CR4b chat runs the model)

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
        deliveries: [IncludedAttachmentDelivery] = [],
        timing seedTiming: RunTimingReport = RunTimingReport()
    ) {
        var timing = seedTiming
        let preset = routing.team.flatMap { TeamCatalog.get($0) } ?? TeamCatalog.defaultRunTeam()
        guard let preset else {
            appendFailedRun("No team configured.", kind: .teamRun, toThreadId: threadId)
            return
        }

        let effort = EffortLevel(rawValue: routing.effort.rawValue) ?? preset.defaultEffort
        let turnKind: ThreadTurnKind = preset.mutating ? .mutatingRun : (routing.lane == .design ? .designBoard : .teamRun)
        let runId = UUID().uuidString
        let startedAt = Date()
        let resolvedModelId = effectiveModelId(for: routing, preset: preset)
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: turnKind, status: .running,
            createdAt: startedAt, author: .worker,
            modelId: preset.mutating ? resolvedModelId : (routing.to.isEmpty ? nil : routing.to),
            runId: runId
        )
        guard (try? store.appendTurn(turn, toThreadId: threadId, now: startedAt)) != nil else { return }
        timing.stamp(RunTimingKey.threadWorkerTurnPersisted, at: startedAt)
        // Single-thread refresh so live deltas can land before the off-main full list returns.
        refreshPublishedThread(threadId)
        reload()

        let request = RunRequest(
            message: routing.text.trimmingCharacters(in: .whitespacesAndNewlines),
            repoRoot: repoRoot,
            // Worker_Session_Continuity: carry the visible thread so the run resumes this
            // thread's vendor CLI session per (source, model) instead of a fresh process.
            threadId: threadId,
            projectId: projectId,
            presetId: routing.team,
            pinnedModelId: routing.to.isEmpty ? nil : routing.to,
            effort: effort,
            lane: routing.lane.workLane,
            context: context,
            deliveries: deliveries,
            timing: timing
        )
        let service = makeRunService()
        let threadStore = store
        let turnId = turn.id
        let artifactContext = ArtifactProjector.Context(models: models)
        let teamQuestion = request.message
        let teamLabel = preset.displayName

        Task { @MainActor in
            let uiTiming = RunTimingAccumulator()
            // Consume live answer-delta events so the running turn shows streamed text
            // before the worker exits (mirrors the worker_chat streaming path).
            let (events, continuation) = AsyncStream<RunEvent>.makeStream()
            let consumer = Task { @MainActor in
                for await event in events {
                    if turnKind == .teamRun {
                        self.applyLiveArtifactEvent(
                            event, runId: runId, question: teamQuestion, teamLabel: teamLabel,
                            context: artifactContext)
                    }
                    let isAnswer = event.kind == RunEventKind.workerAnswerDelta
                    let isReasoning = event.kind == RunEventKind.workerReasoningDelta
                    guard isAnswer || isReasoning,
                          let text = event.payload["text"]?.stringValue else { continue }
                    // Stream live text into the in-memory turn (no per-delta list decode or
                    // full thread.json rewrite); a durable checkpoint is throttled inside.
                    let published = self.applyLiveDelta(
                        threadId: threadId, turnId: turnId, isAnswer: isAnswer, text: text,
                        truncated: isAnswer ? (event.payload["truncated"]?.boolValue ?? false) : nil)
                    if published {
                        await uiTiming.count(RunTimingKey.uiPublishCount)
                        await uiTiming.stampOnce(RunTimingKey.firstUIPublish)
                    }
                }
            }
            let result = await service.run(request, origin: .gui, runId: runId, events: continuation)
            await consumer.value
            liveCheckpointAt[turnId] = nil
            liveArtifactByRunId.removeValue(forKey: runId)

            // Seed settlement from the in-memory turn (freshest live text — the last delta
            // may post-date the last durable checkpoint), else the store, else the seed.
            var settled = threads.first(where: { $0.id == threadId })?.turn(id: turnId)
                ?? threadStore.get(threadId)?.turn(id: turnId) ?? turn
            settled.completedAt = Date()
            var settledRun: TeamRun?
            switch result {
            case .success(var run):
                // RLS-S01: a terminal run MUST settle to a terminal turn — never .running.
                settled.status = Self.settledStatus(forSuccessfulRun: run.status)
                if settled.modelId == nil, let modelId = run.answers.first?.modelId {
                    settled.modelId = modelId
                }
                if preset.mutating, let stage = run.stages.last(where: { $0.purpose == .plan }) {
                    settled.stageId = stage.id
                }
                // Capture any real image the worker produced (a path in its output) into the
                // thread's canonical attachment store, so the timeline shows a preview, and
                // strip the now-redundant path from the caption. Run-time copy of canonical
                // bytes — never the vendor path, never a faked thumb. Design boards are
                // skipped: their tile strip already owns the fan-out images.
                if turnKind != .designBoard {
                    let harvested = self.harvestWorkerImages(
                        run: run, settledText: settled.text,
                        reasoningText: settled.reasoningText, threadId: threadId)
                    if !harvested.refs.isEmpty {
                        settled.attachmentRefs += harvested.refs
                        if let caption = harvested.cleanedCaption { settled.text = caption }
                    }
                }
                settledRun = run
            case .failure(let error):
                settled.status = .failed
                settled.text = error.description
                settled.runId = nil
            }
            await uiTiming.stamp(RunTimingKey.threadTurnSettlementStart)
            await uiTiming.count(RunTimingKey.threadStoreUpdateTurnCount)
            // RLS-S01: terminal settlement is not best-effort. A swallowed write left the
            // turn stuck on the last `.running` checkpoint (the "it's still answering"
            // bug). Reflect the terminal state in memory FIRST so the UI can never show an
            // indefinite spinner, then persist — and surface (don't swallow) a write failure.
            applyTerminalSettlement(settled, threadId: threadId)
            do {
                try threadStore.updateTurn(settled, inThreadId: threadId, now: Date())
                await uiTiming.stamp(RunTimingKey.threadTurnSettlementEnd)
            } catch {
                await uiTiming.stamp(RunTimingKey.threadTurnSettlementError, detail: String(describing: error))
                PerfCounters.bump(.settlementError)
                FileHandle.standardError.write(Data(
                    "[settlement] FAILED to persist terminal turn \(turnId) in thread \(threadId): \(error)\n".utf8))
            }
            if var run = settledRun {
                var finalTiming = run.timing ?? timing
                finalTiming.merge(await uiTiming.snapshot())
                finalTiming.count(RunTimingKey.runStoreSaveCount, by: 1)
                run.timing = finalTiming
                try? runStore.save(run, models: models)
                if turnKind == .teamRun, run.status.isTerminal {
                    ArtifactFloorOpener.regenerateArtifact(for: run, models: models)
                }
                // CWB-S03: in-process post-run capacity refresh for the worker's source.
                // The boolean gate lives in CapacityResidentService; this caller satisfies
                // `settlementObservedInDockAppProcess` by being the Dock app's run observer.
                if let modelId = run.answers.first?.modelId,
                   let source = models.first(where: { $0.id == modelId })?.driverId
                       ?? ModelCatalog.get(modelId)?.driverId,
                   CapacityAcquisition.validRefreshSourceIds.contains(source) {
                    await CapacityResidentService.shared.postRunSettled(source: source)
                }
            }
            reload()
        }
    }

    /// TRR-S01c — map board `RunEvent`s into the live artifact preview (Mac-only).
    private func applyLiveArtifactEvent(
        _ event: RunEvent,
        runId: String,
        question: String,
        teamLabel: String,
        context: ArtifactProjector.Context
    ) {
        guard event.kind == RunEventKind.workerStatusChanged
            || event.kind == RunEventKind.workerAnswerDelta else { return }
        ensureLiveArtifactSeed(
            runId: runId, question: question, teamLabel: teamLabel, context: context)
        guard var state = liveArtifactByRunId[runId] else { return }
        if LiveArtifactProjector.apply(event, to: &state) {
            liveArtifactByRunId[runId] = state
            _ = bumpPublishGeneration()
        }
    }

    private func ensureLiveArtifactSeed(
        runId: String,
        question: String,
        teamLabel: String,
        context: ArtifactProjector.Context
    ) {
        if let state = liveArtifactByRunId[runId], !state.seatList.isEmpty { return }
        if let run = runStore.load(runId: runId) {
            liveArtifactByRunId[runId] = LiveArtifactProjector.seed(run: run, context: context)
        } else if liveArtifactByRunId[runId] == nil {
            liveArtifactByRunId[runId] = LiveArtifactProjector.bootstrap(
                runId: runId, question: question, teamLabel: teamLabel)
        }
    }

    /// Force the in-memory `threads` turn to its terminal settled state immediately, so a
    /// completed run can never leave a live spinner even if the durable write then fails
    /// or a `reload()` races. The store write remains the source of durable truth.
    private func applyTerminalSettlement(_ settled: ThreadTurn, threadId: String) {
        guard let ti = threads.firstIndex(where: { $0.id == threadId }),
              let tj = threads[ti].turns.firstIndex(where: { $0.id == settled.id }) else { return }
        threads[ti].turns[tj] = settled
    }

    /// Models whose driver is confirmed ready (cached health) — the only bench the
    /// team resolver may draw from. Never probes.
    var readyModels: [Model] {
        let parked = SetupStore().load().parkedSet
        let readyDriverIds = Set(
            toolStatuses
                .filter { $0.status.isSmokeReady && !parked.contains($0.driverId) }
                .map(\.driverId)
        )
        return models.filter { $0.enabled && readyDriverIds.contains($0.driverId) }
    }

    /// Resolve the model a routing send will actually run — explicit pin, else Auto tier
    /// default for the default team, else the team's first resolved worker.
    private func effectiveModelId(for routing: ComposeRouting, preset: TeamPreset) -> String? {
        if !routing.to.isEmpty { return routing.to }
        if preset.id == TeamCatalog.defaultRunTeam()?.id {
            let settings = DefaultModelSettingsPersistence().load()
            let ready = Set(readyModels.map(\.id))
            return SubstitutionResolver.resolveAuto(settings: settings, readyModelIds: ready).resolvedModelId
        }
        let effort = EffortLevel(rawValue: routing.effort.rawValue) ?? preset.defaultEffort
        let resolved = TeamResolver.resolve(
            team: preset, requestLane: routing.lane.workLane, requestEffort: effort,
            readyModels: readyModels)
        return resolved.answerWorkers.first?.modelId
    }

    /// The durable TeamRun behind a board turn (by `runId`), for the board view.
    /// In-memory cache of decoded runs. Terminal runs are immutable, so caching them
    /// turns the repeated `run.json` decode (SwiftUI re-reads `ThreadBoardRow.run` many
    /// times per draw → a 5–10s stall on a big run) into a dict lookup. Not @Observable —
    /// writes here must never trigger a re-render during body evaluation.
    private let runCache = RunDecodeCache()

    func liveArtifact(forRunId runId: String) -> LiveArtifactProjector.State? {
        liveArtifactByRunId[runId]
    }

    func teamRun(forRunId runId: String) -> TeamRun? {
        if let cached = runCache.get(runId) { return cached }
        guard let run = runStore.load(runId: runId) else { return nil }
        PerfCounters.bump(.runJSONDecode)
        // Only cache terminal (immutable) runs; a running run still changes.
        if run.status.isTerminal { runCache.set(runId, run) }
        return run
    }

    /// Manual "Resume now" for a vendor park — same run id, in-process.
    func resumeParkedVendorRun(runId: String) async {
        let coordinatorId = "mac:\(ProcessInfo.processInfo.processIdentifier)"
        guard runStore.claimVendorWake(
            runId: runId,
            coordinatorId: coordinatorId,
            now: Date(),
            force: true
        ) != nil else { return }
        let service = RunService(
            models: models,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock
        )
        _ = await service.resumeParkedRun(
            runId: runId,
            coordinatorId: coordinatorId,
            selectionOrigin: MorningReceipt.manualResumeOrigin
        )
        runCache.clear(runId)
        requestReload()
    }

    /// Compatible substitutes for a parked vendor wait (manual "Use another model").
    func vendorSubstitutionCandidates(for run: TeamRun) -> [Model] {
        guard run.status == .queued,
              run.phase == .waitingForVendor,
              run.blocker?.resource == .vendorBackoff,
              let failedModelId = run.workers.first?.modelId,
              let presetId = run.presetId,
              let preset = TeamCatalog.get(presetId) else { return [] }
        let settings = DefaultModelSettingsPersistence().load()
        let observations = runStore.list().flatMap { stored in
            stored.failedWorkerAnswers.compactMap(\.result.capacityObservation)
                + stored.attempts.compactMap(\.capacityObservation)
        }
        let cooling = SourceCapacityLedger.coolingSources(observations: observations, now: Date())
        return VendorSubstitutionPolicy.manualCandidates(
            run: run,
            failedModelId: failedModelId,
            preset: preset,
            settings: settings,
            models: models,
            readyModels: readyModels,
            coolingSourceIds: cooling,
            lane: run.lane ?? preset.lane
        )
    }

    /// Manual substitute while parked — same run id, user-selected model.
    func substituteParkedVendorRun(runId: String, modelId: String) async {
        let coordinatorId = "mac:\(ProcessInfo.processInfo.processIdentifier)"
        guard runStore.claimVendorWake(
            runId: runId,
            coordinatorId: coordinatorId,
            now: Date(),
            force: true
        ) != nil else { return }
        let service = RunService(
            models: models,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock
        )
        _ = await service.substituteParkedRun(
            runId: runId,
            modelId: modelId,
            coordinatorId: coordinatorId
        )
        runCache.clear(runId)
        requestReload()
    }

    /// Cancel a parked vendor wait via ownership kill settlement.
    func cancelParkedVendorRun(runId: String) async {
        _ = ProcessOwnershipSurface(runStore: runStore).kill(id: runId)
        runCache.clear(runId)
        requestReload()
    }

    /// Warm the terminal-run decode cache off the MainActor after selection (PERF-S04b).
    /// Body evaluation still falls back to a sync load on cache miss.
    private func prefetchTerminalRuns(for thread: WorkThread) {
        let missing = thread.turns.compactMap(\.runId).filter { runCache.get($0) == nil }
        guard !missing.isEmpty else { return }
        let runStore = self.runStore
        Task.detached(priority: .userInitiated) {
            var loaded: [(String, TeamRun)] = []
            for runId in missing {
                guard let run = runStore.load(runId: runId), run.status.isTerminal else { continue }
                loaded.append((runId, run))
            }
            guard !loaded.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (runId, run) in loaded {
                    if self.runCache.get(runId) == nil {
                        self.runCache.set(runId, run)
                        PerfCounters.bump(.runJSONDecode)
                    }
                }
            }
        }
    }



    /// Drop a run from the decode cache (e.g. after it's updated/persisted).
    func invalidateRunCache(_ runId: String) { runCache.clear(runId) }

    private func appendFailedRun(_ reason: String, kind: ThreadTurnKind, toThreadId threadId: String) {
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: kind, status: .failed,
            createdAt: Date(), completedAt: Date(), author: .system, text: reason
        )
        try? store.appendTurn(turn, toThreadId: threadId, now: Date())
        refreshPublishedThread(threadId)
        reload()
    }

    /// A board turn is `.done` whenever the run produced something to show (complete
    /// OR partial — the board itself shows which workers failed); only a fully
    /// failed/interrupted run with no board is a failed turn.
    nonisolated static func turnStatus(for status: RunStatus) -> ThreadTurnStatus {
        switch status {
        case .complete, .partial, .done: return .done
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .failed, .interrupted: return .failed
        // All non-terminal states show the in-flight spinner (RLR-L3 `queued`/
        // `running` included); a SUCCESS coerces these to `.done` via settledStatus.
        case .draft, .queued, .running, .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        }
    }

    /// RLS-S01 terminal-settlement guarantee: a SUCCESSFUL terminal `RunService`
    /// result must settle the thread turn to a terminal state — never `.running`.
    /// `run()` returning `.success` means the run is over, so a `run.status` that
    /// still maps to `.running` (a stale `.finalizing`/`.answersIn`/etc.) is coerced
    /// to `.done`. No spinner may survive a terminal run.
    nonisolated static func settledStatus(forSuccessfulRun status: RunStatus) -> ThreadTurnStatus {
        let mapped = turnStatus(for: status)
        return mapped == .running ? .done : mapped
    }

    /// Chat: hand the message to the chosen model via the coordinator, which
    /// persists the user turn + an optimistic running `workerChat` turn, invokes
    /// the worker through the cached invocation (health == runs), and settles the
    /// reply in place. Live partials arrive via `chatLivePartialObserver` →
    /// `applyLiveDelta(persistCheckpoint: false)` — no 150 ms full-reload poll (PERF-S04a).
    private func runChat(
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

    @discardableResult
    private func appendUserTurn(
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

    /// The placeholder title a fresh, unsent chat carries until its first prompt names it.
    static let newChatTitle = "New Chat"

    private static func title(from text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return newChatTitle }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }

}
