import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// The Mac app's single observable truth. Owns the panel, drives the
/// `CouncilRunCoordinator`, and applies the run-event stream live (status), then
/// fills answers from the settled run. UI reads this; it never mutates run
/// truth directly.
@MainActor
@Observable
final class AppModel {
    var workers: [Worker]
    var prompt: String = ""
    var synthesisInstructions: String = SynthesisInstructions.defaultText
    private(set) var run: CouncilRun?
    private(set) var isRunning = false
    private(set) var health: [String: WorkerHealth] = [:]
    /// Set when the chosen synthesizer is a manual-paste worker: the app shows
    /// this assembled prompt for the user to run and paste back.
    private(set) var manualSynthesisPrompt: String?
    private(set) var lastSavedDirectory: URL?

    private let registry: DriverRegistry
    private let store = RunStore()
    private var runTask: Task<Void, Never>?

    init() {
        let panel = AppConfig.loadDefaultPanel()
        self.workers = panel.isEmpty ? AppModel.fallbackPanel() : panel
        self.registry = AppConfig.loadDefaultRegistry()
    }

    var enabledWorkers: [Worker] { workers.filter(\.enabled) }

    func toggle(_ worker: Worker) {
        guard let index = workers.firstIndex(where: { $0.id == worker.id }) else { return }
        workers[index].enabled.toggle()
    }

    func driverName(for worker: Worker) -> String {
        registry.manifest(for: worker)?.displayName ?? worker.driverId
    }

    func isManual(_ worker: Worker) -> Bool {
        registry.manifest(for: worker)?.kind == .manualPaste
    }

    // MARK: - Running a council

    func runCouncil() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }

        let panel = enabledWorkers
        guard !panel.isEmpty else { return }

        isRunning = true
        manualSynthesisPrompt = nil
        lastSavedDirectory = nil
        let runId = UUID().uuidString
        run = CouncilRun(
            id: runId,
            prompt: trimmed,
            status: .draft,
            panel: panel.map(\.id),
            members: panel.map { MemberResponse(workerId: $0.id, status: .queued) },
            createdAt: Date()
        )

        let coordinator = CouncilRunCoordinator(
            workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()),
            registry: registry
        )
        let stream = coordinator.events

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let consumer = Task { @MainActor [weak self] in
                for await event in stream { self?.apply(event) }
            }
            let settled = await coordinator.fanOut(prompt: trimmed, workers: panel, runId: runId)
            await consumer.value
            self.run = settled
            await self.performSynthesis()
            self.persist()
            self.isRunning = false
        }
    }

    func stop() {
        runTask?.cancel()
    }

    // MARK: - Synthesis

    /// The worker that will write the master plan: first enabled worker whose
    /// role can synthesize (default Opus 4.8).
    var synthesizerWorker: Worker? {
        enabledWorkers.first(where: \.canSynthesize)
    }

    private func performSynthesis() async {
        guard var current = run, !current.answeredMembers.isEmpty else { return }
        guard !Task.isCancelled else { return }
        guard let synthesizer = synthesizerWorker,
              let manifest = registry.manifest(for: synthesizer) else { return }

        // Manual synthesizer: surface the assembled prompt for the user.
        if manifest.kind == .manualPaste {
            manualSynthesisPrompt = SynthesisPromptBuilder.build(
                run: current, workers: workers, instructions: synthesisInstructions
            )
            current.synthesis = Synthesis(
                synthesizerWorkerId: synthesizer.id,
                instructions: SynthesisInstructions.defaultID,
                status: .pending
            )
            run = current
            return
        }

        transition(to: .synthesizing)
        let synthesizerRunner = Synthesizer(workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()))
        let synthesis = await synthesizerRunner.synthesize(
            run: run ?? current,
            synthesizer: synthesizer,
            manifest: manifest,
            workers: workers,
            instructions: synthesisInstructions
        )
        guard var updated = run else { return }
        updated.synthesis = synthesis
        run = updated
        transition(to: synthesis.status == .complete ? .complete : .partial)
    }

    func setManualSynthesis(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = run, let synthesizer = synthesizerWorker else { return }
        current.synthesis = Synthesis(
            synthesizerWorkerId: synthesizer.id,
            instructions: SynthesisInstructions.defaultID,
            masterPlanMarkdown: trimmed,
            status: .complete,
            startedAt: Date(),
            finishedAt: Date()
        )
        run = current
        transition(to: .synthesizing)
        transition(to: .complete)
        manualSynthesisPrompt = nil
        persist()
    }

    func bundleMarkdown() -> String {
        guard let run else { return "" }
        return RunMarkdown.bundle(run, workers: workers)
    }

    private func transition(to status: RunStatus) {
        guard var current = run, current.canTransition(to: status) else { return }
        current.status = status
        run = current
    }

    private func persist() {
        guard let run, run.synthesis?.status == .complete || run.status == .answersIn else { return }
        lastSavedDirectory = try? store.save(run, workers: workers)
    }

    func setManualAnswer(workerId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var current = run,
              let index = current.members.firstIndex(where: { $0.workerId == workerId }) else { return }
        current.members[index].status = .done
        current.members[index].output = trimmed
        current.members[index].finishedAt = Date()
        run = current
    }

    // MARK: - Health (Doctor-lite)

    func checkHealth() {
        let checker = WorkerHealthChecker(commandRunner: SubprocessCommandRunner())
        let snapshot = workers
        let registryCopy = registry
        Task { @MainActor [weak self] in
            for worker in snapshot {
                guard let manifest = registryCopy.manifest(for: worker) else {
                    self?.health[worker.id] = .unhealthy(reason: "no driver \(worker.driverId)")
                    continue
                }
                let result = await checker.smokeTest(manifest, model: worker.modelLabel)
                self?.health[worker.id] = result
            }
        }
    }

    // MARK: - Event application

    private func apply(_ event: RunEvent) {
        guard var current = run else { return }
        switch event.kind {
        case RunEventKind.runStatusChanged:
            if let to = event.payload["to"]?.stringValue, let status = RunStatus(rawValue: to) {
                current.status = status
            }
        case RunEventKind.memberStatusChanged:
            if let workerId = event.payload["workerId"]?.stringValue,
               let to = event.payload["to"]?.stringValue,
               let status = MemberStatus(rawValue: to),
               let index = current.members.firstIndex(where: { $0.workerId == workerId }) {
                current.members[index].status = status
            }
        default:
            break
        }
        run = current
    }

    private static func fallbackPanel() -> [Worker] {
        [Worker(id: "worker_opus", displayName: "Opus 4.8", modelLabel: "claude-opus-4.8", driverId: "claude_code", role: .both)]
    }
}
