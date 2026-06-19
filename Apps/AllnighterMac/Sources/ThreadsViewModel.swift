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

    var composerText: String = ""
    /// Per-turn worker override chosen in the composer; nil resolves the default.
    var requestedWorkerId: String?

    /// The active project new threads bind to (PRJ-S14). Kept in sync from
    /// `ProjectsViewModel.activeProjectId` by RootView. Nil → threads stay Unassigned.
    var currentProjectId: String?

    /// Pending text from a global quick-capture hotkey (⌥⌘Space or menu "Quick capture").
    /// The currently-visible RoutingComposer will adopt it into its editor (only if
    /// that editor is empty), then clear the pending. Quick capture creates a new
    /// thread by default per the threads phase spec.
    var pendingQuickCaptureText: String?

    /// The context packet being revealed, if the reveal sheet is open.
    private(set) var revealedPacket: ThreadContextPacket?

    let models: [Model]
    private let store: ThreadStore
    private let runStore: RunStore
    private let coordinator: WorkerChatCoordinator
    private let registry: DriverRegistry
    private let runner: WorkerRunner
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

    /// Production init: self-sufficient, loads the same config as AppModel and
    /// invokes real CLIs. GUI fixtures use an isolated temp store.
    convenience init(floorStatus: FloorManagerStatus? = nil) {
        let config = AppConfig.loadConfiguration()
        // Cached health (no probing): lets fan-out resolve teams through the SAME
        // invocations that passed the health probe (health == runs).
        let records = SetupStore().load().records
        let invocations = Self.invocations(from: records)
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
        self.runner = runner
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

    private static func invocations(from records: [ToolProbeRecord]) -> [String: ToolInvocation] {
        var map: [String: ToolInvocation] = [:]
        for record in records where record.invocation != nil {
            map[record.driverId] = record.invocation
        }
        return map
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

    /// The worker the composer will reply as, given the current override + thread.
    var resolvedComposerWorkerId: String? {
        guard let thread = selectedThread else { return requestedWorkerId }
        // Resolution is pure given workers/registry; mirror the coordinator rule.
        if let requestedWorkerId, models.contains(where: { $0.id == requestedWorkerId }) {
            return requestedWorkerId
        }
        if let d = thread.defaultWorkerId, models.contains(where: { $0.id == d }) { return d }
        if let last = thread.lastWorkerId, models.contains(where: { $0.id == last }) { return last }
        return models.first { $0.enabled && registry.manifest(for: $0)?.kind == .headlessCLI }?.id
    }

    var canSend: Bool {
        selectedThreadId != nil &&
        selectedThread?.isArchived != true &&
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        requestedWorkerId = nil
        pendingScrollToTurnId = ThreadsPresenter.firstUnreadTurnId(thread)
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
        let thread = try? store.create(
            id: UUID().uuidString, title: title, now: Date(), workingDir: workingDir
        )
        if let thread { stampProject(thread.id) }
        reload()
        if let thread { selectedThreadId = thread.id }
        return thread
    }

    /// Bind a freshly created thread to the active project (PRJ-S14). No-op when no
    /// project is active — the thread stays Unassigned (blocked from mutating dispatch).
    private func stampProject(_ threadId: String) {
        guard let pid = currentProjectId else { return }
        _ = try? store.bindProject(threadId: threadId, projectId: pid)
    }

    /// Empty thread for the "Start a run" flow.
    func newRun() {
        _ = newThread(title: "New run")
    }

    // MARK: - Routing composer (CR4a user turn; CR4b chat runs the model)

    /// Global quick capture (hotkey / menu bar): create a fresh thread (by default,
    /// per Persistent_Work_Threads) and stage clipboard content for the composer
    /// that will mount for it. If clipboardText is empty this still surfaces the
    /// composer for a new run.
    func applyQuickCapture(clipboardText: String?) {
        let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = clip.isEmpty ? "New run" : Self.title(from: clip)
        _ = newThread(title: title)
        if !clip.isEmpty {
            pendingQuickCaptureText = clip
        }
    }

    /// Send from the unified routing composer. Project-scoped runs go through
    /// `RunService` in the repo root; unassigned threads fall back to single-worker
    /// chat via the coordinator.
    func sendRouting(_ routing: ComposeRouting, createThread: Bool = false) {
        let message = routing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        let threadId: String
        if createThread || selectedThreadId == nil {
            guard let thread = try? store.create(
                id: UUID().uuidString, title: Self.title(from: message), now: Date()
            ) else { return }
            stampProject(thread.id)
            reload()
            selectedThreadId = thread.id
            threadId = thread.id
        } else if let id = selectedThreadId {
            guard store.get(id)?.isArchived != true else { return }
            threadId = id
        } else {
            return
        }

        if let scope = repoRoot(for: threadId) {
            appendUserTurn(message, toThreadId: threadId)
            runViaRunService(routing, toThreadId: threadId, projectId: scope.projectId, repoRoot: scope.root)
        } else {
            runChat(message: message, toThreadId: threadId, workerId: routing.to)
        }
    }

    private func repoRoot(for threadId: String) -> (projectId: String?, root: String)? {
        guard let thread = store.get(threadId) else { return nil }
        if let pid = thread.projectId ?? currentProjectId,
           let project = try? projectStore.load(id: pid),
           project.rootState == .available {
            let root = project.normalizedRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !root.isEmpty { return (pid, root) }
        }
        if let dir = thread.workingDir?.trimmingCharacters(in: .whitespacesAndNewlines), !dir.isEmpty {
            return (thread.projectId, dir)
        }
        return nil
    }

    private func makeRunService() -> RunService {
        RunService(
            models: readyModels,
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: writeLock,
            invocations: Self.invocations(from: toolStatuses)
        )
    }

    /// Unified run primitive — answer teams and mutating execution share one path.
    private func runViaRunService(
        _ routing: ComposeRouting,
        toThreadId threadId: String,
        projectId: String?,
        repoRoot: String
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
            createdAt: startedAt, author: .worker, workerId: preset.mutating ? routing.to : nil,
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
            lane: routing.lane.workLane
        )
        let service = makeRunService()
        let threadStore = store

        Task { @MainActor in
            let result = await service.run(request, origin: .gui, runId: runId)
            var settled = turn
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
    func teamRun(forRunId runId: String) -> TeamRun? {
        runStore.load(runId: runId)
    }

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
    private func runChat(message: String, toThreadId threadId: String, workerId: String) {
        Task { @MainActor in
            do {
                let checkpoint = try await coordinator.beginSend(
                    message: message, toThreadId: threadId, requestedWorkerId: workerId
                )
                reload()
                switch checkpoint {
                case .finished:
                    break
                case .awaitingInvoke(let pending):
                    _ = try await coordinator.completeSend(pending)
                    reload()
                }
            } catch {
                reload()
            }
        }
    }

    private func appendUserTurn(_ message: String, toThreadId threadId: String) {
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user, text: message
        )
        try? store.appendTurn(turn, toThreadId: threadId, now: Date())
        reload()
    }

    private static func title(from text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New run" }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }

    // MARK: - GUI fixtures

    func applyFixture(_ fixture: String) {
        switch fixture {
        case "thread-empty":
            _ = newThread(title: "New run")
        case "home-with-threads":
            seedFixtureThreads()
            selectedThreadId = nil
        case "thread-with-turns":
            seedFixtureThreadWithTurns()
        case "thread-chat":
            seedFixtureChatExchange()
        case "thread-team-board":
            seedFixtureTeamBoard()
        case "thread-mutating-run":
            seedFixtureMutatingRun()
        case "home-rail":
            seedFixtureRail()
            selectedThreadId = nil
        case "home-rail-th2":
            seedFixtureRailControls()
            selectedThreadId = nil
        case "home-rail-unr":
            seedFixtureUnreadMatrix()
        case "projects-rail":
            seedFixtureProjectsRail()
            reload()
            selectedThreadId = nil   // land on the home composer (shows the project chip)
        default:
            break
        }
    }

    /// PRJ-S14 proof: threads grouped under projects — a pinned cross-project row,
    /// a project with >4 threads (so "N more" shows), an unread row, a second
    /// project, and an Unassigned bucket. Bound to the sample project ids seeded
    /// into `ProjectsViewModel` by RootView.
    private func seedFixtureProjectsRail() {
        let base = Date()
        func mk(_ id: String, _ title: String, _ ago: TimeInterval, project: String?, pinned: Bool = false, unread: Bool = false) {
            guard (try? store.create(id: id, title: title, now: base.addingTimeInterval(-ago))) != nil else { return }
            if let project { _ = try? store.bindProject(threadId: id, projectId: project) }
            if pinned { _ = try? store.setPinned(threadId: id, pinned: true, now: base) }
            if unread {
                let t = ThreadTurn(id: "\(id)-t", threadId: id, kind: .workerChat, status: .done,
                                   createdAt: base, completedAt: base, author: .worker)
                _ = try? store.appendTurn(t, toThreadId: id, now: base)
            }
        }
        mk("pr-pin", "Redesign the profile screen now", 30, project: "prj_halo", pinned: true)
        mk("pr-halo-1", "Onboarding empty states", 720, project: "prj_halo", unread: true)
        mk("pr-halo-2", "Rate-limit the public API", 60, project: "prj_halo")
        mk("pr-halo-3", "Dark-mode token audit", 7200, project: "prj_halo")
        mk("pr-halo-4", "Fix the uploader client", 10000, project: "prj_halo")
        mk("pr-halo-5", "Refactor the settings screen", 12000, project: "prj_halo")
        mk("pr-web-1", "First page POC implementation", 300, project: "prj_web")
        mk("pr-un-1", "Token bucket vs sliding window", 900, project: nil)
    }

    /// CR4e proof: a grouped rail — a pinned conversation, plus recent ones across
    /// lanes (design / build / chat) with a running pill — so the Pinned/Recent
    /// sections, lane filters, and status pills all have something to show.
    private func seedFixtureRail() {
        let base = Date()
        func turn(_ tid: String, _ thread: String, _ kind: ThreadTurnKind, _ status: ThreadTurnStatus) -> ThreadTurn {
            ThreadTurn(id: tid, threadId: thread, kind: kind, status: status,
                       createdAt: base, completedAt: status.isTerminal ? base : nil, author: .worker)
        }

        // Pinned design conversation.
        if (try? store.create(id: "rail-design", title: "Redesign the onboarding flow", now: base.addingTimeInterval(-600))) != nil {
            _ = try? store.appendTurn(turn("rail-design-t", "rail-design", .designBoard, .done), toThreadId: "rail-design", now: base)
            _ = try? store.setPinned(threadId: "rail-design", pinned: true, now: base)
        }
        // Build conversation, currently running (Running filter + running pill).
        if (try? store.create(id: "rail-build", title: "Rate-limit the public API", now: base.addingTimeInterval(-120))) != nil {
            _ = try? store.appendTurn(turn("rail-build-t1", "rail-build", .teamRun, .done), toThreadId: "rail-build", now: base)
            _ = try? store.appendTurn(turn("rail-build-t2", "rail-build", .mutatingRun, .running), toThreadId: "rail-build", now: base)
        }
        // Code conversation, settled.
        if (try? store.create(id: "rail-build2", title: "Refactor the uploader client", now: base.addingTimeInterval(-300))) != nil {
            _ = try? store.appendTurn(turn("rail-build2-t", "rail-build2", .mutatingRun, .done), toThreadId: "rail-build2", now: base)
        }
        // Chat-only conversation (no lane → only under All).
        _ = try? store.create(id: "rail-chat", title: "Token bucket vs sliding window", now: base.addingTimeInterval(-900))

        reload()
    }

    /// TH2 proof: pinned thread, unread landed reply, archived thread — triage + archive view.
    private func seedFixtureRailControls() {
        let base = Date()
        func workerDone(_ id: String, threadId: String, at: Date) -> ThreadTurn {
            ThreadTurn(id: id, threadId: threadId, kind: .workerChat, status: .done,
                       createdAt: at, completedAt: at, author: .worker, text: "reply", workerId: "model_opus")
        }

        if (try? store.create(id: "th2-pinned", title: "Pinned planning thread", now: base.addingTimeInterval(-300))) != nil {
            _ = try? store.setPinned(threadId: "th2-pinned", pinned: true, now: base)
        }
        if (try? store.create(id: "th2-unread", title: "Unread worker reply", now: base.addingTimeInterval(-60))) != nil {
            _ = try? store.appendTurn(workerDone("th2-unread-w", threadId: "th2-unread", at: base), toThreadId: "th2-unread", now: base)
        }
        if (try? store.create(id: "th2-archived", title: "Archived finished thread", now: base.addingTimeInterval(-900))) != nil {
            _ = try? store.appendTurn(workerDone("th2-arch-w", threadId: "th2-archived", at: base.addingTimeInterval(-800)),
                                     toThreadId: "th2-archived", now: base)
            _ = try? store.setPinned(threadId: "th2-archived", pinned: true, now: base)
            _ = try? store.archiveThread(threadId: "th2-archived")
        }
        reload()
    }

    /// UNR-S07 proof: full unread row matrix — idle, reply, attention, running,
    /// running+unread, and selected-unread-below-fold.
    private func seedFixtureUnreadMatrix() {
        let base = Date()
        let workerId = models.first?.id ?? "model_opus"

        func userTurn(_ id: String, threadId: String, at: Date, text: String = "question") -> ThreadTurn {
            ThreadTurn(
                id: id, threadId: threadId, kind: .userMessage, status: .done,
                createdAt: at, completedAt: at, author: .user, text: text
            )
        }

        func workerTurn(
            _ id: String, threadId: String, at: Date, status: ThreadTurnStatus,
            text: String = "reply"
        ) -> ThreadTurn {
            ThreadTurn(
                id: id, threadId: threadId, kind: .workerChat, status: status,
                createdAt: at, completedAt: status.isTerminal ? at : nil,
                author: .worker, text: text, workerId: workerId
            )
        }

        // Read idle — landed reply, cursor caught up.
        if (try? store.create(id: "unr-idle", title: "Read — idle", now: base.addingTimeInterval(-500))) != nil {
            _ = try? store.appendTurn(userTurn("unr-idle-u", threadId: "unr-idle", at: base.addingTimeInterval(-480)),
                                     toThreadId: "unr-idle", now: base.addingTimeInterval(-480))
            _ = try? store.appendTurn(workerTurn("unr-idle-w", threadId: "unr-idle", at: base.addingTimeInterval(-470), status: .done),
                                     toThreadId: "unr-idle", now: base.addingTimeInterval(-470))
            _ = try? store.markRead(threadId: "unr-idle", throughTurnId: "unr-idle-w", now: base.addingTimeInterval(-469))
        }

        // Unread landed reply.
        if (try? store.create(id: "unr-reply", title: "Unread — worker reply", now: base.addingTimeInterval(-400))) != nil {
            _ = try? store.appendTurn(userTurn("unr-reply-u", threadId: "unr-reply", at: base.addingTimeInterval(-390)),
                                     toThreadId: "unr-reply", now: base.addingTimeInterval(-390))
            _ = try? store.appendTurn(workerTurn("unr-reply-w", threadId: "unr-reply", at: base.addingTimeInterval(-380), status: .done,
                                                  text: "Token bucket — allows bursts while holding the average."),
                                     toThreadId: "unr-reply", now: base.addingTimeInterval(-380))
        }

        // Unread + attention (failed worker).
        if (try? store.create(id: "unr-attention", title: "Unread — failed worker", now: base.addingTimeInterval(-350))) != nil {
            _ = try? store.appendTurn(userTurn("unr-attention-u", threadId: "unr-attention", at: base.addingTimeInterval(-340)),
                                     toThreadId: "unr-attention", now: base.addingTimeInterval(-340))
            _ = try? store.appendTurn(workerTurn("unr-attention-w", threadId: "unr-attention", at: base.addingTimeInterval(-330),
                                                  status: .failed, text: "The worker failed."),
                                     toThreadId: "unr-attention", now: base.addingTimeInterval(-330))
        }

        // Running with no unread (cursor at user, running worker not yet landed).
        if (try? store.create(id: "unr-running", title: "Running — no unread", now: base.addingTimeInterval(-300))) != nil {
            _ = try? store.appendTurn(userTurn("unr-running-u", threadId: "unr-running", at: base.addingTimeInterval(-290)),
                                     toThreadId: "unr-running", now: base.addingTimeInterval(-290))
            _ = try? store.appendTurn(workerTurn("unr-running-w", threadId: "unr-running", at: base.addingTimeInterval(-280), status: .running),
                                     toThreadId: "unr-running", now: base.addingTimeInterval(-280))
        }

        // Running + unread (landed reply unseen, newer running turn).
        if (try? store.create(id: "unr-running-unread", title: "Running + unread", now: base.addingTimeInterval(-250))) != nil {
            _ = try? store.appendTurn(userTurn("unr-run-unread-u", threadId: "unr-running-unread", at: base.addingTimeInterval(-240)),
                                     toThreadId: "unr-running-unread", now: base.addingTimeInterval(-240))
            _ = try? store.appendTurn(workerTurn("unr-run-unread-w1", threadId: "unr-running-unread", at: base.addingTimeInterval(-230),
                                                  status: .done, text: "Earlier reply you have not opened."),
                                     toThreadId: "unr-running-unread", now: base.addingTimeInterval(-230))
            _ = try? store.appendTurn(workerTurn("unr-run-unread-w2", threadId: "unr-running-unread", at: base.addingTimeInterval(-220), status: .running),
                                     toThreadId: "unr-running-unread", now: base.addingTimeInterval(-220))
        }

        // Selected unread below the fold — filler turns keep the unread anchor off-screen.
        if (try? store.create(id: "unr-selected", title: "Selected unread (below fold)", now: base.addingTimeInterval(-200))) != nil {
            for index in 0..<12 {
                let at = base.addingTimeInterval(Double(-190 + index))
                _ = try? store.appendTurn(
                    userTurn("unr-selected-u\(index)", threadId: "unr-selected", at: at,
                             text: "Earlier context message \(index + 1)."),
                    toThreadId: "unr-selected", now: at
                )
            }
            let unreadAt = base.addingTimeInterval(-60)
            _ = try? store.appendTurn(
                workerTurn("unr-selected-w", threadId: "unr-selected", at: unreadAt, status: .done,
                           text: "Unread reply below the visible viewport."),
                toThreadId: "unr-selected", now: unreadAt
            )
        }

        reload()
        if let selected = threads.first(where: { $0.id == "unr-selected" }) {
            select(selected)
        }
    }

    private func seedFixtureThreads() {
        let base = Date()
        let titles = [
            "Token bucket vs sliding window",
            "Redesign the profile screen",
            "Rate-limit the public API",
        ]
        for (index, title) in titles.enumerated() {
            _ = try? store.create(
                id: "fixture-\(index)",
                title: title,
                now: base.addingTimeInterval(TimeInterval(-index * 120))
            )
        }
        reload()
    }

    private func seedFixtureThreadWithTurns() {
        let id = "fixture-thread"
        _ = try? store.create(id: id, title: "Token bucket vs sliding window", now: Date())
        let turn = ThreadTurn(
            id: "fixture-turn-1",
            threadId: id,
            kind: .userMessage,
            status: .done,
            createdAt: Date(),
            completedAt: Date(),
            author: .user,
            text: "For per-user API rate limiting — token bucket or sliding window? Short answer + why."
        )
        _ = try? store.appendTurn(turn, toThreadId: id, now: Date())
        reload()
        selectedThreadId = id
    }

    /// CR4b proof: a user turn + a settled worker reply (designer-mock only).
    private func seedFixtureChatExchange() {
        let id = "fixture-chat"
        _ = try? store.create(id: id, title: "Token bucket vs sliding window", now: Date())
        let workerId = models.first { $0.id == "model_opus" }?.id ?? models.first?.id ?? "model_opus"
        let user = ThreadTurn(
            id: "fixture-chat-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "For per-user API rate limiting — token bucket or sliding window? Short answer + why."
        )
        let reply = ThreadTurn(
            id: "fixture-chat-reply", threadId: id, kind: .workerChat, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker,
            text: "**Token bucket.** It allows short bursts (up to the bucket size) while holding the long-run average to the refill rate — which is what per-user API limits actually want. Sliding-window log is more precise but stores every timestamp per user (memory + GC churn); sliding-window counter approximates it but still smooths bursts away. For rate limiting, allow the burst: token bucket, refill = your sustained rate, capacity = your burst budget.",
            workerId: workerId
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(reply, toThreadId: id, now: Date())
        reload()
        selectedThreadId = id
    }

    /// CR4c proof: a user question + a settled team board (designer-mock only).
    /// Seeds a durable TeamRun into the fixture run store so the board renders the
    /// real path (turn → runId → TeamRun → answers + plan).
    private func seedFixtureTeamBoard() {
        let id = "fixture-team"
        _ = try? store.create(id: id, title: "Rate-limit the public API", now: Date())

        let picks = models.filter { $0.enabled }.prefix(2)
        let m0 = picks.first?.id ?? "model_opus"
        let m1 = picks.dropFirst().first?.id ?? "model_grok"
        let w0 = Worker(id: Worker.makeID(modelId: m0, instanceIndex: 0), modelId: m0,
                        instanceIndex: 0, skillId: "answer", skillName: "Answer", purpose: .answer)
        let w1 = Worker(id: Worker.makeID(modelId: m1, instanceIndex: 0), modelId: m1,
                        instanceIndex: 0, skillId: "answer", skillName: "Answer", purpose: .answer)
        let writer = Worker(id: Worker.makeID(modelId: m0, instanceIndex: 1), modelId: m0,
                            instanceIndex: 1, skillId: "plan_writer", skillName: "Plan writer", purpose: .plan)

        var run = TeamRun(
            id: "fixture-team-run", prompt: "Per-user rate limiting for the public API — recommend an approach.",
            status: .complete, origin: .gui, presetId: "build_panel",
            workers: [w0, w1, writer],
            workerAnswers: [
                WorkerAnswer(workerId: w0.id, modelId: m0, status: .done,
                             output: "**Token bucket.** Allows controlled bursts up to the bucket size while holding the long-run average to the refill rate — the right fit for per-user API limits.",
                             durationMs: 4200),
                WorkerAnswer(workerId: w1.id, modelId: m1, status: .done,
                             output: "**Sliding-window counter.** Smoother than fixed windows and cheap to store (two counters per user); slightly approximates the boundary but avoids the double-burst edge of fixed windows.",
                             durationMs: 5100),
            ],
            createdAt: Date()
        )
        run.stages = [StageOutput(
            id: "fixture-team-plan", purpose: .plan, producedByWorkerId: writer.id,
            promptProfileId: "plan_writer", status: .done,
            payload: .plan(markdown: "**Recommendation: token bucket**, refill = sustained rate, capacity = burst budget. It satisfies the burst requirement both answers agreed on; the sliding-window counter is the fallback if memory per user must stay flat. Minority view (worker 2) preserved: prefer sliding-window if exact boundary fairness matters more than bursts."),
            startedAt: Date(), finishedAt: Date()
        )]
        _ = try? runStore.save(run, models: models)

        let user = ThreadTurn(
            id: "fixture-team-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Per-user rate limiting for the public API — send it to the team and recommend an approach."
        )
        let board = ThreadTurn(
            id: "fixture-team-board", threadId: id, kind: .teamRun, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker, runId: run.id
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(board, toThreadId: id, now: Date())
        reload()
        selectedThreadId = id
    }

    /// CR4d proof: a user instruction + a settled mutating run turn
    /// (designer-mock). Seeds a durable run carrying normal unified-run output.
    private func seedFixtureMutatingRun() {
        let id = "fixture-mutating-run"
        _ = try? store.create(id: id, title: "Add retry to the upload client", now: Date(),
                              workingDir: "/Users/you/code/uploader")
        let workerId = models.first { $0.id == "model_claude_code" }?.id
            ?? models.first { registry.manifest(for: $0)?.kind == .headlessCLI }?.id
            ?? models.first?.id ?? "model_claude_code"

        var run = TeamRun(id: "fixture-mutating-run-run", prompt: "Add retry to the upload client",
                          status: .complete, origin: .gui,
                          workers: [Worker(id: Worker.makeID(modelId: workerId, instanceIndex: 0),
                                           modelId: workerId, instanceIndex: 0,
                                           skillId: "first_principles_builder", purpose: .answer)],
                          workerAnswers: [
                              WorkerAnswer(
                                  workerId: Worker.makeID(modelId: workerId, instanceIndex: 0),
                                  modelId: workerId, status: .done,
                                  output: "Added exponential backoff (3 attempts, jitter) to `UploadClient.send`. Updated tests: `UploadClientTests.testRetriesOnTransient` passes. Ran `swift test` — 42 passing."
                              )
                          ],
                          createdAt: Date(),
                          mutating: true)
        run.stages = [StageOutput(
            id: "fixture-mutating-run-stage", purpose: .plan, producedByWorkerId: workerId,
            status: .done,
            payload: .plan(markdown: "Added exponential backoff (3 attempts, jitter) to `UploadClient.send`. Updated tests: `UploadClientTests.testRetriesOnTransient` passes. Ran `swift test` — 42 passing."),
            startedAt: Date(), finishedAt: Date()
        )]
        _ = try? runStore.save(run, models: models)

        let user = ThreadTurn(
            id: "fixture-mutating-run-user", threadId: id, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user,
            text: "Add exponential backoff retry to the upload client and run the tests."
        )
        let mutatingRun = ThreadTurn(
            id: "fixture-mutating-run-turn", threadId: id, kind: .mutatingRun, status: .done,
            createdAt: Date(), completedAt: Date(), author: .worker,
            workerId: workerId, runId: run.id, stageId: "fixture-mutating-run-stage"
        )
        _ = try? store.appendTurn(user, toThreadId: id, now: Date())
        _ = try? store.appendTurn(mutatingRun, toThreadId: id, now: Date())
        reload()
        selectedThreadId = id
    }

    // MARK: - Send

    /// Sends the composer text to the resolved worker. Reloads after each store
    /// write so the optimistic running turn appears immediately, then again when
    /// the worker settles.
    func send() {
        guard let threadId = selectedThreadId else { return }
        let message = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let requested = requestedWorkerId
        composerText = ""

        Task { @MainActor in
            do {
                let checkpoint = try await coordinator.beginSend(
                    message: message, toThreadId: threadId, requestedWorkerId: requested
                )
                reload()
                switch checkpoint {
                case .finished:
                    break
                case .awaitingInvoke(let pending):
                    _ = try await coordinator.completeSend(pending)
                    reload()
                }
            } catch {
                reload()
            }
        }
    }

    /// Completes a manual-paste turn with the user's pasted reply.
    func completeManualPaste(workerTurnId: String, manualNoteTurnId: String?, reply: String) {
        guard let threadId = selectedThreadId else { return }
        Task { @MainActor in
            _ = try? await coordinator.completeManualPaste(
                threadId: threadId, workerTurnId: workerTurnId,
                manualNoteTurnId: manualNoteTurnId, reply: reply
            )
            reload()
        }
    }

    // MARK: - Context reveal

    func revealContext(packetId: String) {
        guard let threadId = selectedThreadId else { return }
        Task { @MainActor in
            revealedPacket = await coordinator.revealContext(threadId: threadId, packetId: packetId)
        }
    }

    func dismissReveal() { revealedPacket = nil }

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
