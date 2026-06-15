import Foundation
import Observation
import AppKit
import AllnighterCore
import AllnighterEngine

/// The Mac app's single observable truth. Owns the panel (as seats), presets,
/// history and Doctor state; drives the `CouncilRunCoordinator` then the
/// `Synthesizer` (analysis → plan); applies the run-event stream live. UI reads
/// this; it never mutates run truth directly.
@MainActor
@Observable
final class AppModel {
    var workers: [Worker]
    var prompt: String = ""

    // Presets (Phase 06 tiered) + current (possibly hand-edited) selection.
    private(set) var presets: [PanelPreset] = []
    private(set) var activePresetId: String?
    private(set) var currentSeats: [PanelSeatSpec] = []
    private(set) var currentSynthesis: SynthesisConfig

    private(set) var run: CouncilRun?
    private(set) var isRunning = false
    /// Set when the chosen judge is a manual-paste worker: the assembled combined
    /// synthesis prompt for the user to run and paste back.
    private(set) var manualSynthesisPrompt: String?
    private(set) var lastSavedDirectory: URL?

    // Doctor
    private(set) var diagnoses: [String: WorkerDiagnosis] = [:]
    private(set) var isDoctorRunning = false

    // History
    private(set) var history: [CouncilRun] = []
    private(set) var historySelection: CouncilRun?

    // Review board / final spec (RB2/RB3)
    private(set) var isReviewing = false

    // Dispatch (RB4)
    var dispatchWorkingDirectory: String = ""
    var dispatchWorkerId: String?
    var dispatchRevealOnly: Bool = false
    private(set) var isDispatching = false

    private let registry: DriverRegistry
    private let store = RunStore()
    private let presetStore = PanelPresetStore()
    private let profileStore = PromptProfileStore()
    private var runTask: Task<Void, Never>?

    static let lightReviewLenses = ["security_privacy", "code_maintainer", "proof_qa"]
    static let fullReviewLenses = ["security_privacy", "code_maintainer", "proof_qa", "ui_ux", "customer_advocate", "dissent_preserver", "cost_latency_quota", "coverage_audit"]

    init() {
        let panel = AppConfig.loadDefaultPanel()
        let resolvedPanel = panel.isEmpty ? AppModel.fallbackPanel() : panel
        self.workers = resolvedPanel
        self.registry = AppConfig.loadDefaultRegistry()
        // Temporary default synthesis; replaced by the active preset below.
        self.currentSynthesis = SynthesisConfig(
            analysisProfileId: SynthesisInstructions.analysisID,
            planProfileId: SynthesisInstructions.planID
        )
        reloadPresets()
        if let first = presets.first { apply(first) }
        reloadHistory()
    }

    // MARK: - Panel / seats

    /// Workers referenced by the current seats, in panel order.
    var seatedWorkerIds: [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for s in currentSeats where seen.insert(s.workerId).inserted { ordered.append(s.workerId) }
        return ordered
    }

    var expandedSeats: [PanelSeat] { currentSeats.expandedSeats() }

    func isSeated(_ worker: Worker) -> Bool {
        currentSeats.contains { $0.workerId == worker.id }
    }

    func seatCount(for worker: Worker) -> Int {
        currentSeats.first { $0.workerId == worker.id }?.count ?? 0
    }

    /// Toggle a worker in/out of the current (ad-hoc) panel. Marks the panel as
    /// no longer matching a named preset.
    func toggle(_ worker: Worker) {
        if let index = currentSeats.firstIndex(where: { $0.workerId == worker.id }) {
            currentSeats.remove(at: index)
        } else {
            currentSeats.append(PanelSeatSpec(workerId: worker.id))
        }
        activePresetId = nil
    }

    func driverName(for worker: Worker) -> String {
        registry.manifest(for: worker)?.displayName ?? worker.driverId
    }

    func isManual(_ worker: Worker) -> Bool {
        registry.manifest(for: worker)?.kind == .manualPaste
    }

    // MARK: - Presets

    private func reloadPresets() {
        presets = AppConfig.builtInPresets(panel: workers) + presetStore.load()
    }

    func apply(_ preset: PanelPreset) {
        currentSeats = preset.seats
        currentSynthesis = preset.synthesis
        activePresetId = preset.id
    }

    @discardableResult
    func saveCurrentAsPreset(named name: String) -> PanelPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !currentSeats.isEmpty else { return nil }
        let preset = PanelPreset(
            id: "preset_\(UUID().uuidString.prefix(8))",
            displayName: trimmed,
            seats: currentSeats,
            synthesis: currentSynthesis
        )
        try? presetStore.save(preset)
        reloadPresets()
        activePresetId = preset.id
        return preset
    }

    func deletePreset(_ preset: PanelPreset) {
        guard !preset.builtIn else { return }
        try? presetStore.delete(id: preset.id)
        if activePresetId == preset.id { activePresetId = nil }
        reloadPresets()
    }

    var activePresetName: String {
        presets.first { $0.id == activePresetId }?.displayName ?? "Custom panel"
    }

    // MARK: - Judge resolution

    /// The worker that will judge (analysis + plan): the preset's explicit judge
    /// when seated, else the first seated worker that can synthesize.
    var judgeWorker: Worker? {
        let seated = workers.filter { seatedWorkerIds.contains($0.id) }
        if let id = currentSynthesis.judgeWorkerId, let chosen = seated.first(where: { $0.id == id }) {
            return chosen
        }
        return seated.first(where: \.canSynthesize) ?? seated.first
    }

    // MARK: - Call plan

    var callPlan: CallPlan {
        let preset = PanelPreset(id: "current", displayName: "current", seats: currentSeats, synthesis: currentSynthesis)
        return CallPlanEstimator().plan(for: preset, latencyByWorker: latencyByWorker())
    }

    private func latencyByWorker() -> [String: Int] {
        var durations: [String: [Int]] = [:]
        for run in history {
            for m in run.members where m.durationMs != nil {
                durations[m.workerId, default: []].append(m.durationMs! / 1000)
            }
        }
        return durations.compactMapValues { samples in
            guard !samples.isEmpty else { return nil }
            let sorted = samples.sorted()
            return sorted[sorted.count / 2]
        }
    }

    // MARK: - Running a council

    func runCouncil() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        let seats = expandedSeats
        guard !seats.isEmpty else { return }

        isRunning = true
        manualSynthesisPrompt = nil
        lastSavedDirectory = nil
        historySelection = nil
        let runId = UUID().uuidString
        run = CouncilRun(
            id: runId, prompt: trimmed, status: .draft,
            origin: .gui, presetId: activePresetId,
            panel: seats,
            members: seats.map { MemberResponse(seatId: $0.id, workerId: $0.workerId, status: .queued) },
            createdAt: Date()
        )

        let coordinator = CouncilRunCoordinator(
            workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()),
            registry: registry
        )
        let stream = coordinator.events
        let snapshotWorkers = workers
        let presetId = activePresetId

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let consumer = Task { @MainActor [weak self] in
                for await event in stream { self?.apply(event) }
            }
            let settled = await coordinator.fanOut(prompt: trimmed, seats: seats, workers: snapshotWorkers, origin: .gui, presetId: presetId, runId: runId)
            await consumer.value
            self.run = settled
            await self.performSynthesis()
            self.persist()
            self.isRunning = false
        }
    }

    func stop() { runTask?.cancel() }

    private func performSynthesis() async {
        guard var current = run, !current.answeredMembers.isEmpty, !Task.isCancelled else { return }
        guard let judge = judgeWorker, let manifest = registry.manifest(for: judge) else { return }

        // Manual judge: reveal the combined synthesis prompt; user pastes the result.
        if manifest.kind == .manualPaste {
            manualSynthesisPrompt = SynthesisPromptBuilder.combinedPrompt(
                run: current, workers: workers,
                analysisInstructions: SynthesisInstructions.analysisText,
                planInstructions: SynthesisInstructions.planText
            )
            run = current
            return
        }

        transition(to: .synthesizing)
        let synthesizer = Synthesizer(workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()))
        let stages = await synthesizer.synthesize(
            run: run ?? current, judge: judge, manifest: manifest, workers: workers, config: currentSynthesis
        )
        guard var updated = run else { return }
        updated.stages.append(contentsOf: stages)
        run = updated
        let planDone = stages.contains { $0.purpose == .plan && $0.status == .done }
        transition(to: planDone ? .complete : .partial)
    }

    func setManualSynthesis(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = run, let judge = judgeWorker else { return }
        let parsed = JudgeOutputParser.parseCombined(trimmed)
        let now = Date()
        if let analysis = parsed.analysis {
            current.stages.append(StageOutput(id: UUID().uuidString, purpose: .analysis, producedByWorkerId: judge.id, promptProfileId: currentSynthesis.analysisProfileId, status: .done, payload: .analysis(analysis), startedAt: now, finishedAt: now))
        }
        let planText = parsed.planMarkdown ?? trimmed
        current.stages.append(StageOutput(id: UUID().uuidString, purpose: .plan, producedByWorkerId: judge.id, promptProfileId: currentSynthesis.planProfileId, status: .done, payload: .plan(markdown: planText), startedAt: now, finishedAt: now))
        run = current
        transition(to: .synthesizing)
        transition(to: .complete)
        manualSynthesisPrompt = nil
        persist()
    }

    func setManualAnswer(seatId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = run,
              let index = current.members.firstIndex(where: { $0.seatId == seatId }) else { return }
        current.members[index].status = .done
        current.members[index].output = trimmed
        current.members[index].finishedAt = Date()
        run = current
    }

    // MARK: - Review board + final spec (RB2/RB3)

    /// Run advisory review lenses over the current completed run, then the
    /// first-principles finalizer. Budget routing: lenses round-robin across
    /// seated headless workers; the judge writes the final spec.
    func runReviewBoard(lensIds: [String], thenFinalize: Bool = true) {
        guard !isRunning, !isReviewing, var current = run, current.masterPlan != nil else { return }
        let profiles = profileStore.load()
        let profileByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Workers eligible to run a lens: seated, headless, with a manifest.
        let lensWorkers = workers.filter { w in
            seatedWorkerIds.contains(w.id) && registry.manifest(for: w)?.kind == .headlessCLI
        }
        let pool = lensWorkers.isEmpty ? workers.filter { registry.manifest(for: $0)?.kind == .headlessCLI } : lensWorkers
        guard !pool.isEmpty, let judge = judgeWorker, let judgeManifest = registry.manifest(for: judge) else { return }

        var lenses: [ResolvedLens] = []
        for (i, lensId) in lensIds.enumerated() {
            guard let profile = profileByID[lensId], profile.purpose == .reviewLens else { continue }
            let worker = pool[i % pool.count]
            guard let manifest = registry.manifest(for: worker) else { continue }
            lenses.append(ResolvedLens(lensId: lensId, profile: profile, worker: worker, manifest: manifest,
                                       inputSelectors: ReviewCoordinator.defaultSelectors(forLens: lensId)))
        }
        guard !lenses.isEmpty else { return }

        isReviewing = true
        transition(to: .reviewing)
        let snapshotWorkers = workers
        let finalProfile = profileByID["final_spec_v1"] ?? BuiltInProfiles.finalSpec

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let reduceRunner = ReduceRunner(workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()))
            let reviewStages = await ReviewCoordinator(reduceRunner: reduceRunner)
                .review(run: current, workers: snapshotWorkers, lenses: lenses)
            guard var updated = self.run else { self.isReviewing = false; return }
            updated.stages.append(contentsOf: reviewStages)
            self.run = updated
            current = updated

            if thenFinalize {
                self.transition(to: .finalizing)
                let finalizer = Finalizer(workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()))
                let finalStage = await finalizer.finalize(run: current, finalizer: judge, manifest: judgeManifest, workers: snapshotWorkers, profile: finalProfile)
                guard var withFinal = self.run else { self.isReviewing = false; return }
                withFinal.stages.append(finalStage)
                self.run = withFinal
                self.transition(to: finalStage.status == .done ? .complete : .partial)
            } else {
                self.transition(to: .complete)
            }
            self.persist()
            self.isReviewing = false
        }
    }

    var latestReviews: [StageOutput] {
        guard let run = displayRun else { return [] }
        return RunMarkdown.latestReviews(run)
    }

    var finalSpec: FinalSpecPayload? {
        displayRun?.latestStage(.finalSpec)?.payload?.finalSpec
    }

    // MARK: - Direct dispatch (RB4)

    var dispatches: [StageOutput] {
        (displayRun?.stages ?? []).filter { $0.purpose == .dispatch }
    }

    /// Can we hand this run to an executor? (a plan or final spec exists)
    var canDispatch: Bool { (displayRun?.masterPlan) != nil }

    /// "Implement This": build the brief and dispatch to the chosen worker in the
    /// chosen working directory. Doctor-gated; reveal-only writes artifacts without
    /// invoking. Never creates worktrees/commits.
    func dispatch() {
        guard !isDispatching, let current = run, current.masterPlan != nil else { return }
        let dir = dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return }
        let workerId = dispatchWorkerId ?? judgeWorker?.id
        guard let workerId, let worker = workers.first(where: { $0.id == workerId }),
              let brief = BriefBuilder.build(run: current, executionWorkerId: workerId, workingDirectory: dir) else { return }

        let manifest = registry.manifest(for: worker)
        let index = current.stages.filter { $0.purpose == .dispatch }.count + 1
        let revealOnly = dispatchRevealOnly
        let snapshotRunId = current.id

        isDispatching = true
        let registryCopy = registry
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Doctor gate: use a cached healthy result, else diagnose now.
            var healthy = self.diagnosis(for: workerId)?.isHealthy ?? false
            if self.diagnosis(for: workerId) == nil {
                let d = await Doctor(commandRunner: SubprocessCommandRunner()).diagnose(worker, manifest: manifest)
                self.diagnoses[workerId] = d
                healthy = d.isHealthy
            }
            let artifactsDir = (try? self.store.runDirectory(forRunId: snapshotRunId)) ?? AllnighterPaths.runs.appendingPathComponent("run_\(snapshotRunId)")
            let dispatcher = Dispatcher(workerRunner: WorkerRunner(commandRunner: SubprocessCommandRunner()))
            let stage = await dispatcher.dispatch(
                brief: brief, worker: worker, manifest: manifest, healthy: healthy,
                revealOnly: revealOnly, dispatchIndex: index, artifactsDir: artifactsDir
            )
            guard var updated = self.run else { self.isDispatching = false; return }
            updated.stages.append(stage)
            self.run = updated
            self.persist()
            self.isDispatching = false
        }
    }

    // MARK: - Derived views

    var displayRun: CouncilRun? { historySelection ?? run }

    func bundleMarkdown() -> String {
        guard let run = displayRun else { return "" }
        return RunMarkdown.bundle(run, workers: workers)
    }

    func masterPlanMarkdown() -> String {
        guard let run = displayRun else { return "" }
        return RunMarkdown.masterPlan(run)
    }

    func seatDisplayName(_ seatId: String, in run: CouncilRun) -> String {
        guard let seat = run.panel.first(where: { $0.id == seatId }) else { return seatId }
        let shares = run.panel.filter { $0.workerId == seat.workerId }.count > 1
        let name = workers.first { $0.id == seat.workerId }?.displayName ?? seat.workerId
        return seat.displayName(workerName: name, sharesWorker: shares)
    }

    private func transition(to status: RunStatus) {
        guard var current = run, current.canTransition(to: status) else { return }
        current.status = status
        run = current
    }

    private func persist() {
        guard let run, run.status == .complete || run.status == .partial || run.status == .answersIn else { return }
        lastSavedDirectory = try? store.save(run, workers: workers)
        reloadHistory()
    }

    // MARK: - Doctor

    func runDoctor() {
        guard !isDoctorRunning else { return }
        isDoctorRunning = true
        let doctor = Doctor(commandRunner: SubprocessCommandRunner())
        let snapshot = workers
        let registryCopy = registry
        Task { @MainActor [weak self] in
            let results = await doctor.diagnoseAll(workers: snapshot, registry: registryCopy)
            guard let self else { return }
            self.diagnoses = Dictionary(uniqueKeysWithValues: results.map { ($0.workerId, $0) })
            self.isDoctorRunning = false
        }
    }

    func diagnosis(for workerId: String) -> WorkerDiagnosis? { diagnoses[workerId] }

    // MARK: - History

    func reloadHistory() { history = store.list() }
    func openHistory(_ run: CouncilRun) { historySelection = run }
    func closeHistory() { historySelection = nil }

    func runAgain(_ source: CouncilRun) {
        prompt = source.prompt
        // Reconstruct seats from the source panel.
        var specs: [PanelSeatSpec] = []
        var counts: [String: Int] = [:]
        for seat in source.panel { counts[seat.workerId, default: 0] += 1 }
        var seen = Set<String>()
        for seat in source.panel where seen.insert(seat.workerId).inserted {
            specs.append(PanelSeatSpec(workerId: seat.workerId, count: counts[seat.workerId] ?? 1, stance: seat.stance))
        }
        currentSeats = specs
        activePresetId = source.presetId
        historySelection = nil
        runCouncil()
    }

    // MARK: - Quick capture

    func quickCapture(prefillClipboard: Bool) {
        historySelection = nil
        if prefillClipboard,
           prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty {
            prompt = clip
        }
    }

    // MARK: - Events

    private func apply(_ event: RunEvent) {
        guard var current = run else { return }
        switch event.kind {
        case RunEventKind.runStatusChanged:
            if let to = event.payload["to"]?.stringValue, let status = RunStatus(rawValue: to) {
                current.status = status
            }
        case RunEventKind.memberStatusChanged:
            if let seatId = event.payload["seatId"]?.stringValue,
               let to = event.payload["to"]?.stringValue,
               let status = MemberStatus(rawValue: to),
               let index = current.members.firstIndex(where: { $0.seatId == seatId }) {
                current.members[index].status = status
            }
        default:
            break
        }
        run = current
    }

    private static func fallbackPanel() -> [Worker] {
        [Worker(id: "worker_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both)]
    }
}
