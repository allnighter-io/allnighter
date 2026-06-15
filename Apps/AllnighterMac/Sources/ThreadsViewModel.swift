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

    /// The context packet being revealed, if the reveal sheet is open.
    private(set) var revealedPacket: ThreadContextPacket?

    let models: [Model]
    private let store: ThreadStore
    private let coordinator: WorkerChatCoordinator
    private let registry: DriverRegistry

    /// Production init: self-sufficient, loads the same config as AppModel and
    /// invokes real CLIs.
    convenience init() {
        let config = AppConfig.loadConfiguration()
        self.init(
            store: ThreadStore(),
            registry: config.registry,
            models: config.models,
            runner: WorkerRunner(commandRunner: SubprocessCommandRunner())
        )
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
