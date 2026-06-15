import Foundation
import Observation
import AppKit
import AllnighterCore
import AllnighterEngine

/// The Mac app's single observable truth. Owns the panel, presets, history and
/// Doctor state; drives the `CouncilRunCoordinator`; applies the run-event
/// stream live (status), then fills answers from the settled run. UI reads this;
/// it never mutates run truth directly.
@MainActor
@Observable
final class AppModel {
    // Panel
    var workers: [Worker]
    var prompt: String = ""

    // Synthesis instructions (P05-S03)
    private(set) var instructionPresets: [SynthesisInstructionPreset] = []
    var selectedInstructionPresetId: String = SynthesisInstructions.defaultID
    /// The effective instruction text. Equal to the selected preset's template
    /// until the user edits it, at which point the run records custom text.
    var instructionText: String = SynthesisInstructions.defaultText

    // Panel presets (P05-S02)
    private(set) var panelPresets: [PanelPreset] = []
    private(set) var activePresetId: String?
    /// The explicit draft synthesizer (from the active preset). Falls back to the
    /// first enabled worker that can synthesize when nil.
    var synthesizerWorkerId: String?

    // History (P05-S01)
    private(set) var history: [CouncilRun] = []
    /// When set, the detail pane shows this saved run read-only instead of the
    /// live composer/run.
    private(set) var historySelection: CouncilRun?

    // Doctor (P05-S04)
    private(set) var diagnoses: [String: WorkerDiagnosis] = [:]
    private(set) var isDoctorRunning = false

    private(set) var run: CouncilRun?
    private(set) var isRunning = false
    /// Set when the chosen synthesizer is a manual-paste worker: the app shows
    /// this assembled prompt for the user to run and paste back.
    private(set) var manualSynthesisPrompt: String?
    private(set) var lastSavedDirectory: URL?

    private let registry: DriverRegistry
    private let store = RunStore()
    private let instructionStore = SynthesisInstructionStore()
    private let presetStore = PanelPresetStore()
    private var runTask: Task<Void, Never>?

    init() {
        let panel = AppConfig.loadDefaultPanel()
        let resolvedPanel = panel.isEmpty ? AppModel.fallbackPanel() : panel
        self.workers = resolvedPanel
        self.registry = AppConfig.loadDefaultRegistry()
        reloadPresets(panel: resolvedPanel)
        reloadHistory()
    }

    var enabledWorkers: [Worker] { workers.filter(\.enabled) }

    func toggle(_ worker: Worker) {
        guard let index = workers.firstIndex(where: { $0.id == worker.id }) else { return }
        workers[index].enabled.toggle()
        // A hand edit to the panel means it no longer matches the active preset.
        activePresetId = nil
    }

    func driverName(for worker: Worker) -> String {
        registry.manifest(for: worker)?.displayName ?? worker.driverId
    }

    func isManual(_ worker: Worker) -> Bool {
        registry.manifest(for: worker)?.kind == .manualPaste
    }

    // MARK: - Presets (P05-S02 / S03)

    private func reloadPresets(panel: [Worker]) {
        instructionPresets = instructionStore.load()
        let builtIn = AppConfig.builtInPanelPreset(panel: panel)
        panelPresets = [builtIn] + presetStore.load().filter { $0.id != builtIn.id }
        selectInstructionPreset(id: selectedInstructionPresetId)
    }

    var selectedInstructionPreset: SynthesisInstructionPreset? {
        instructionPresets.first { $0.id == selectedInstructionPresetId }
    }

    /// The honest record of what synthesis used: a named preset (persist its id)
    /// or custom inline text (persist the text). See `SynthesisInstructionChoice`.
    var synthesisChoice: SynthesisInstructionChoice {
        if let preset = selectedInstructionPreset, preset.template == instructionText {
            return .preset(preset)
        }
        return .custom(instructionText)
    }

    func selectInstructionPreset(id: String) {
        selectedInstructionPresetId = id
        if let preset = instructionPresets.first(where: { $0.id == id }) {
            instructionText = preset.template
        }
    }

    /// Applies a saved panel preset: enables exactly its workers, sets the draft
    /// synthesizer, and selects its synthesis-instruction preset.
    func applyPreset(_ preset: PanelPreset) {
        for index in workers.indices {
            workers[index].enabled = preset.panelWorkerIds.contains(workers[index].id)
        }
        synthesizerWorkerId = preset.draftSynthesizerWorkerId
        selectInstructionPreset(id: preset.draftSynthesisInstructionPresetId)
        activePresetId = preset.id
    }

    /// Saves the current enabled panel + synthesizer + instruction preset as a
    /// new named user preset and makes it active.
    @discardableResult
    func saveCurrentAsPreset(named name: String) -> PanelPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !enabledWorkers.isEmpty else { return nil }
        let preset = PanelPreset(
            id: "preset_\(UUID().uuidString.prefix(8))",
            displayName: trimmed,
            panelWorkerIds: enabledWorkers.map(\.id),
            draftSynthesizerWorkerId: (synthesizerWorker ?? enabledWorkers[0]).id,
            draftSynthesisInstructionPresetId: selectedInstructionPresetId
        )
        try? presetStore.save(preset)
        reloadPresets(panel: workers)
        activePresetId = preset.id
        return preset
    }

    func deletePreset(_ preset: PanelPreset) {
        guard !preset.builtIn else { return }
        try? presetStore.delete(id: preset.id)
        if activePresetId == preset.id { activePresetId = nil }
        reloadPresets(panel: workers)
    }

    /// Saves the current instruction text as a new named instruction preset.
    @discardableResult
    func saveInstructionPreset(named name: String) -> SynthesisInstructionPreset? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedText.isEmpty else { return nil }
        let preset = SynthesisInstructionPreset(
            id: "instr_\(UUID().uuidString.prefix(8))",
            displayName: trimmedName,
            template: instructionText
        )
        try? instructionStore.save(preset)
        instructionPresets = instructionStore.load()
        selectInstructionPreset(id: preset.id)
        return preset
    }

    // MARK: - History (P05-S01)

    func reloadHistory() {
        history = store.list()
    }

    func openHistory(_ run: CouncilRun) {
        historySelection = run
    }

    func closeHistory() {
        historySelection = nil
    }

    /// Reconstructs a past run's configuration (prompt, panel, synthesizer,
    /// instructions, preset) and runs it again.
    func runAgain(_ source: CouncilRun) {
        prompt = source.prompt
        for index in workers.indices {
            workers[index].enabled = source.panel.contains(workers[index].id)
        }
        synthesizerWorkerId = source.synthesis?.synthesizerWorkerId
        if let instructions = source.synthesis?.instructions {
            applyPersistedInstructions(instructions)
        }
        activePresetId = source.panelPresetId
        historySelection = nil
        runCouncil()
    }

    /// Restores instruction selection from a persisted value: a known preset id
    /// re-selects that preset; anything else is treated as literal custom text.
    private func applyPersistedInstructions(_ value: String) {
        if let preset = instructionPresets.first(where: { $0.id == value }) {
            selectInstructionPreset(id: preset.id)
        } else {
            instructionText = value
        }
    }

    func workerName(_ id: String) -> String {
        workers.first { $0.id == id }?.displayName ?? id
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
        historySelection = nil
        let runId = UUID().uuidString
        run = CouncilRun(
            id: runId,
            prompt: trimmed,
            status: .draft,
            panel: panel.map(\.id),
            members: panel.map { MemberResponse(workerId: $0.id, status: .queued) },
            panelPresetId: activePresetId,
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

    /// The worker that will write the master plan: the preset's explicit
    /// synthesizer when enabled and able, else the first enabled worker that can
    /// synthesize (default Opus 4.8 by configuration).
    var synthesizerWorker: Worker? {
        if let id = synthesizerWorkerId,
           let chosen = enabledWorkers.first(where: { $0.id == id && $0.canSynthesize }) {
            return chosen
        }
        return enabledWorkers.first(where: \.canSynthesize)
    }

    private func performSynthesis() async {
        guard var current = run, !current.answeredMembers.isEmpty else { return }
        guard !Task.isCancelled else { return }
        guard let synthesizer = synthesizerWorker,
              let manifest = registry.manifest(for: synthesizer) else { return }

        let choice = synthesisChoice

        // Manual synthesizer: surface the assembled prompt for the user.
        if manifest.kind == .manualPaste {
            manualSynthesisPrompt = SynthesisPromptBuilder.build(
                run: current, workers: workers, instructions: choice.text
            )
            current.synthesis = Synthesis(
                synthesizerWorkerId: synthesizer.id,
                instructions: choice.persistedValue,
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
            instructions: choice
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
            instructions: synthesisChoice.persistedValue,
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
        guard let run = displayRun else { return "" }
        return RunMarkdown.bundle(run, workers: workers)
    }

    /// The run currently shown in the detail pane (history selection wins).
    var displayRun: CouncilRun? { historySelection ?? run }

    private func transition(to status: RunStatus) {
        guard var current = run, current.canTransition(to: status) else { return }
        current.status = status
        run = current
    }

    private func persist() {
        guard let run, run.synthesis?.status == .complete || run.status == .answersIn else { return }
        lastSavedDirectory = try? store.save(run, workers: workers)
        reloadHistory()
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

    // MARK: - Doctor (P05-S04)

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

    var orderedDiagnoses: [WorkerDiagnosis] {
        workers.compactMap { diagnoses[$0.id] }
    }

    // MARK: - Quick capture (P05-S05)

    /// Brings the composer forward for a fresh prompt. When the composer is empty
    /// and `prefillClipboard` is set, seeds it from the clipboard so a copied
    /// question becomes a one-keystroke council run.
    func quickCapture(prefillClipboard: Bool) {
        historySelection = nil
        if prefillClipboard,
           prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let clip = NSPasteboard.general.string(forType: .string)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty {
            prompt = clip
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
