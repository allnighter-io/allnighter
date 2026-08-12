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
    var threads: [WorkThread] = []
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
    let coordinator: AgentChatCoordinator
    /// Shared sink for default-chat streaming flushes (PERF-S04a). Wired after init.
    private let chatLivePartialObserver = ThreadSendCoordinator.LivePartialObserver()
    let registry: DriverRegistry
    let commandRunner: CommandRunner
    /// When false, team/mutating runs built through `RunService` honor the injected
    /// `commandRunner` for opencode seats (test doubles only).
    let routeOpenCodeToServe: Bool
    /// Cached health truth (loaded once at launch, never probed here) — drives the
    /// ready bench the team resolver may draw from. Empty until setup has run.
    let toolStatuses: [ToolProbeRecord]
    /// Process-wide mutating-run gate (Unified Run Model). Shared with `RunService`
    /// so concurrent mutating runs on one repo root are refused honestly.
    let writeLock: RunWriteLockRegistry
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
    var liveCheckpointAt: [String: Date] = [:]
    private static let liveCheckpointInterval: TimeInterval = 1.5
    /// TRR-S01c — live artifact seat snapshots keyed by run id (cleared on terminal).
    var liveArtifactByRunId: [String: LiveArtifactProjector.State] = [:]

    static let readClearDebounceNs: UInt64 = 200_000_000

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
        routeOpenCodeToServe: Bool = true,
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
        self.routeOpenCodeToServe = routeOpenCodeToServe
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

    func armScrollToBottomAfterSend() {
        forceScrollToBottomAfterSend = true
        forceScrollToBottomClearTask?.cancel()
        forceScrollToBottomClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.forceScrollToBottomWindowNs)
            guard !Task.isCancelled else { return }
            forceScrollToBottomAfterSend = false
        }
    }

    private static let forceScrollToBottomWindowNs: UInt64 = 600_000_000







    /// The durable TeamRun behind a board turn (by `runId`), for the board view.
    /// In-memory cache of decoded runs. Terminal runs are immutable, so caching them
    /// turns the repeated `run.json` decode (SwiftUI re-reads `ThreadBoardRow.run` many
    /// times per draw → a 5–10s stall on a big run) into a dict lookup. Not @Observable —
    /// writes here must never trigger a re-render during body evaluation.
    let runCache = RunDecodeCache()





}
