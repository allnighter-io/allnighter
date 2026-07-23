import Foundation
import AllnighterCore
import AgentOSTeam

/// Panel round coordinator (`docs/phases/Pilot_Panel.md` PN-S03) — session-led blind
/// jury control plane. Mirrors Pilot's durability-as-mutex pattern: the first thing a
/// successful `runRound` does is flip status to `.running` (with `owner.pid`) BEFORE
/// the (possibly long) seat dispatch, so a concurrent round refuses with
/// `PANEL_ROUND_IN_FLIGHT`.
///
/// **Rerun storage (decision):** `--seats a,b` is a **new attempt on the same round**,
/// not a new round number. The attempt's results REPLACE those seats in the round's
/// merged `seatResults`. Full-roster dispatches start a new round. Max-rounds ceilings
/// apply only when starting a NEW round (reruns of the current round are exempt).
///
/// **Built-in brief (decision 6):** `brief == nil` on round 1 uses
/// `PanelSeatPrompt.builtinBrief`. `brief == nil` on round 2+ is a usage error (focus
/// brief required — cheap nudge toward the rejection-carry discipline).
public struct PanelCoordinator: Sendable {
    /// Transport-agnostic progress events (like `RelayCoordinator.RelayEvent`). CLI maps
    /// these to NDJSON; a GUI could map them elsewhere.
    public enum PanelEvent: Sendable, Equatable {
        case seatStarted(seat: String, round: Int, attempt: Int)
        case seatSettled(seat: String, round: Int, attempt: Int, status: String)
        case roundSettled(round: Int, attempt: Int)
    }

    public typealias EventSink = @Sendable (PanelEvent) -> Void

    /// Injectable seat dispatch for tests. Production path builds a
    /// `CatalogRunCoordinator` run over the PN-S02 answer path with per-seat prompts,
    /// RO-enforced manifests (real root) or clone-isolated cwd (PN-S06).
    public typealias SeatDispatch = @Sendable (
        _ seats: [PanelSeat],
        _ brief: String,
        _ targetPath: String,
        _ projectRoot: String,
        _ panelId: String
    ) async -> [SeatResult]

    public enum StartError: Swift.Error, Sendable, Equatable {
        case emptyRoster
        case targetMissing(path: String)
    }

    public enum RoundError: Swift.Error, Sendable, Equatable {
        case panelNotFound
        case roundInFlight
        case notAwaitingPM(status: String)
        case targetMissing(path: String)
        case briefRequired
        case maxRoundsReached(max: Int)
        case unknownSeats([String])
        case emptySeatFilter
    }

    public enum DoneError: Swift.Error, Sendable, Equatable {
        case panelNotFound
        case roundInFlight
        case alreadyDone
    }

    public struct RoundResult: Sendable, Equatable {
        public var state: PanelState
        public var round: PanelRound
        public var attempt: PanelRoundAttempt

        public init(state: PanelState, round: PanelRound, attempt: PanelRoundAttempt) {
            self.state = state
            self.round = round
            self.attempt = attempt
        }
    }

    public struct Config: Sendable {
        public var projectRoot: String
        public var projectId: String
        public var targetPath: String
        public var teamId: String?
        public var seats: [PanelSeat]
        public var maxRounds: Int

        public init(
            projectRoot: String,
            projectId: String,
            targetPath: String,
            teamId: String? = nil,
            seats: [PanelSeat],
            maxRounds: Int = 10
        ) {
            self.projectRoot = projectRoot
            self.projectId = projectId
            self.targetPath = targetPath
            self.teamId = teamId
            self.seats = seats
            self.maxRounds = max(1, maxRounds)
        }
    }

    private let stateStore: PanelStateStore
    private let seatDispatch: SeatDispatch
    /// Optional (Pilot_Panel.md decision 12 / PN-S05): projects the panel onto a
    /// `WorkThread` so the Mac inbox shows the jury live. Pure composition — `nil` by
    /// default so every existing test/headless caller keeps working unchanged; CLI
    /// constructs one so real panels always show in the inbox.
    private let threadProjector: PanelThreadProjector?
    private let now: @Sendable () -> Date
    private let idFactory: @Sendable () -> String
    /// Injected panels root for clone isolation (tests); nil → `AllnighterPaths.panels`.
    private let panelsRoot: URL?

    public init(
        stateStore: PanelStateStore = PanelStateStore(),
        seatDispatch: SeatDispatch? = nil,
        threadProjector: PanelThreadProjector? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        idFactory: @escaping @Sendable () -> String = { PanelState.makeId() },
        workerRunner: (any WorkerInvoking)? = nil,
        models: [Model] = [],
        registry: DriverRegistry = DriverRegistry(),
        panelsRoot: URL? = nil,
        cloneCopier: PanelSeatIsolation.Copier? = nil
    ) {
        self.stateStore = stateStore
        self.threadProjector = threadProjector
        self.now = now
        self.idFactory = idFactory
        self.panelsRoot = panelsRoot
        if let seatDispatch {
            self.seatDispatch = seatDispatch
        } else {
            let runner = workerRunner
            let models = models
            let registry = registry
            let panelsRoot = panelsRoot
            let copier = cloneCopier
            let stateStore = stateStore
            let projector = threadProjector
            let now = now
            self.seatDispatch = { seats, brief, targetPath, projectRoot, panelId in
                await PanelCoordinator.defaultDispatch(
                    seats: seats,
                    brief: brief,
                    targetPath: targetPath,
                    projectRoot: projectRoot,
                    panelId: panelId,
                    workerRunner: runner,
                    models: models,
                    registry: registry,
                    panelsRoot: panelsRoot,
                    cloneCopier: copier,
                    progress: { run in
                        PanelCoordinator.persistDispatchProgress(
                            run: run,
                            seats: seats,
                            panelId: panelId,
                            stateStore: stateStore
                        )
                        if let state = stateStore.load(id: panelId) {
                            projector?.sync(state: state, now: now())
                        }
                    }
                )
            }
        }
    }

    // MARK: - start

    /// Creates a parked panel at `awaitingPM` with zero rounds. Does not dispatch.
    /// Isolation is planned (driver RO vs clone) but never refuses a seat — PN-S06.
    public func start(
        config: Config,
        models: [Model] = [],
        registry: DriverRegistry = DriverRegistry()
    ) -> Result<PanelState, StartError> {
        guard !config.seats.isEmpty else { return .failure(.emptyRoster) }
        let resolvedTarget = Self.resolveTargetPath(config.targetPath, projectRoot: config.projectRoot)
        if PanelState.contentHash(ofFileAt: resolvedTarget) == nil {
            return .failure(.targetMissing(path: config.targetPath))
        }

        let state = PanelState(
            id: idFactory(),
            projectRoot: config.projectRoot,
            projectId: config.projectId,
            targetPath: config.targetPath,
            teamId: config.teamId,
            seats: config.seats,
            status: .awaitingPM,
            maxRounds: config.maxRounds,
            rounds: [],
            createdAt: now()
        )
        threadProjector?.started(state: state, projectId: config.projectId)
        persist(state)
        return .success(state)
    }

    /// Isolation plan for a roster (driver RO vs clone). Pure; no materialization.
    public static func isolationPlan(
        seats: [PanelSeat],
        models: [Model],
        registry: DriverRegistry
    ) -> [PanelSeatIsolation.SeatPlan] {
        PanelSeatIsolation.plan(seats: seats, models: models, registry: registry)
    }

    // MARK: - runRound

    /// Dispatches one round (or a seat-subset rerun of the current round). Blocks until
    /// every seat settles. Partial failures are kept — the round always settles with
    /// per-seat status + the findings that arrived.
    public func runRound(
        panelId: String,
        brief: String? = nil,
        seatFilter: [String]? = nil,
        events: EventSink? = nil
    ) async -> Result<RoundResult, RoundError> {
        guard var state = stateStore.load(id: panelId) else { return .failure(.panelNotFound) }
        if state.status == .running { return .failure(.roundInFlight) }
        guard state.status == .awaitingPM else {
            return .failure(.notAwaitingPM(status: state.status.rawValue))
        }

        let isRerun = seatFilter != nil
        let filterIds: [String]?
        if let raw = seatFilter {
            let ids = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !ids.isEmpty else { return .failure(.emptySeatFilter) }
            let rosterIds = Set(state.seats.map(\.workerId))
            let unknown = ids.filter { !rosterIds.contains($0) }
            if !unknown.isEmpty { return .failure(.unknownSeats(unknown)) }
            filterIds = ids
        } else {
            filterIds = nil
        }

        // maxRounds ceilings a NEW round only — seat reruns of the current round are exempt.
        let nextRoundNumber: Int
        if isRerun {
            // Rerun targets the current (last) round; if none yet, open round 1.
            nextRoundNumber = state.rounds.last?.roundNumber ?? 1
        } else {
            nextRoundNumber = state.rounds.count + 1
            if nextRoundNumber > state.maxRounds {
                return .failure(.maxRoundsReached(max: state.maxRounds))
            }
        }

        // Built-in brief for round 1; focus brief required for round 2+.
        let resolvedBrief: String
        let briefSource: PanelRound.BriefSource
        if let brief, !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedBrief = brief
            briefSource = .custom
        } else if nextRoundNumber == 1 {
            resolvedBrief = PanelSeatPrompt.builtinBrief
            briefSource = .builtin
        } else {
            return .failure(.briefRequired)
        }

        // Pin target hash at dispatch; missing target refuses (never invent a hash).
        let resolvedTarget = Self.resolveTargetPath(state.targetPath, projectRoot: state.projectRoot)
        guard let targetHash = PanelState.contentHash(ofFileAt: resolvedTarget) else {
            return .failure(.targetMissing(path: state.targetPath))
        }

        let seatsToRun: [PanelSeat]
        if let filterIds {
            seatsToRun = state.seats.filter { filterIds.contains($0.workerId) }
        } else {
            seatsToRun = state.seats
        }

        let startedAt = now()
        let attemptNumber: Int
        if isRerun, let last = state.rounds.last, !state.rounds.isEmpty {
            attemptNumber = (last.attempts.last?.attemptNumber ?? 0) + 1
        } else {
            attemptNumber = 1
        }

        // Durability-as-mutex: flip to running + write owner.pid BEFORE dispatch.
        state.status = .running
        if isRerun, !state.rounds.isEmpty {
            // Open the current round for the new attempt (clear finishedAt while in flight).
            var open = state.rounds[state.rounds.count - 1]
            open.finishedAt = nil
            open.targetHash = targetHash
            open.brief = resolvedBrief
            open.briefSource = briefSource
            state.rounds[state.rounds.count - 1] = open
        } else {
            let openRound = PanelRound(
                roundNumber: nextRoundNumber,
                targetHash: targetHash,
                brief: resolvedBrief,
                briefSource: briefSource,
                seatResults: seatsToRun.map {
                    SeatResult(workerId: $0.workerId, lens: $0.lens, status: .running, report: "")
                },
                attempts: [],
                startedAt: startedAt,
                finishedAt: nil
            )
            state.rounds.append(openRound)
        }
        persist(state)

        for seat in seatsToRun {
            events?(.seatStarted(seat: seat.workerId, round: nextRoundNumber, attempt: attemptNumber))
        }

        let dispatched = await seatDispatch(
            seatsToRun, resolvedBrief, state.targetPath, state.projectRoot, state.id
        )

        // Map results back onto the roster seats (preserve lens when dispatch omits it).
        let byId = Dictionary(uniqueKeysWithValues: dispatched.map { ($0.workerId, $0) })
        var attemptResults: [SeatResult] = []
        for seat in seatsToRun {
            var result = byId[seat.workerId] ?? SeatResult(
                workerId: seat.workerId, lens: seat.lens, status: .failed,
                reason: "seat produced no result", report: ""
            )
            if result.lens.isEmpty { result.lens = seat.lens }
            attemptResults.append(result)
            events?(.seatSettled(
                seat: result.workerId, round: nextRoundNumber,
                attempt: attemptNumber, status: result.status.rawValue
            ))
        }

        let finishedAt = now()
        let attempt = PanelRoundAttempt(
            attemptNumber: attemptNumber,
            seatFilter: filterIds,
            targetHash: targetHash,
            brief: resolvedBrief,
            briefSource: briefSource,
            seatResults: attemptResults,
            startedAt: startedAt,
            finishedAt: finishedAt
        )

        // Merge into the open round and park back at awaitingPM.
        var round = state.rounds[state.rounds.count - 1]
        round.attempts.append(attempt)
        round.targetHash = targetHash
        round.brief = resolvedBrief
        round.briefSource = briefSource
        round.finishedAt = finishedAt
        if isRerun && !round.seatResults.isEmpty {
            // REPLACE only the rerun seats; keep other seats' prior results.
            var merged = Dictionary(uniqueKeysWithValues: round.seatResults.map { ($0.workerId, $0) })
            for result in attemptResults {
                merged[result.workerId] = result
            }
            // Preserve roster order.
            let order = state.seats.map(\.workerId)
            round.seatResults = order.compactMap { merged[$0] }
        } else {
            round.seatResults = attemptResults
        }
        state.rounds[state.rounds.count - 1] = round
        state.status = .awaitingPM
        persist(state)

        events?(.roundSettled(round: nextRoundNumber, attempt: attemptNumber))
        return .success(RoundResult(state: state, round: round, attempt: attempt))
    }

    // MARK: - done

    /// Declares the panel finished. Only `awaitingPM` → `done` (never invents
    /// convergence). In-flight rounds refuse. Sweeps any leaked seat clones.
    public func done(panelId: String, note: String? = nil) -> Result<PanelState, DoneError> {
        guard var state = stateStore.load(id: panelId) else { return .failure(.panelNotFound) }
        if state.status == .running { return .failure(.roundInFlight) }
        if state.status == .done { return .failure(.alreadyDone) }
        state.status = .done
        state.finishedAt = now()
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.note = note
        }
        persist(state)
        PanelSeatIsolation.sweepPanelClones(panelId: panelId, panelsRoot: panelsRoot ?? stateStore.rootDirectory)
        return .success(state)
    }

    // MARK: - helpers

    /// Single choke point every `PanelState` mutation already runs through — the natural
    /// hook for `threadProjector?.sync` (PN-S05): fires synchronously right after each
    /// save so in-flight running turns and settled reports stay aligned with the ledger.
    private func persist(_ state: PanelState) {
        _ = try? stateStore.save(state)
        threadProjector?.sync(state: state, now: now())
    }

    /// Resolve a possibly-relative target path against the project root.
    public static func resolveTargetPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix("/") { return path }
        return URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(path)
            .path
    }

    /// Production seat dispatch: answer-path only (no plan writer), per-seat prompts,
    /// RO-enforced manifests on the real root, clone-isolated cwd for every other seat
    /// (PN-S06 — "no seat is ever refused"). Falls back to failed seats when no runner
    /// is wired (tests should inject `seatDispatch`).
    private static func defaultDispatch(
        seats: [PanelSeat],
        brief: String,
        targetPath: String,
        projectRoot: String,
        panelId: String,
        workerRunner: (any WorkerInvoking)?,
        models: [Model],
        registry: DriverRegistry,
        panelsRoot: URL?,
        cloneCopier: PanelSeatIsolation.Copier?,
        progress: @escaping @Sendable (TeamRun) -> Void
    ) async -> [SeatResult] {
        guard let workerRunner else {
            return seats.map {
                SeatResult(
                    workerId: $0.workerId, lens: $0.lens, status: .failed,
                    reason: "no worker runner wired for panel dispatch", report: ""
                )
            }
        }

        var enforced = registry
        var earlyFailures: [SeatResult] = []
        var runnableSeats: [PanelSeat] = []
        var workerWorkingDirectories: [String: String] = [:]
        var cloneURLs: [URL] = []
        let copier = cloneCopier ?? .system
        let root = panelsRoot

        defer {
            for url in cloneURLs {
                PanelSeatIsolation.removeClone(at: url)
            }
        }

        for seat in seats {
            let modelId = PanelTeamResolver.modelId(for: seat.workerId)
            guard let model = models.first(where: { $0.id == modelId }) else {
                // Unreachable after panel-start roster preflight under normal flow.
                // Kept only for catalog drift between start and round / test injection.
                earlyFailures.append(SeatResult(
                    workerId: seat.workerId, lens: seat.lens, status: .failed,
                    reason: "Panel seat '\(seat.workerId)' missing from model catalog (catalog drift after start)",
                    report: ""
                ))
                continue
            }
            guard let manifest = registry.manifest(for: model) else {
                earlyFailures.append(SeatResult(
                    workerId: seat.workerId, lens: seat.lens, status: .failed,
                    reason: "Panel seat '\(seat.workerId)' has no registered driver manifest", report: ""
                ))
                continue
            }

            if let ro = PanelReadOnlyArgs.enforce(on: manifest) {
                // Confirmed RO mode — keep real project root.
                enforced = enforced.replacing(ro)
                workerWorkingDirectories[seat.workerId] = projectRoot
            } else {
                // Clone isolation for non-enforcing drivers.
                do {
                    let cloneURL = try PanelSeatIsolation.materializeClone(
                        projectRoot: projectRoot,
                        panelId: panelId,
                        seatId: seat.workerId,
                        panelsRoot: root,
                        copier: copier
                    )
                    cloneURLs.append(cloneURL)
                    workerWorkingDirectories[seat.workerId] = cloneURL.path
                } catch {
                    earlyFailures.append(SeatResult(
                        workerId: seat.workerId, lens: seat.lens, status: .failed,
                        reason: PanelSeatIsolation.cloneFailureMessage(
                            workerId: seat.workerId, detail: "\(error)"
                        ),
                        report: ""
                    ))
                    continue
                }
            }
            runnableSeats.append(seat)
        }

        guard !runnableSeats.isEmpty else { return earlyFailures }

        let workers: [Worker] = runnableSeats.enumerated().map { offset, seat in
            let modelId = PanelTeamResolver.modelId(for: seat.workerId)
            return Worker(
                id: seat.workerId,
                modelId: modelId,
                instanceIndex: offset,
                skillId: nil,
                purpose: .answer
            )
        }
        let resolved = ResolvedTeamRun(
            teamPresetId: "panel_round",
            teamDisplayName: "Panel",
            lane: .code,
            outputKind: .specReview,
            effort: .med,
            scoutWorker: nil,
            answerWorkers: workers,
            planWriter: nil,
            isRunnable: true
        )
        let workerPrompts = PanelSeatPrompt.workerPrompts(
            seats: runnableSeats, brief: brief, targetPath: targetPath
        )
        let coordinator = CatalogRunCoordinator(
            workerRunner: workerRunner, registry: enforced
        )
        let run = await coordinator.run(
            resolved: resolved,
            prompt: brief,
            models: models,
            runId: "panel_\(UUID().uuidString.lowercased())",
            repoRoot: projectRoot,
            workerPrompts: workerPrompts,
            workerWorkingDirectories: workerWorkingDirectories,
            persist: progress
        )

        var results: [SeatResult] = earlyFailures
        for seat in runnableSeats {
            let answer = run.workerAnswers.first { $0.memberId == seat.workerId }
            results.append(seatResult(seat: seat, answer: answer, runId: run.id))
        }
        return results
    }

    /// Persist every worker transition into the open panel round. A slow or hung
    /// final seat must not leave peers that already failed/completed displayed as
    /// empty placeholders.
    private static func persistDispatchProgress(
        run: TeamRun,
        seats: [PanelSeat],
        panelId: String,
        stateStore: PanelStateStore
    ) {
        guard var state = stateStore.load(id: panelId),
              state.status == .running,
              let roundIndex = state.rounds.indices.last else { return }

        var byId = Dictionary(
            uniqueKeysWithValues: state.rounds[roundIndex].seatResults.map { ($0.workerId, $0) }
        )
        for seat in seats {
            guard let answer = run.workerAnswers.first(where: { $0.memberId == seat.workerId }) else {
                continue
            }
            byId[seat.workerId] = seatResult(seat: seat, answer: answer, runId: run.id)
        }
        state.rounds[roundIndex].seatResults = state.seats.compactMap { byId[$0.workerId] }
        _ = try? stateStore.save(state)
    }

    private static func seatResult(
        seat: PanelSeat,
        answer: TeamAnswer?,
        runId: String
    ) -> SeatResult {
        let report = answer?.output ?? ""
        let dispatchStatus: SeatResult.Status
        switch answer?.result.status {
        case .done:
            dispatchStatus = .done
        case .timedOut:
            dispatchStatus = .timedOut
        case .failed, .cancelled, .skipped:
            dispatchStatus = .failed
        case .queued, .running:
            dispatchStatus = .running
        case .none:
            dispatchStatus = .failed
        }
        return PanelFindingsParser.seatResult(
            workerId: seat.workerId,
            lens: seat.lens,
            report: report,
            runId: runId,
            dispatchStatus: dispatchStatus,
            dispatchReason: answer?.result.errorReason
                ?? (answer == nil ? "seat produced no worker result" : nil)
        )
    }
}

// MARK: - DriverRegistry replace helper

private extension DriverRegistry {
    /// Returns a new registry with `manifest` replacing any existing entry for the same id.
    func replacing(_ manifest: DriverManifest) -> DriverRegistry {
        var byId: [String: DriverManifest] = [:]
        for m in all {
            byId[m.id] = m
        }
        byId[manifest.id] = manifest
        return DriverRegistry(Array(byId.values))
    }
}
