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

    /// Pending text from a global quick-capture hotkey (⌥⌘Space or menu "Quick capture").
    /// The currently-visible RoutingComposer will adopt it into its editor (only if
    /// that editor is empty), then clear the pending. Quick capture creates a new
    /// thread by default per the threads phase spec.
    var pendingQuickCaptureText: String?

    /// The context packet being revealed, if the reveal sheet is open.
    private(set) var revealedPacket: ThreadContextPacket?

    let models: [Model]
    private let store: ThreadStore
    private let coordinator: WorkerChatCoordinator
    private let registry: DriverRegistry

    /// Production init: self-sufficient, loads the same config as AppModel and
    /// invokes real CLIs. GUI fixtures use an isolated temp store.
    convenience init() {
        let config = AppConfig.loadConfiguration()
        #if DEBUG
        let store: ThreadStore
        if GUIFixture.isActive {
            let name = GUIFixture.active ?? "fixture"
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("allnighter-gui-fixture-\(name)", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = ThreadStore(rootDirectory: root)
        } else {
            store = ThreadStore()
        }
        #else
        let store = ThreadStore()
        #endif
        self.init(
            store: store,
            registry: config.registry,
            models: config.models,
            runner: WorkerRunner(commandRunner: SubprocessCommandRunner())
        )
        #if DEBUG
        if let fixture = GUIFixture.active {
            applyFixture(fixture)
        }
        #endif
    }

    /// Designated init — tests inject a temp store and a mock runner.
    init(store: ThreadStore, registry: DriverRegistry, models: [Model], runner: WorkerRunner) {
        self.store = store
        self.registry = registry
        self.models = models
        self.coordinator = WorkerChatCoordinator(
            store: store, runner: runner, registry: registry, models: models
        )
        reload()
    }

    // MARK: - Derived

    /// Threads in triage order for the list.
    var triagedThreads: [WorkThread] { ThreadsPresenter.triaged(threads) }

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
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func driverName(for workerId: String) -> String {
        guard let model = models.first(where: { $0.id == workerId }) else { return workerId }
        return registry.manifest(for: model)?.displayName ?? model.driverId
    }

    // MARK: - List / selection

    func reload() {
        threads = store.list()
        if let id = selectedThreadId, !threads.contains(where: { $0.id == id }) {
            selectedThreadId = threads.first?.id
        }
    }

    func select(_ thread: WorkThread) {
        selectedThreadId = thread.id
        requestedWorkerId = nil
    }

    @discardableResult
    func newThread(title: String = "New thread", workingDir: String? = nil) -> WorkThread? {
        let thread = try? store.create(
            id: UUID().uuidString, title: title, now: Date(), workingDir: workingDir
        )
        reload()
        if let thread { selectedThreadId = thread.id }
        return thread
    }

    /// Empty thread for the "Start a work order" flow.
    func newWorkOrder() {
        _ = newThread(title: "New work order")
    }

    // MARK: - Routing composer (CR4a user turn; CR4b chat runs the model)

    /// Global quick capture (hotkey / menu bar): create a fresh thread (by default,
    /// per Persistent_Work_Threads) and stage clipboard content for the composer
    /// that will mount for it. If clipboardText is empty this still surfaces the
    /// composer for a new work order.
    func applyQuickCapture(clipboardText: String?) {
        let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = clip.isEmpty ? "New work order" : Self.title(from: clip)
        _ = newThread(title: title)
        if !clip.isEmpty {
            pendingQuickCaptureText = clip
        }
    }

    /// Send from the routing composer. Resolves/creates the thread, then routes
    /// by mode: Chat runs the chosen model and streams its reply back as a
    /// `workerChat` turn (CR4b); Fan out / Execute record the user turn for now
    /// (their runs land in CR4c/CR4d — never a faked result).
    func sendRouting(_ routing: ComposeRouting, createThread: Bool = false) {
        let message = routing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        let threadId: String
        if createThread || selectedThreadId == nil {
            guard let thread = try? store.create(
                id: UUID().uuidString, title: Self.title(from: message), now: Date()
            ) else { return }
            reload()
            selectedThreadId = thread.id
            threadId = thread.id
        } else if let id = selectedThreadId {
            threadId = id
        } else {
            return
        }

        switch routing.mode {
        case .chat:
            runChat(message: message, toThreadId: threadId, workerId: routing.to)
        case .fanout, .exec:
            // CR4c/CR4d: team board + dispatch. For now record the intent as a
            // user turn so nothing is lost or faked.
            appendUserTurn(message, toThreadId: threadId)
        }
    }

    /// Chat: hand the message to the chosen model via the coordinator, which
    /// persists the user turn + an optimistic running `workerChat` turn, invokes
    /// the worker through the cached invocation (health == runs), and settles the
    /// reply in place.
    private func runChat(message: String, toThreadId threadId: String, workerId: String) {
        Task { @MainActor in
            let sendTask = Task.detached { [coordinator] in
                try await coordinator.send(message: message, toThreadId: threadId, requestedWorkerId: workerId)
            }
            reload()                  // show the optimistic running turn at once
            _ = try? await sendTask.value
            reload()                  // settle the worker reply (or honest failure)
        }
    }

    private func appendUserTurn(_ message: String, toThreadId threadId: String) {
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: threadId, kind: .userMessage, status: .done,
            createdAt: Date(), completedAt: Date(), author: .user, text: message
        )
        try? store.append(turn, toThreadId: threadId, now: Date())
        reload()
    }

    private static func title(from text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New work order" }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }

    // MARK: - GUI fixtures

    func applyFixture(_ fixture: String) {
        switch fixture {
        case "thread-empty":
            _ = newThread(title: "New work order")
        case "home-with-threads":
            seedFixtureThreads()
            selectedThreadId = nil
        case "thread-with-turns":
            seedFixtureThreadWithTurns()
        case "thread-chat":
            seedFixtureChatExchange()
        default:
            break
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
        _ = try? store.append(turn, toThreadId: id, now: Date())
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
        _ = try? store.append(user, toThreadId: id, now: Date())
        _ = try? store.append(reply, toThreadId: id, now: Date())
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
                // The coordinator persists optimistic turns before awaiting the
                // invoke; poll the store once so the UI shows running right away.
                let sendTask = Task.detached { [coordinator] in
                    try await coordinator.send(message: message, toThreadId: threadId, requestedWorkerId: requested)
                }
                // Brief optimistic refresh, then the settled refresh.
                reload()
                _ = try await sendTask.value
                reload()
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
}
