import Foundation
import Observation
import AppKit
import AllnighterCore
import AgentOSTeam
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
    private(set) var currentPinnedSeatSpecs: [SeatSpec] = []
    private(set) var currentSynthesis: SynthesisConfig

    /// User-favorited team ids (persisted via `TeamFavorites`). Observable so every
    /// team picker re-sorts the instant a star is toggled.
    private(set) var favoriteTeamIds: [String] = TeamFavorites.ids()

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
    // badge, team health, and Setup (docs/phases/setup/01 §5).
    private(set) var toolStatuses: [ToolProbeRecord] = []
    private(set) var isDetecting = false
    /// When set, a live probe is running for this driver only (`nil` = all CLIs).
    private(set) var probingDriverId: String?
    /// One-click Cursor Agent CLI install in flight (official curl installer).
    private(set) var isInstallingCursorAgentCLI = false
    /// Last install failure detail for the Cursor repair panel (cleared on retry/success).
    private(set) var cursorAgentInstallError: String?
    /// Parked driver ids — mirrored from SetupStore so @Observable views refresh on park/unpark.
    private(set) var parkedDriverIds: Set<String> = []
    private let setupStore: SetupStore

    // Agent-powered tool discovery (the "census", tier 2): once ≥1 tool is ready,
    // a healthy agent can hunt down the tools the plain probe missed.
    private(set) var isRunningCensus = false
    private(set) var lastCensusSummary: String?

    // History
    private(set) var history: [TeamRun] = []
    private(set) var historySelection: TeamRun?

    // Review board / final spec (RB2/RB3)
    private(set) var isReviewing = false

    let registry: DriverRegistry
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

    init(setupStore: SetupStore = SetupStore()) {
        self.setupStore = setupStore
        self.parkedDriverIds = setupStore.load().parkedSet
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
        #if DEBUG
        // GUI Visual Proof Gate: seed deterministic mixed-health rows ONLY when a
        // fixture is requested. DEBUG builds only. See docs/gui/Visual_Proof_Gate.md.
        if GUIFixture.isActive {
            if let seeded = GUIFixture.seededModels(base: config.models) {
                models = seeded
            }
            toolStatuses = GUIFixture.seededToolStatuses(for: models, now: Date())
        }
        #endif
    }

    // MARK: - Panel / seats

    /// Workers referenced by the current seats, in panel order.
    var rosterModelIds: [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for s in currentPinnedSeatSpecs where seen.insert(s.modelId).inserted { ordered.append(s.modelId) }
        return ordered
    }

    var expandedAgents: [Agent] { currentPinnedSeatSpecs.expandedAgents() }

    func isSeated(_ model: Model) -> Bool {
        currentPinnedSeatSpecs.contains { $0.modelId == model.id }
    }

    func seatCount(for model: Model) -> Int {
        currentPinnedSeatSpecs.first { $0.modelId == model.id }?.count ?? 0
    }

    /// Toggle a worker in/out of the current (ad-hoc) panel. Marks the panel as
    /// no longer matching a named preset.
    func toggle(_ model: Model) {
        if let index = currentPinnedSeatSpecs.firstIndex(where: { $0.modelId == model.id }) {
            currentPinnedSeatSpecs.remove(at: index)
        } else {
            currentPinnedSeatSpecs.append(SeatSpec(modelId: model.id))
        }
        activePresetId = nil
    }

    func driverName(for model: Model) -> String {
        registry.manifest(for: model)?.displayName ?? model.driverId
    }

    func isManual(_ model: Model) -> Bool {
        registry.manifest(for: model)?.kind == .manualPaste
    }

    // MARK: - Presets

    func reloadPresets() {
        presets = AppConfig.builtInPresets(models: models) + presetStore.load()
    }

    func apply(_ preset: PanelPreset) {
        currentPinnedSeatSpecs = preset.workerSpecs
        currentSynthesis = preset.synthesis
        activePresetId = preset.id
    }

    @discardableResult
    func saveCurrentAsPreset(named name: String) -> PanelPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !currentPinnedSeatSpecs.isEmpty else { return nil }
        let preset = PanelPreset(
            id: "preset_\(UUID().uuidString.prefix(8))",
            displayName: trimmed,
            workerSpecs: currentPinnedSeatSpecs,
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

    var runSummary: String {
        let count = expandedAgents.count
        let noun = count == 1 ? "agent" : "agents"
        var parts = ["\(count) \(noun)"]
        if let judge = planWriterModel?.displayName {
            parts.append("judge: \(judge)")
        }
        let depth = currentSynthesis.analysisDepth == .combined
            ? "combined analysis + plan" : "separate analysis + plan"
        parts.append(depth)
        return parts.joined(separator: " · ")
    }

    // MARK: - Running a team

    func runTeam() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        let seats = expandedAgents
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
            answers: seats.map {
                TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? AgentStage.answer.rawValue,
                          result: WorkerRunResult(status: .queued))
            },
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
            let settled = await coordinator.runTeam(prompt: trimmed, teamWorkers: seats, models: snapshotModels, origin: .gui, presetId: presetId, runId: runId)
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
            current.stages.append(StageOutput(id: UUID().uuidString, purpose: .analysis, producedByAgentId: planWriter.id, promptProfileId: currentSynthesis.analysisProfileId, status: .done, payload: .analysis(analysis), startedAt: now, finishedAt: now))
        }
        let planText = parsed.planMarkdown ?? trimmed
        current.stages.append(StageOutput(id: UUID().uuidString, purpose: .plan, producedByAgentId: planWriter.id, promptProfileId: currentSynthesis.planProfileId, status: .done, payload: .plan(markdown: planText), startedAt: now, finishedAt: now))
        run = current
        transition(to: .planning)
        transition(to: .complete)
        manualSynthesisPrompt = nil
        persist()
    }

    func setManualAnswer(agentId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var current = run,
              let index = current.answers.firstIndex(where: { $0.memberId == agentId }) else { return }
        current.answers[index].result.status = .done
        current.answers[index].result.output = trimmed
        current.answers[index].result.timing.finishedAt = Date()
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
            lenses.append(ResolvedLens(lensId: lensId, profile: profile, model: model, manifest: manifest,
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

    func seatDisplayName(_ agentId: String, in run: TeamRun) -> String {
        guard let seat = run.workers.first(where: { $0.id == agentId }) else { return agentId }
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
        // RLR-L3: one-worker runs settle terminal as `.done` (and clocks as
        // `.timedOut`); both must persist or the app silently drops real runs.
        guard run.status == .complete || run.status == .partial || run.status == .answersIn
                || run.status == .done || run.status == .timedOut
                || (hasBoard && run.status == .failed) else { return }
        lastSavedDirectory = try? store.save(run, models: models)
        reloadHistory()
    }

    // MARK: - Doctor

    func runDoctor() {
        guard !isDoctorRunning else { return }
        isDoctorRunning = true
        let doctor = Doctor(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()))
        let snapshot = models
        let registryCopy = registry
        Task { @MainActor [weak self] in
            let results = await doctor.diagnoseAll(models: snapshot, registry: registryCopy)
            guard let self else { return }
            self.diagnoses = Dictionary(uniqueKeysWithValues: results.map { ($0.modelId, $0) })
            self.isDoctorRunning = false
        }
    }

    func diagnosis(for modelId: String) -> ModelDiagnosis? { diagnoses[modelId] }

    // MARK: - Detection (CLIDetector → canonical per-tool status)

    var readyToolCount: Int {
        benchTally.ready
    }
    var totalToolCount: Int {
        benchTally.supported
    }
    /// Shared Core tally — sole owner of ready/supported chrome numbers.
    var benchTally: BenchTally {
        BenchTallyProjector.tally(
            registry: registry,
            records: toolStatuses,
            parked: parkedDriverIds
        )
    }
    /// Every supported tool is ready — used to keep setup affordances quiet when
    /// there is nothing to fix (Track B). False on a cold, unprobed launch.
    /// Parked CLIs are excluded from both counts (they are ignored, not broken).
    var allToolsReady: Bool { benchTally.headline == .allReady }
    func toolStatus(for driverId: String) -> ToolProbeRecord? { toolStatuses.first { $0.driverId == driverId } }

    /// Durable park intent from SetupStore (also mutated by `alln drivers park`).
    func isParked(_ driverId: String) -> Bool { parkedDriverIds.contains(driverId) }

    /// Park or unpark a CLI. Preserves probe cache and model toggles.
    func setParked(_ driverId: String, parked: Bool) {
        var state = setupStore.load()
        if parked { state.park(driverId) } else { state.unpark(driverId) }
        try? setupStore.save(state)
        parkedDriverIds = state.parkedSet
    }

    /// Workers (model seats) on tools that are ready — for the "· N workers" tally.
    var readyWorkerCount: Int {
        let parked = parkedDriverIds
        let readyDrivers = Set(toolStatuses.filter { $0.status.isSmokeReady && !parked.contains($0.driverId) }.map(\.driverId))
        return models.filter { $0.enabled && readyDrivers.contains($0.driverId) }.count
    }

    /// The single source of truth for every model picker (CLI-setup redesign): a
    /// model is *available* only when it is ON (enabled — the default) AND its CLI is
    /// ready and not parked. Sorted A→Z by display name. OFF, parked, or not-ready
    /// models never appear in the Models dropdown or the title bar — they live only
    /// on the CLI setup page.
    var availableModels: [Model] {
        let parked = parkedDriverIds
        let readyDrivers = Set(toolStatuses.filter { $0.status.isSmokeReady && !parked.contains($0.driverId) }.map(\.driverId))
        // A cooling source is not available right now — so Auto's preview and the run path
        // agree (the run already substitutes around it). Live filter; never stale on expiry.
        let cooling = coolingSources
        return models
            .filter { $0.enabled && readyDrivers.contains($0.driverId) && !cooling.contains($0.driverId) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Distinct ready CLIs backing the available models (for "N available · M CLIs").
    var availableModelCLICount: Int {
        Set(availableModels.map(\.driverId)).count
    }

    /// Per-tool cards for the Team-health popover + Setup window. One card per
    /// SUPPORTED headless-CLI driver (not just per cached record) so onboarding
    /// always lists every CLI we support — a driver we've never probed shows as
    /// `.notChecked` instead of vanishing, which is what made the cold first-run
    /// page render blank.
    var setupCards: [SetupCardModel] {
        let detecting = isDetecting || isInstallingCursorAgentCLI
        let only = isInstallingCursorAgentCLI ? CursorAgentCLIInstall.driverId : probingDriverId
        return AppSetupModel.setupCards(
            registry: registry, toolStatuses: toolStatuses, models: models,
            parkedDriverIds: parkedDriverIds,
            isDetecting: detecting, probingDriverId: only)
    }

    // MARK: - Source capacity cooldowns (pre-dispatch availability)

    /// Cached per-source cooldowns — the expensive run-store scan, refreshed on demand
    /// (picker/dropdown open), NEVER per render. The "cooling NOW" decision is a live
    /// `> Date()` filter over this, so an expiry is never stale; only a brand-new cooldown
    /// needs a refresh, and one only appears when a run settles with a capacity wall.
    private(set) var cachedCooldowns: [SourceCooldown] = []

    /// Re-scan recent runs for capacity observations. Cheap; call it on a user action
    /// (opening the model picker / Models dropdown), not every render.
    func refreshCapacityCooldowns(now: Date = Date()) {
        let lookback = now.addingTimeInterval(-12 * 60 * 60)
        let observations = store.list()
            .filter { $0.createdAt >= lookback }
            .flatMap { $0.failedWorkerAnswers }
            .compactMap { $0.result.capacityObservation }
        cachedCooldowns = SourceCapacityLedger.sources(observations: observations, now: now)
    }

    /// Sources tapped out right now — live filter over the cache (never stale on expiry).
    var coolingSources: Set<String> {
        let now = Date()
        return Set(cachedCooldowns.filter { $0.coolingUntil > now }.map(\.source))
    }

    /// "At capacity · resets <time>" when this source is cooling now, else nil — the picker
    /// reason that tells the user it's transient (not a broken setup) and when it lifts.
    func capacityReason(forSource driverId: String, now: Date = Date()) -> String? {
        guard let cd = cachedCooldowns.first(where: { $0.source == driverId && $0.coolingUntil > now })
        else { return nil }
        guard let displayTime = VendorContinuityPresentation.resetDisplayTime(cd.coolingUntil, now: now)
        else { return "At capacity" }
        return "At capacity · resets \(displayTime)"
    }

    // MARK: - Compose routing data (CR3)

    /// The bench the routing composer knows about — enabled models annotated with
    /// live readiness from `toolStatuses`. Used for chip labels / lookups of models
    /// that may no longer be selectable. The Model picker itself reads
    /// `composeSelectableBench` only (never not-installed or other setup gaps).
    var composeBench: [ComposeBenchModel] {
        let cooling = coolingSources
        let parked = parkedDriverIds
        return models.filter(\.enabled).map { m in
            let rec = toolStatus(for: m.driverId)
            let isParked = parked.contains(m.driverId)
            let probeReady = !isParked && (rec?.status.isSmokeReady ?? false)
            let isCooling = cooling.contains(m.driverId)
            let ready = probeReady && !isCooling
            let reason: String?
            if isParked {
                reason = "Parked"
            } else if !probeReady {
                switch rec?.status {
                case .installedNotSignedIn?: reason = "Not signed in"
                case .shimmedNeedsConfirm?: reason = "Needs a path"
                case .probeFailed?: reason = "Probe failed"
                case .rateLimited(let observation)?: reason = DoctorReport.rateLimitedDetail(observation: observation)
                case .installedNotProbed?: reason = "Not checked"
                case .notInstalled?: reason = "Not installed"
                case .none: reason = "Not checked"
                case .ready?: reason = nil
                }
            } else if isCooling {
                reason = capacityReason(forSource: m.driverId)
            } else {
                reason = nil
            }
            return ComposeBenchModel(
                id: m.id,
                name: ModelDisplayName.format(baseName: m.displayName, modelId: m.id, driverId: m.driverId),
                driverId: m.driverId,
                cli: m.driverId.replacingOccurrences(of: "_", with: "-"),
                sub: ModelDisplayName.driverSubtitle(modelId: m.id, driverId: m.driverId),
                ready: ready, notReadyReason: ready ? nil : reason,
                supportsEffort: m.supportsEffort(registry: registry))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Models the compose target picker may offer: ON (enabled) and CLI ready.
    /// Same gate as `availableModels` — not-installed, parked, unsigned-in, cooling,
    /// and other setup gaps stay on CLI setup and never clutter the picker.
    var composeSelectableBench: [ComposeBenchModel] {
        composeBench.filter(\.ready)
    }

    /// Models that can run as an agent in your repo — enabled models whose
    /// source is a headless CLI agent.
    var composeExecutorIds: Set<String> {
        Set(models.filter(\.enabled).filter { registry.manifest(for: $0)?.kind == .headlessCLI }.map(\.id))
    }

    func composeTeams(for lane: ComposeLane) -> [ComposeTeam] {
        composeTeams(for: lane, catalog: TeamCatalog.all)
    }

    private func composeTeams(for lane: ComposeLane, catalog: [TeamDefinition]) -> [ComposeTeam] {
        let favorites = favoriteTeamIds
        let favRank = Dictionary(uniqueKeysWithValues: favorites.enumerated().map { ($1, $0) })
        let teams = catalog.filter { $0.lane == lane.workLane }
            .filter { !$0.isLabTeam && TeamVisibility.isEnabled($0.id) }.map { p -> ComposeTeam in
            let n = p.agentSpecs.count
            let noun = lane == .design ? "mockups" : (lane == .copy ? "versions" : "agents")
            return ComposeTeam(id: p.id, name: p.displayName, summary: "\(n) \(noun)",
                               isFavorite: favorites.contains(p.id), lane: lane,
                               isFeatured: BuiltInTeams.team(p.id) != nil)
        }
        // Favorites first (in the user's favorite order); the rest keep catalog order.
        return teams.enumerated().sorted { a, b in
            let ra = favRank[a.element.id], rb = favRank[b.element.id]
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    func composeDefaultTeam(for lane: ComposeLane) -> String {
        let teams = composeTeams(for: lane)
        return (teams.first { $0.isFavorite } ?? teams.first)?.id ?? ""
    }

    /// Every team across all crafts, deduped, favorites first — the composer picker
    /// is no longer lane-scoped (search spans the whole roster; favorites are the
    /// default browsing surface).
    func composeAllTeams() -> [ComposeTeam] {
        let catalog = TeamCatalog.all
        var seen = Set<String>()
        var all: [ComposeTeam] = []
        for lane in ComposeLane.allCases {
            for t in composeTeams(for: lane, catalog: catalog) where !seen.contains(t.id) {
                seen.insert(t.id)
                all.append(t)
            }
        }
        // Favorites first (favorite order), then the rest keep aggregate order.
        let favRank = Dictionary(uniqueKeysWithValues: favoriteTeamIds.enumerated().map { ($1, $0) })
        return all.enumerated().sorted { a, b in
            let ra = favRank[a.element.id], rb = favRank[b.element.id]
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Recently selected teams (most-recent first, max 3) — drives the picker's Recent
    /// section. In-memory: empty at launch, so the section is simply omitted until used.
    private(set) var recentTeamIds: [String] = []

    func noteRecentTeam(_ id: String) {
        recentTeamIds.removeAll { $0 == id }
        recentTeamIds.insert(id, at: 0)
        if recentTeamIds.count > 3 { recentTeamIds = Array(recentTeamIds.prefix(3)) }
    }

    /// Toggle a team's favorite state (persisted). Reloading the observable list
    /// re-renders every team picker (favorites move to the front).
    func toggleFavorite(_ teamId: String) {
        try? TeamFavorites.toggle(teamId)
        favoriteTeamIds = TeamFavorites.ids()
    }

    func isFavorite(_ teamId: String) -> Bool { favoriteTeamIds.contains(teamId) }

    /// Per-driver invocations resolved by detection — so GUI runs spawn through the
    /// SAME plan that passed the health probe (health == runs; docs/phases/setup/01 §10).
    private var runnerInvocations: [String: ToolInvocation] {
        AppSetupModel.invocations(from: toolStatuses)
    }

    /// Every worker invocation the app spawns goes through this composed
    /// `WorkerInvoking` stack so runs reuse the detected invocation rather than
    /// the bare command on the ambient PATH.
    private func makeWorkerRunner() -> any WorkerInvoking {
        WorkerInvokerFactory.makeWorkerInvoker(invocations: runnerInvocations)
    }

    /// HOTFIX (Launch Authority TCC): the cache-only launch path. Loads the
    /// last persisted probe records into `toolStatuses` and spawns NOTHING — no
    /// shell, no `command -v`, no `--version`, no smoke. Cold launch calls this
    /// so the first screen renders cached/unknown state without TCC prompts.
    /// Live probing happens only on explicit setup/recheck/run intent.
    func loadCachedSetupState() {
        let cached = setupStore.load()
        if !cached.records.isEmpty { toolStatuses = cached.records }
        parkedDriverIds = cached.parkedSet
    }

    /// Setup seen state (Track A): true once the user has been through setup at
    /// least once. Current launch does not auto-open setup; this persisted truth
    /// is kept for routing/copy and future setup decisions.
    var hasCompletedSetup: Bool { setupStore.load().setupCompletedAt != nil }

    /// Mark first-run setup as seen.
    /// Idempotent; preserves probe records + the assembled team.
    func markSetupCompleted() {
        var state = setupStore.load()
        guard state.setupCompletedAt == nil else { return }
        state.setupCompletedAt = Date()
        try? setupStore.save(state)
    }

    /// DEV: clear the first-run completion flag so launch re-shows onboarding —
    /// lets the founder re-experience first-run from the GUI routes sheet.
    func resetSetupCompleted() {
        var state = setupStore.load()
        state.setupCompletedAt = nil
        try? setupStore.save(state)
    }

    #if DEBUG
    /// DEBUG dev panel — seed mixed-health bench state (never persisted).
    func applyDevBenchScenario(_ scenario: String) {
        if let seeded = GUIFixture.seededModels(base: models, scenario: scenario) {
            models = seeded
        }
        toolStatuses = GUIFixture.seededToolStatuses(for: models, now: Date(), scenario: scenario)
    }
    #endif

    /// HOTFIX (Launch Authority TCC): the explicit full-probe path. Spawns real
    /// provider CLIs (resolve → version → smoke), can spend quota, and captures
    /// login-shell PATH — so it MUST be user-initiated (Re-check, Re-scan, full
    /// Setup). Never call this from launch/onAppear; use `loadCachedSetupState()`.
    ///
    /// NOTE: a process-quiet `runLightSetupRefresh(userInitiated:)` (no smoke)
    /// is intentionally NOT added yet — see Open Question 1 in the hotfix doc.
    /// Until the full Setup UI lands, launch is strictly cache-only and live
    /// checks go through this explicit full probe.
    func runFullSetupProbe(userInitiated: Bool) {
        runSetupProbe(userInitiated: userInitiated, onlyDriverId: nil)
    }

    /// Live detect + smoke. `onlyDriverId` re-probes one CLI (repair panel Run); `nil` = all.
    /// Parked CLIs are skipped on re-check-all; a single-driver repair still probes
    /// that one CLI (so Unpark → Run works).
    func runSetupProbe(userInitiated: Bool, onlyDriverId: String? = nil) {
        guard userInitiated else { loadCachedSetupState(); return }
        guard !isDetecting, !isInstallingCursorAgentCLI else { return }
        LoginShell.applyToProcessEnvironment()
        let cached = setupStore.load()
        if !cached.records.isEmpty { toolStatuses = cached.records }
        parkedDriverIds = cached.parkedSet
        isDetecting = true
        probingDriverId = onlyDriverId
        let modelLabels = ModelCatalog.probeModelLabels(registry: registry)
        let registryCopy = registry
        let storeCopy = setupStore
        let completedAt = cached.setupCompletedAt
        let parked = cached.parkedSet
        let assembled = cached.assembledTeam
        let parkedList = cached.parkedDriverIds
        Task { @MainActor [weak self] in
            let detector = AllnighterCLIDetector.make(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()), interactive: true)
            let records: [ToolProbeRecord]
            if let onlyDriverId,
               let manifest = registryCopy.all.first(where: { $0.id == onlyDriverId }) {
                let rec = await detector.probe(
                    manifest, model: modelLabels[onlyDriverId] ?? "", now: Date(), smoke: true)
                records = [rec]
            } else {
                let manifests = registryCopy.all.filter { !parked.contains($0.id) }
                let labels = modelLabels.filter { !parked.contains($0.key) }
                records = await detector.probeAll(
                    manifests, models: labels, now: Date(), smoke: true)
            }
            guard let self else { return }
            if onlyDriverId != nil {
                var merged = self.toolStatuses
                for rec in records {
                    DriverProbeRecords.upsert(rec, into: &merged)
                }
                self.toolStatuses = merged
            } else {
                // Keep last-known rows for parked CLIs that were not re-probed.
                var merged = cached.records.filter { parked.contains($0.driverId) }
                for rec in records {
                    DriverProbeRecords.upsert(rec, into: &merged)
                }
                self.toolStatuses = merged
            }
            try? storeCopy.save(.init(
                records: self.toolStatuses,
                setupCompletedAt: completedAt,
                assembledTeam: assembled,
                parkedDriverIds: parkedList
            ))
            self.parkedDriverIds = parked
            self.isDetecting = false
            self.probingDriverId = nil
            // OpenCode Go unlock reads auth.json — refresh bench roster after probe.
            self.reloadModelsFromCatalog()
        }
    }

    /// One-click Cursor Agent CLI install (official Cursor installer), then re-probe.
    /// User-initiated only — runs network install; never from launch/onAppear.
    func installCursorAgentCLI() {
        guard !isDetecting, !isInstallingCursorAgentCLI else { return }
        LoginShell.applyToProcessEnvironment()
        isInstallingCursorAgentCLI = true
        cursorAgentInstallError = nil
        Task { @MainActor [weak self] in
            let runner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())
            let outcome = await CursorAgentCLIInstall.run(commandRunner: runner)
            guard let self else { return }
            self.isInstallingCursorAgentCLI = false
            if outcome.succeeded {
                self.cursorAgentInstallError = nil
                self.runSetupProbe(userInitiated: true, onlyDriverId: CursorAgentCLIInstall.driverId)
            } else {
                self.cursorAgentInstallError = outcome.detail
            }
        }
    }

    // MARK: - Census (agent-powered tool discovery, tier 2)

    /// A model whose tool is confirmed ready — the agent we use to run the
    /// read-only discovery build order. `nil` until at least one tool is ready,
    /// because the census needs a working agent to run it (no bootstrap from
    /// zero — the plain probe must light the first lamp first).
    var censusAgent: Model? {
        let readyDriverIds = Set(toolStatuses.filter { $0.status.isSmokeReady }.map(\.driverId))
        return models.first { $0.enabled && readyDriverIds.contains($0.driverId) }
    }

    var canRunCensus: Bool {
        censusAgent != nil && !isRunningCensus && !isDetecting && hasUnresolvedSupportedTool
    }

    /// Supported headless-CLI drivers we could NOT find (notInstalled or never
    /// probed) — the discovery gap. Powers onboarding "available to add" and gates
    /// the agent fallback (offered only when there is actually a gap to fill, so
    /// it never fires when everything is already found — Track 0.3).
    var unresolvedSupportedDriverIds: [String] {
        AppCensusModel.unresolvedSupported(registry: registry, toolStatuses: toolStatuses)
    }

    var hasUnresolvedSupportedTool: Bool { !unresolvedSupportedDriverIds.isEmpty }

    /// Tier-2 discovery: have one healthy agent run the read-only census build
    /// order to find the tools the plain probe couldn't, then VERIFY every
    /// reported path locally before trusting it (health == runs). Only upgrades
    /// non-ready drivers; never downgrades a tool that's already ready.
    func runCensusDiscovery() {
        guard let agent = censusAgent, !isRunningCensus, !isDetecting,
              let manifest = registry.manifest(for: agent) else { return }
        let prompt = ToolCensus.discoveryBuildOrder(for: registry.all)
        let modelLabels = ModelCatalog.probeModelLabels(registry: registry)
        let registryCopy = registry
        let storeCopy = setupStore
        let invocations = runnerInvocations
        let completedAt = setupStore.load().setupCompletedAt
        isRunningCensus = true
        lastCensusSummary = nil
        Task { @MainActor [weak self] in
            let runner = WorkerInvokerFactory.makeWorkerInvoker(invocations: invocations)
            let outcome = await runner.collect(WorkerInvocation(
                model: agent, manifest: manifest, prompt: prompt,
                workingDirectory: AllnighterPaths.ensuredProbeScratchPath(),
                timeout: .seconds(180)
            ))
            guard let self else { return }
            guard let text = outcome.output, let census = try? ToolCensus.parse(text) else {
                self.lastCensusSummary = "Discovery didn’t return readable results."
                self.isRunningCensus = false
                return
            }
            let discovered = await CensusIngest.ingest(
                census,
                manifests: registryCopy.all,
                models: modelLabels,
                now: Date(),
                smoke: true,
                detector: AllnighterCLIDetector.make(
                    commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy())
                )
            )
            let before = Set(self.toolStatuses.filter { $0.status.isSmokeReady }.map(\.driverId))
            self.toolStatuses = AppCensusModel.mergedToolStatuses(existing: self.toolStatuses, discovered: discovered)
            try? storeCopy.save(.init(records: self.toolStatuses, setupCompletedAt: completedAt))
            let after = Set(self.toolStatuses.filter { $0.status.isSmokeReady }.map(\.driverId))
            let newlyReady = after.subtracting(before).count
            self.lastCensusSummary = newlyReady > 0
                ? "Found and verified \(newlyReady) more tool\(newlyReady == 1 ? "" : "s")."
                : "No additional ready tools found."
            self.isRunningCensus = false
        }
    }

    /// Merge census-discovered records into existing tool status. Pure so the
    /// merge policy is unit-testable: a ready tool is never downgraded; a
    /// non-ready tool is replaced only by a discovered record that's an
    /// improvement (ready, or at least carries a verified invocation); brand-new
    /// drivers are appended. Existing order is preserved.
    static func mergedToolStatuses(existing: [ToolProbeRecord], discovered: [ToolProbeRecord]) -> [ToolProbeRecord] {
        AppCensusModel.mergedToolStatuses(existing: existing, discovered: discovered)
    }

    // MARK: - History

    func reloadHistory() { history = store.list() }
    func openHistory(_ run: TeamRun) { historySelection = run }
    func closeHistory() { historySelection = nil }

    func runAgain(_ source: TeamRun) {
        prompt = source.prompt
        // Reconstruct seats from the source panel.
        var specs: [SeatSpec] = []
        var counts: [String: Int] = [:]
        for seat in source.workers { counts[seat.modelId, default: 0] += 1 }
        var seen = Set<String>()
        for seat in source.workers where seen.insert(seat.modelId).inserted {
            specs.append(SeatSpec(modelId: seat.modelId, count: counts[seat.modelId] ?? 1, skillId: seat.skillId))
        }
        currentPinnedSeatSpecs = specs
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
            if let agentId = event.payload["workerId"]?.stringValue,
               let to = event.payload["to"]?.stringValue,
               let status = WorkerAnswerStatus(rawValue: to),
               let index = current.answers.firstIndex(where: { $0.memberId == agentId }) {
                current.answers[index].result.status = status
                // Design runs ride the run-relative image path on the event so the
                // board tile fills in progressively.
                if let output = event.payload["output"]?.stringValue {
                    current.answers[index].result.output = output
                }
            }
        default:
            break
        }
        run = current
    }

}
