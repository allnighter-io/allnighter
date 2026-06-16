import Foundation
import Observation
import AppKit
import ImageIO
import AllnighterCore
import AllnighterEngine

/// The Mac app's single observable truth. Owns the panel (as seats), presets,
/// history and Doctor state; drives the `TeamRunCoordinator` then the
/// `PlanWriter` (analysis → plan); applies the run-event stream live. UI reads
/// this; it never mutates run truth directly.
@MainActor
@Observable
final class AppModel {
    var models: [Model]
    var prompt: String = ""

    // Presets (Phase 06 tiered) + current (possibly hand-edited) selection.
    private(set) var presets: [PanelPreset] = []
    private(set) var activePresetId: String?
    private(set) var currentWorkerSpecs: [WorkerSpec] = []
    private(set) var currentSynthesis: SynthesisConfig

    private(set) var run: TeamRun?
    private(set) var isRunning = false
    /// Set when the chosen judge is a manual-paste worker: the assembled combined
    /// synthesis prompt for the user to run and paste back.
    private(set) var manualSynthesisPrompt: String?
    private(set) var lastSavedDirectory: URL?

    // Doctor
    private(set) var diagnoses: [String: ModelDiagnosis] = [:]
    private(set) var isDoctorRunning = false

    // First-run CLI detection — canonical per-tool status shared by the health
    // badge, Council health, and Setup (docs/phases/setup/01 §5).
    private(set) var toolStatuses: [ToolProbeRecord] = []
    private(set) var isDetecting = false
    private let setupStore = SetupStore()

    // History
    private(set) var history: [TeamRun] = []
    private(set) var historySelection: TeamRun?

    // Review board / final spec (RB2/RB3)
    private(set) var isReviewing = false

    // Dispatch (RB4)
    var dispatchWorkingDirectory: String = ""
    var dispatchWorkerId: String?
    var dispatchRevealOnly: Bool = false
    private(set) var isDispatching = false

    // Return review (RB5)
    private(set) var isReturnReviewing = false

    // Design council (Lane 2): attach a screenshot, fan out to image engines.
    var designMode = false
    var designScreenshotURL: URL?
    var designTargetShape: TargetShape = .desktop
    var designPersonaIds: [String] = DesignPersonaLibrary.defaultPanelIDs
    private(set) var isDesigning = false

    private let registry: DriverRegistry
    private(set) var configurationSource: ConfigurationSource
    private(set) var registrySource: ConfigurationSource
    /// Blocking alert when bundle and embedded defaults both fail (§7 interim gate).
    var isConfigurationBroken: Bool { bundledConfiguration.isBroken }
    private let bundledConfiguration: BundledConfiguration
    private let store = RunStore()
    private let presetStore = PanelPresetStore()
    private let profileStore = PromptProfileStore()
    private var runTask: Task<Void, Never>?

    static let lightReviewLenses = ["security_privacy", "code_maintainer", "proof_qa"]
    static let fullReviewLenses = ["security_privacy", "code_maintainer", "proof_qa", "ui_ux", "customer_advocate", "dissent_preserver", "scope_discipline", "coverage_audit"]

    init() {
        let config = AppConfig.loadConfiguration()
        self.bundledConfiguration = config
        self.models = config.models
        self.registry = config.registry
        self.configurationSource = config.modelsSource
        self.registrySource = config.registrySource
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
    var rosterModelIds: [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for s in currentWorkerSpecs where seen.insert(s.modelId).inserted { ordered.append(s.modelId) }
        return ordered
    }

    var expandedWorkers: [Worker] { currentWorkerSpecs.expandedWorkers() }

    func isSeated(_ worker: Model) -> Bool {
        currentWorkerSpecs.contains { $0.modelId == worker.id }
    }

    func seatCount(for worker: Model) -> Int {
        currentWorkerSpecs.first { $0.modelId == worker.id }?.count ?? 0
    }

    /// Toggle a worker in/out of the current (ad-hoc) panel. Marks the panel as
    /// no longer matching a named preset.
    func toggle(_ worker: Model) {
        if let index = currentWorkerSpecs.firstIndex(where: { $0.modelId == worker.id }) {
            currentWorkerSpecs.remove(at: index)
        } else {
            currentWorkerSpecs.append(WorkerSpec(modelId: worker.id))
        }
        activePresetId = nil
    }

    func driverName(for worker: Model) -> String {
        registry.manifest(for: worker)?.displayName ?? worker.driverId
    }

    func isManual(_ worker: Model) -> Bool {
        registry.manifest(for: worker)?.kind == .manualPaste
    }

    // MARK: - Presets

    private func reloadPresets() {
        presets = AppConfig.builtInPresets(models: models) + presetStore.load()
    }

    func apply(_ preset: PanelPreset) {
        currentWorkerSpecs = preset.workerSpecs
        currentSynthesis = preset.synthesis
        activePresetId = preset.id
    }

    @discardableResult
    func saveCurrentAsPreset(named name: String) -> PanelPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !currentWorkerSpecs.isEmpty else { return nil }
        let preset = PanelPreset(
            id: "preset_\(UUID().uuidString.prefix(8))",
            displayName: trimmed,
            workerSpecs: currentWorkerSpecs,
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
    var planWriterModel: Model? {
        let roster = models.filter { rosterModelIds.contains($0.id) }
        if let id = currentSynthesis.planWriterModelId, let chosen = roster.first(where: { $0.id == id }) {
            return chosen
        }
        return roster.first(where: \.canWritePlan) ?? roster.first
    }

    // MARK: - Work shape

    var workOrderSummary: String {
        WorkOrder.teamSummary(
            workerCount: expandedWorkers.count,
            planWriterLabel: planWriterModel?.displayName,
            synthesis: currentSynthesis
        )
    }

    // MARK: - Running a team

    func runTeam() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        let seats = expandedWorkers
        guard !seats.isEmpty else { return }

        isRunning = true
        manualSynthesisPrompt = nil
        lastSavedDirectory = nil
        historySelection = nil
        let runId = UUID().uuidString
        run = TeamRun(
            id: runId, prompt: trimmed, status: .draft,
            origin: .gui, presetId: activePresetId,
            workers: seats,
            workerAnswers: seats.map { WorkerAnswer(workerId: $0.id, modelId: $0.modelId, status: .queued) },
            createdAt: Date()
        )

        let coordinator = TeamRunCoordinator(
            workerRunner: makeWorkerRunner(),
            registry: registry
        )
        let stream = coordinator.events
        let snapshotModels = models
        let presetId = activePresetId

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let consumer = Task { @MainActor [weak self] in
                for await event in stream { self?.apply(event) }
            }
            let settled = await coordinator.fanOut(prompt: trimmed, teamWorkers: seats, models: snapshotModels, origin: .gui, presetId: presetId, runId: runId)
            await consumer.value
            self.run = settled
            await self.performSynthesis()
            self.persist()
            self.isRunning = false
        }
    }

    func stop() { runTask?.cancel() }

    private func performSynthesis() async {
        guard var current = run, !current.answeredWorkers.isEmpty, !Task.isCancelled else { return }
        guard let planWriter = planWriterModel, let manifest = registry.manifest(for: planWriter) else { return }

        // Manual planWriter: reveal the combined synthesis prompt; user pastes the result.
        if manifest.kind == .manualPaste {
            manualSynthesisPrompt = SynthesisPromptBuilder.combinedPrompt(
                run: current, models: models,
                analysisInstructions: SynthesisInstructions.analysisText,
                planInstructions: SynthesisInstructions.planText
            )
            run = current
            return
        }

        transition(to: .planning)
        let writer = PlanWriter(workerRunner: makeWorkerRunner())
        let stages = await writer.synthesize(
            run: run ?? current, planWriter: planWriter, manifest: manifest, models: models, config: currentSynthesis
        )
        guard var updated = run else { return }
        updated.stages.append(contentsOf: stages)
        run = updated
        let planDone = stages.contains { $0.purpose == .plan && $0.status == .done }
        transition(to: planDone ? .complete : .partial)
    }

    func setManualSynthesis(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = run, let planWriter = planWriterModel else { return }
        let parsed = PlanOutputParser.parseCombined(trimmed)
        let now = Date()
        if let analysis = parsed.analysis {
            current.stages.append(StageOutput(id: UUID().uuidString, purpose: .analysis, producedByWorkerId: planWriter.id, promptProfileId: currentSynthesis.analysisProfileId, status: .done, payload: .analysis(analysis), startedAt: now, finishedAt: now))
        }
        let planText = parsed.planMarkdown ?? trimmed
        current.stages.append(StageOutput(id: UUID().uuidString, purpose: .plan, producedByWorkerId: planWriter.id, promptProfileId: currentSynthesis.planProfileId, status: .done, payload: .plan(markdown: planText), startedAt: now, finishedAt: now))
        run = current
        transition(to: .planning)
        transition(to: .complete)
        manualSynthesisPrompt = nil
        persist()
    }

    func setManualAnswer(workerId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = run,
              let index = current.workerAnswers.firstIndex(where: { $0.workerId == workerId }) else { return }
        current.workerAnswers[index].status = .done
        current.workerAnswers[index].output = trimmed
        current.workerAnswers[index].finishedAt = Date()
        run = current
    }

    // MARK: - Review board + final spec (RB2/RB3)

    /// Run advisory review lenses over the current completed run, then the
    /// first-principles finalizer. Budget routing: lenses round-robin across
    /// seated headless workers; the judge writes the final spec.
    func runReviewBoard(lensIds: [String], thenFinalize: Bool = true) {
        guard !isRunning, !isReviewing, var current = run, current.plan != nil else { return }
        let profiles = profileStore.load()
        let profileByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Workers eligible to run a lens: seated, headless, with a manifest.
        let lensModels = models.filter { m in
            rosterModelIds.contains(m.id) && registry.manifest(for: m)?.kind == .headlessCLI
        }
        let pool = lensModels.isEmpty ? models.filter { registry.manifest(for: $0)?.kind == .headlessCLI } : lensModels
        guard !pool.isEmpty, let planWriter = planWriterModel, let judgeManifest = registry.manifest(for: planWriter) else { return }

        var lenses: [ResolvedLens] = []
        for (i, lensId) in lensIds.enumerated() {
            guard let profile = profileByID[lensId], profile.purpose == .reviewLens else { continue }
            let model = pool[i % pool.count]
            guard let manifest = registry.manifest(for: model) else { continue }
            lenses.append(ResolvedLens(lensId: lensId, profile: profile, worker: model, manifest: manifest,
                                       inputSelectors: ReviewCoordinator.defaultSelectors(forLens: lensId)))
        }
        guard !lenses.isEmpty else { return }

        isReviewing = true
        transition(to: .reviewing)
        let snapshotModels = models
        let finalProfile = profileByID["final_spec_v1"] ?? BuiltInProfiles.finalSpec

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let reduceRunner = ReduceRunner(workerRunner: makeWorkerRunner())
            let reviewStages = await ReviewCoordinator(reduceRunner: reduceRunner)
                .review(run: current, models: snapshotModels, lenses: lenses)
            guard var updated = self.run else { self.isReviewing = false; return }
            updated.stages.append(contentsOf: reviewStages)
            self.run = updated
            current = updated

            if thenFinalize {
                self.transition(to: .finalizing)
                let finalizer = Finalizer(workerRunner: makeWorkerRunner())
                let finalStage = await finalizer.finalize(run: current, finalizer: planWriter, manifest: judgeManifest, models: snapshotModels, profile: finalProfile)
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
    var canDispatch: Bool { (displayRun?.plan) != nil }

    /// "Implement This": build the brief and dispatch to the chosen worker in the
    /// chosen working directory. Doctor-gated; reveal-only writes artifacts without
    /// invoking. Never creates worktrees/commits.
    func dispatch() {
        guard !isDispatching, let current = run, current.plan != nil else { return }
        let dir = dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return }
        let workerId = dispatchWorkerId ?? planWriterModel?.id
        guard let workerId, let model = models.first(where: { $0.id == workerId }),
              let brief = BriefBuilder.build(run: current, executionWorkerId: workerId, workingDirectory: dir) else { return }

        let manifest = registry.manifest(for: model)
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
                let d = await Doctor(commandRunner: SubprocessCommandRunner()).diagnose(model, manifest: manifest)
                self.diagnoses[workerId] = d
                healthy = d.isHealthy
            }
            let artifactsDir = (try? self.store.runDirectory(forRunId: snapshotRunId)) ?? AllnighterPaths.runs.appendingPathComponent("run_\(snapshotRunId)")
            let dispatcher = Dispatcher(workerRunner: makeWorkerRunner())
            let stage = await dispatcher.dispatch(
                brief: brief, worker: model, manifest: manifest, healthy: healthy,
                revealOnly: revealOnly, dispatchIndex: index, artifactsDir: artifactsDir
            )
            guard var updated = self.run else { self.isDispatching = false; return }
            updated.stages.append(stage)
            self.run = updated
            self.persist()
            self.isDispatching = false
        }
    }

    // MARK: - Return review + scoring + scorecards (RB5)

    var returnReview: ReturnReviewPayload? {
        displayRun?.latestStage(.returnReview)?.payload?.returnReview
    }
    var outcomeScore: EvalScore? {
        displayRun?.latestStage(.outcomeScore)?.payload?.outcomeScore
    }

    /// Model scorecards aggregated on demand from local run history.
    var scorecards: [WorkerScorecard] { ScorecardBuilder.build(from: history) }

    /// Evaluate the latest executor return: advisory return review + an outcome
    /// score against the spec's acceptance criteria. Closes the control loop.
    func runReturnReview() {
        guard !isReturnReviewing, let current = run,
              let dispatch = current.stages.last(where: { $0.purpose == .dispatch }),
              let ret = dispatch.payload?.executionReturn, ret.status == .done,
              let planWriter = planWriterModel, let manifest = registry.manifest(for: planWriter) else { return }
        let spec = current.latestStage(.finalSpec)?.payload?.markdown ?? current.plan ?? ""
        let criteria = AcceptanceCriteria.extract(from: spec)

        isReturnReviewing = true
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let runner = makeWorkerRunner()
            let reviewStage = await ReturnReviewer(workerRunner: runner)
                .review(run: current, executionReturn: ret, reviewer: planWriter, manifest: manifest, profile: BuiltInProfiles.returnReview)
            guard var updated = self.run else { self.isReturnReviewing = false; return }
            updated.stages.append(reviewStage)

            if !criteria.isEmpty {
                let rubric = Rubric.fromAcceptanceCriteria(criteria)
                let evalCase = EvalCase(id: current.id, prompt: current.prompt, rubric: rubric)
                let score = await EvalHarness(workerRunner: runner).score(
                    artifact: ret.transcriptExcerpt ?? "", mode: "execution",
                    evalCase: evalCase, judge: planWriter, manifest: manifest,
                    config: EvalConfig(planWriterModelId: planWriter.id, passes: 1)
                )
                updated.stages.append(StageOutput(id: UUID().uuidString, purpose: .outcomeScore, producedByWorkerId: planWriter.id, status: .done, payload: .outcomeScore(score)))
            }
            self.run = updated
            self.persist()
            self.isReturnReviewing = false
        }
    }

    // MARK: - Derived views

    var displayRun: TeamRun? { historySelection ?? run }

    func bundleMarkdown() -> String {
        guard let run = displayRun else { return "" }
        return RunMarkdown.bundle(run, models: models)
    }

    func planMarkdown() -> String {
        guard let run = displayRun else { return "" }
        return RunMarkdown.plan(run)
    }

    func seatDisplayName(_ workerId: String, in run: TeamRun) -> String {
        guard let seat = run.workers.first(where: { $0.id == workerId }) else { return workerId }
        let shares = run.workers.filter { $0.modelId == seat.modelId }.count > 1
        let name = models.first { $0.id == seat.modelId }?.displayName ?? seat.modelId
        return seat.displayName(modelName: name, sharesModel: shares)
    }

    private func transition(to status: RunStatus) {
        guard var current = run, current.canTransition(to: status) else { return }
        current.status = status
        run = current
    }

    private func persist() {
        guard let run else { return }
        // Design runs are worth keeping even when every engine failed (the board of
        // gray tiles + reasons, and the screenshot, should survive + show in History).
        let hasBoard = run.latestStage(.board) != nil
        guard run.status == .complete || run.status == .partial || run.status == .answersIn
                || (hasBoard && run.status == .failed) else { return }
        lastSavedDirectory = try? store.save(run, models: models)
        reloadHistory()
    }

    // MARK: - Doctor

    func runDoctor() {
        guard !isDoctorRunning else { return }
        isDoctorRunning = true
        let doctor = Doctor(commandRunner: SubprocessCommandRunner())
        let snapshot = models
        let registryCopy = registry
        Task { @MainActor [weak self] in
            let results = await doctor.diagnoseAll(models: snapshot, registry: registryCopy)
            guard let self else { return }
            self.diagnoses = Dictionary(uniqueKeysWithValues: results.map { ($0.modelId, $0) })
            self.isDoctorRunning = false
        }
    }

    func diagnosis(for workerId: String) -> ModelDiagnosis? { diagnoses[workerId] }

    // MARK: - Detection (CLIDetector → canonical per-tool status)

    var readyToolCount: Int { toolStatuses.filter { $0.status.isReady }.count }
    var totalToolCount: Int { registry.all.filter { $0.kind == .headlessCLI }.count }
    func toolStatus(for driverId: String) -> ToolProbeRecord? { toolStatuses.first { $0.driverId == driverId } }

    /// Workers (model seats) on tools that are ready — for the "· N workers" tally.
    var readyWorkerCount: Int {
        let readyDrivers = Set(toolStatuses.filter { $0.status.isReady }.map(\.driverId))
        return models.filter { $0.enabled && readyDrivers.contains($0.driverId) }.count
    }

    /// Per-tool cards for the Team-health popover + Setup window, mapped from the
    /// canonical probe records + manifests + the models each tool hosts.
    var setupCards: [SetupCardModel] {
        toolStatuses.compactMap { rec in
            guard let manifest = registry.manifest(id: rec.driverId) else { return nil }
            let seats = models.filter { $0.driverId == rec.driverId }.map {
                SetupCardModel.WorkerSeat(id: $0.id, name: $0.displayName, modelLabel: $0.modelLabel, isPlanWriter: $0.canWritePlan)
            }
            let route = "via " + rec.driverId.replacingOccurrences(of: "_", with: "-")
            let state: SetupCardState
            var shim: String?
            var reason: String?
            switch rec.status {
            case .ready: state = .ready
            case .installedNotSignedIn: state = .needsLogin
            case .shimmedNeedsConfirm(let r): state = .needsPath; shim = r.rawCommandV
            case .probeFailed(let r): state = .probeFailed; reason = r
            case .notInstalled: state = .notInstalled
            case .installedNotProbed: state = .installedNotProbed
            }
            return SetupCardModel(
                driverId: rec.driverId, name: manifest.displayName, route: route, version: rec.version,
                state: state, workers: seats,
                loginCommand: manifest.setup?.loginFlow?.interactiveCommand,
                installHint: manifest.setup?.installHint, docsURL: manifest.setup?.docsURL,
                shimCommand: shim, probeReason: reason)
        }
    }

    /// Per-driver invocations resolved by detection — so GUI runs spawn through the
    /// SAME plan that passed the health probe (health == runs; docs/phases/setup/01 §10).
    private var runnerInvocations: [String: ToolInvocation] {
        var map: [String: ToolInvocation] = [:]
        for record in toolStatuses { if let inv = record.invocation { map[record.driverId] = inv } }
        return map
    }

    /// Every WorkerRunner the app spawns goes through this so runs reuse the
    /// detected invocation rather than the bare command on the ambient PATH.
    private func makeWorkerRunner() -> WorkerRunner {
        WorkerRunner(commandRunner: SubprocessCommandRunner(), invocations: runnerInvocations)
    }

    /// Probe every CLI: show cached state instantly, then refresh from a live
    /// resolve → version → smoke sweep. Drives the health badge + Council health.
    func runDetection() {
        guard !isDetecting else { return }
        let cached = setupStore.load()
        if !cached.records.isEmpty { toolStatuses = cached.records }
        isDetecting = true
        var modelLabels: [String: String] = [:]
        for m in models where modelLabels[m.driverId] == nil { modelLabels[m.driverId] = m.modelLabel }
        let registryCopy = registry
        let storeCopy = setupStore
        let completedAt = cached.setupCompletedAt
        Task { @MainActor [weak self] in
            let records = await CLIDetector(commandRunner: SubprocessCommandRunner())
                .probeAll(registryCopy.all, models: modelLabels, now: Date())
            guard let self else { return }
            self.toolStatuses = records
            try? storeCopy.save(.init(records: records, setupCompletedAt: completedAt))
            self.isDetecting = false
        }
    }

    // MARK: - History

    func reloadHistory() { history = store.list() }
    func openHistory(_ run: TeamRun) { historySelection = run }
    func closeHistory() { historySelection = nil }

    func runAgain(_ source: TeamRun) {
        prompt = source.prompt
        // Reconstruct seats from the source panel.
        var specs: [WorkerSpec] = []
        var counts: [String: Int] = [:]
        for seat in source.workers { counts[seat.modelId, default: 0] += 1 }
        var seen = Set<String>()
        for seat in source.workers where seen.insert(seat.modelId).inserted {
            specs.append(WorkerSpec(modelId: seat.modelId, count: counts[seat.modelId] ?? 1, skillId: seat.skillId))
        }
        currentWorkerSpecs = specs
        activePresetId = source.presetId
        historySelection = nil
        runTeam()
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
        case RunEventKind.workerStatusChanged:
            if let workerId = event.payload["workerId"]?.stringValue,
               let to = event.payload["to"]?.stringValue,
               let status = WorkerAnswerStatus(rawValue: to),
               let index = current.workerAnswers.firstIndex(where: { $0.workerId == workerId }) {
                current.workerAnswers[index].status = status
                // Design runs ride the run-relative image path on the event so the
                // board tile fills in progressively.
                if let output = event.payload["output"]?.stringValue {
                    current.workerAnswers[index].output = output
                }
            }
        default:
            break
        }
        run = current
    }

}

// MARK: - Design council (Lane 2)

extension AppModel {
    /// Workers whose CLI can generate a design image headlessly (the design seats).
    var imageWorkers: [Model] {
        models.filter { registry.manifest(for: $0)?.canGenerateImages == true }
    }

    /// The current board (live from members during the run; persisted at settle).
    var board: BoardPayload? { displayRun?.latestStage(.board)?.payload?.board }

    var canRunDesign: Bool {
        !isDesigning && !isRunning && !imageWorkers.isEmpty && !designPersonaIds.isEmpty &&
        (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || designScreenshotURL != nil)
    }

    func attachScreenshot(_ url: URL) {
        designScreenshotURL = url
        designTargetShape = inferredTargetShape(from: url) ?? designTargetShape
    }

    func clearScreenshot() { designScreenshotURL = nil }

    /// The run folder on disk (idempotent create).
    func runFolderURL(for run: TeamRun) -> URL {
        (try? store.runDirectory(forRunId: run.id)) ?? AllnighterPaths.runs.appendingPathComponent("run_\(run.id)")
    }

    /// Absolute URL of a seat's generated image, if it rendered.
    func imageURL(forSeat workerId: String) -> URL? {
        guard let run = displayRun, let member = run.workerAnswer(workerId: workerId),
              member.status == .done, let rel = member.output, !rel.isEmpty else { return nil }
        return runFolderURL(for: run).appendingPathComponent(rel)
    }

    /// The "before" screenshot URL (persisted path at settle, else the attachment).
    var screenshotURL: URL? {
        if let run = displayRun, let rel = run.latestStage(.board)?.payload?.board?.screenshotPath {
            return runFolderURL(for: run).appendingPathComponent(rel)
        }
        return designScreenshotURL
    }

    func designPersona(forSeat workerId: String) -> String {
        displayRun?.workers.first { $0.id == workerId }?.skillId ?? "minimal"
    }

    /// Build the design panel: each selected persona on an image worker
    /// (round-robin; a worker may fill several persona seats — self-fusion).
    private func designSeats() -> [Worker] {
        let imgs = imageWorkers
        guard !imgs.isEmpty else { return [] }
        var perWorker: [String: Int] = [:]
        return designPersonaIds.enumerated().map { i, persona in
            let model = imgs[i % imgs.count]
            let idx = perWorker[model.id, default: 0]
            perWorker[model.id] = idx + 1
            return Worker(id: "\(model.id)#\(idx)", modelId: model.id, instanceIndex: idx, skillId: persona)
        }
    }

    /// Attach a screenshot, fan out to the image engines × personas, reveal the
    /// board. The board is the first truth surface — no AI verdict precedes it.
    func runDesign() {
        guard canRunDesign else { return }
        let seats = designSeats()
        guard !seats.isEmpty else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        isDesigning = true
        historySelection = nil
        lastSavedDirectory = nil
        let runId = UUID().uuidString
        let runDir = (try? store.runDirectory(forRunId: runId)) ?? AllnighterPaths.runs.appendingPathComponent("run_\(runId)")
        try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        // Copy the attached screenshot into the run folder (run-relative truth).
        var relScreenshot: String?
        var absScreenshot: String?
        if let src = designScreenshotURL {
            let dest = runDir.appendingPathComponent("screenshot.png")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil {
                relScreenshot = "screenshot.png"
                absScreenshot = dest.path
            }
        }

        let request = DesignRequest(prompt: trimmed, personaIds: designPersonaIds,
                                    screenshotPath: relScreenshot, targetShape: designTargetShape)
        run = TeamRun(
            id: runId, prompt: trimmed, status: .draft, origin: .gui, presetId: "design_board",
            workers: seats, workerAnswers: seats.map { WorkerAnswer(workerId: $0.id, modelId: $0.modelId, status: .queued) },
            createdAt: Date()
        )

        let coordinator = DesignCoordinator(
            imageRunner: DesignImageRunner(commandRunner: SubprocessCommandRunner()),
            registry: registry
        )
        let stream = coordinator.events
        let snapshotModels = models

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let consumer = Task { @MainActor [weak self] in
                for await event in stream { self?.apply(event) }
            }
            let settled = await coordinator.generate(
                request: request, teamWorkers: seats, models: snapshotModels,
                runDir: runDir, screenshotAbsolutePath: absScreenshot, runId: runId
            )
            await consumer.value
            self.run = settled
            self.persist()
            self.isDesigning = false
        }
    }

    /// Record the human's pick onto the latest board stage (logged for taste memory).
    func pickOption(workerId: String, rationale: String? = nil) {
        guard historySelection == nil, var current = run,
              let stageIndex = current.stages.lastIndex(where: { $0.purpose == .board }),
              var board = current.stages[stageIndex].payload?.board,
              let option = board.options.first(where: { $0.workerId == workerId }), option.hasImage else { return }
        let rejected = board.options.filter { $0.workerId != workerId && $0.hasImage }.map(\.workerId)
        board.chosen = ChosenOption(workerId: workerId, persona: option.persona, rationale: rationale,
                                    rejectedWorkerIds: rejected, chosenAt: Date())
        current.stages[stageIndex].payload = .board(board)
        run = current
        persist()
    }

    private func inferredTargetShape(from url: URL) -> TargetShape? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double, h > 0 else { return nil }
        let aspect = w / h
        if aspect < 0.6 { return .mobile }
        if aspect > 1.8 { return .desktop }
        return nil
    }

    // MARK: - Build this (Design2)

    /// Headless workers, image-readers (Claude Code, Codex) first — the build
    /// implementer must see the chosen image.
    var buildWorkers: [Model] {
        models.filter { registry.manifest(for: $0)?.kind == .headlessCLI }
            .sorted { (registry.manifest(for: $0)?.canReadImages == true ? 0 : 1)
                    < (registry.manifest(for: $1)?.canReadImages == true ? 0 : 1) }
    }

    func canReadImages(_ workerId: String) -> Bool {
        guard let m = models.first(where: { $0.id == workerId }) else { return false }
        return registry.manifest(for: m)?.canReadImages == true
    }

    var canBuildChosen: Bool {
        board?.chosen != nil && !isDispatching &&
        !dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !buildWorkers.isEmpty
    }

    /// "Build this": hand the chosen image + the redesign framing to a coding agent
    /// (reuses RB4 dispatch). The agent restyles the existing code to match.
    func buildChosen() {
        guard historySelection == nil, canBuildChosen, let current = run, let chosen = board?.chosen else { return }
        let dir = dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let workerId = dispatchWorkerId ?? buildWorkers.first?.id
        guard let workerId, let model = models.first(where: { $0.id == workerId }),
              let brief = DesignBriefBuilder.build(run: current, chosenSeatId: chosen.workerId,
                                                   executionWorkerId: workerId, workingDirectory: dir,
                                                   runFolder: runFolderURL(for: current)) else { return }

        let manifest = registry.manifest(for: model)
        let index = current.stages.filter { $0.purpose == .dispatch }.count + 1
        let revealOnly = dispatchRevealOnly
        let snapshotRunId = current.id

        isDispatching = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            var healthy = self.diagnosis(for: workerId)?.isHealthy ?? false
            if self.diagnosis(for: workerId) == nil {
                let d = await Doctor(commandRunner: SubprocessCommandRunner()).diagnose(model, manifest: manifest)
                self.diagnoses[workerId] = d
                healthy = d.isHealthy
            }
            let artifactsDir = (try? self.store.runDirectory(forRunId: snapshotRunId)) ?? AllnighterPaths.runs.appendingPathComponent("run_\(snapshotRunId)")
            let dispatcher = Dispatcher(workerRunner: makeWorkerRunner())
            let stage = await dispatcher.dispatch(
                brief: brief, worker: model, manifest: manifest, healthy: healthy,
                revealOnly: revealOnly, dispatchIndex: index, artifactsDir: artifactsDir
            )
            guard var updated = self.run else { self.isDispatching = false; return }
            updated.stages.append(stage)
            self.run = updated
            self.persist()
            self.isDispatching = false
        }
    }
}
