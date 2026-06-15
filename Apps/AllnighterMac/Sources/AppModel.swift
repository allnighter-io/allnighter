import Foundation
import Observation
import AppKit
import ImageIO
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

    // Return review (RB5)
    private(set) var isReturnReviewing = false

    // Design council (Lane 2): attach a screenshot, fan out to image engines.
    var designMode = false
    var designScreenshotURL: URL?
    var designTargetShape: TargetShape = .desktop
    var designPersonaIds: [String] = DesignPersonaLibrary.defaultPanelIDs
    private(set) var isDesigning = false

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

    // MARK: - Return review + scoring + scorecards (RB5)

    var returnReview: ReturnReviewPayload? {
        displayRun?.latestStage(.returnReview)?.payload?.returnReview
    }
    var outcomeScore: EvalScore? {
        displayRun?.latestStage(.outcomeScore)?.payload?.outcomeScore
    }

    /// Worker scorecards aggregated on demand from local run history.
    var scorecards: [WorkerScorecard] { ScorecardBuilder.build(from: history) }

    /// Evaluate the latest executor return: advisory return review + an outcome
    /// score against the spec's acceptance criteria. Closes the control loop.
    func runReturnReview() {
        guard !isReturnReviewing, let current = run,
              let dispatch = current.stages.last(where: { $0.purpose == .dispatch }),
              let ret = dispatch.payload?.executionReturn, ret.status == .done,
              let judge = judgeWorker, let manifest = registry.manifest(for: judge) else { return }
        let spec = current.latestStage(.finalSpec)?.payload?.markdown ?? current.masterPlan ?? ""
        let criteria = AcceptanceCriteria.extract(from: spec)

        isReturnReviewing = true
        let snapshotWorkers = workers
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let runner = WorkerRunner(commandRunner: SubprocessCommandRunner())
            let reviewStage = await ReturnReviewer(workerRunner: runner)
                .review(run: current, executionReturn: ret, reviewer: judge, manifest: manifest, profile: BuiltInProfiles.returnReview)
            guard var updated = self.run else { self.isReturnReviewing = false; return }
            updated.stages.append(reviewStage)

            if !criteria.isEmpty {
                let rubric = Rubric.fromAcceptanceCriteria(criteria)
                let evalCase = EvalCase(id: current.id, prompt: current.prompt, rubric: rubric)
                let score = await EvalHarness(workerRunner: runner).score(
                    artifact: ret.transcriptExcerpt ?? "", mode: "execution",
                    evalCase: evalCase, judge: judge, manifest: manifest,
                    config: EvalConfig(judgeWorkerId: judge.id, passes: 1)
                )
                updated.stages.append(StageOutput(id: UUID().uuidString, purpose: .outcomeScore, producedByWorkerId: judge.id, status: .done, payload: .outcomeScore(score)))
            }
            self.run = updated
            self.persist()
            _ = snapshotWorkers
            self.isReturnReviewing = false
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
                // Design runs ride the run-relative image path on the event so the
                // board tile fills in progressively.
                if let output = event.payload["output"]?.stringValue {
                    current.members[index].output = output
                }
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

// MARK: - Design council (Lane 2)

extension AppModel {
    /// Workers whose CLI can generate a design image headlessly (the design seats).
    var imageWorkers: [Worker] {
        workers.filter { registry.manifest(for: $0)?.canGenerateImages == true }
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
    func runFolderURL(for run: CouncilRun) -> URL {
        (try? store.runDirectory(forRunId: run.id)) ?? AllnighterPaths.runs.appendingPathComponent("run_\(run.id)")
    }

    /// Absolute URL of a seat's generated image, if it rendered.
    func imageURL(forSeat seatId: String) -> URL? {
        guard let run = displayRun, let member = run.member(seatId: seatId),
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

    func designPersona(forSeat seatId: String) -> String {
        displayRun?.panel.first { $0.id == seatId }?.stance ?? "minimal"
    }

    /// Build the design panel: each selected persona on an image worker
    /// (round-robin; a worker may fill several persona seats — self-fusion).
    private func designSeats() -> [PanelSeat] {
        let imgs = imageWorkers
        guard !imgs.isEmpty else { return [] }
        var perWorker: [String: Int] = [:]
        return designPersonaIds.enumerated().map { i, persona in
            let worker = imgs[i % imgs.count]
            let idx = perWorker[worker.id, default: 0]
            perWorker[worker.id] = idx + 1
            return PanelSeat(id: "\(worker.id)#\(idx)", workerId: worker.id, seatIndex: idx, stance: persona)
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
        run = CouncilRun(
            id: runId, prompt: trimmed, status: .draft, origin: .gui, presetId: "design_board",
            panel: seats, members: seats.map { MemberResponse(seatId: $0.id, workerId: $0.workerId, status: .queued) },
            createdAt: Date()
        )

        let coordinator = DesignCoordinator(
            imageRunner: DesignImageRunner(commandRunner: SubprocessCommandRunner()),
            registry: registry
        )
        let stream = coordinator.events
        let snapshotWorkers = workers

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let consumer = Task { @MainActor [weak self] in
                for await event in stream { self?.apply(event) }
            }
            let settled = await coordinator.generate(
                request: request, seats: seats, workers: snapshotWorkers,
                runDir: runDir, screenshotAbsolutePath: absScreenshot, runId: runId
            )
            await consumer.value
            self.run = settled
            self.persist()
            self.isDesigning = false
        }
    }

    /// Record the human's pick onto the latest board stage (logged for taste memory).
    func pickOption(seatId: String, rationale: String? = nil) {
        guard var current = run,
              let stageIndex = current.stages.lastIndex(where: { $0.purpose == .board }),
              var board = current.stages[stageIndex].payload?.board,
              let option = board.options.first(where: { $0.seatId == seatId }), option.hasImage else { return }
        let rejected = board.options.filter { $0.seatId != seatId && $0.hasImage }.map(\.seatId)
        board.chosen = ChosenOption(seatId: seatId, persona: option.persona, rationale: rationale,
                                    rejectedSeatIds: rejected, chosenAt: Date())
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
    var buildWorkers: [Worker] {
        workers.filter { registry.manifest(for: $0)?.kind == .headlessCLI }
            .sorted { (registry.manifest(for: $0)?.canReadImages == true ? 0 : 1)
                    < (registry.manifest(for: $1)?.canReadImages == true ? 0 : 1) }
    }

    func canReadImages(_ workerId: String) -> Bool {
        registry.manifest(for: workers.first { $0.id == workerId } ?? workers[0])?.canReadImages == true
    }

    var canBuildChosen: Bool {
        board?.chosen != nil && !isDispatching &&
        !dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !buildWorkers.isEmpty
    }

    /// "Build this": hand the chosen image + the redesign framing to a coding agent
    /// (reuses RB4 dispatch). The agent restyles the existing code to match.
    func buildChosen() {
        guard canBuildChosen, let current = run, let chosen = board?.chosen else { return }
        let dir = dispatchWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let workerId = dispatchWorkerId ?? buildWorkers.first?.id
        guard let workerId, let worker = workers.first(where: { $0.id == workerId }),
              let brief = DesignBriefBuilder.build(run: current, chosenSeatId: chosen.seatId,
                                                   executionWorkerId: workerId, workingDirectory: dir,
                                                   runFolder: runFolderURL(for: current)) else { return }

        let manifest = registry.manifest(for: worker)
        let index = current.stages.filter { $0.purpose == .dispatch }.count + 1
        let revealOnly = dispatchRevealOnly
        let snapshotRunId = current.id

        isDispatching = true
        Task { @MainActor [weak self] in
            guard let self else { return }
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
}
