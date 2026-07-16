import Foundation
import AllnighterCore

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
    /// `CatalogRunCoordinator` run over the PN-S02 answer path with per-seat prompts
    /// and RO-enforced manifests.
    public typealias SeatDispatch = @Sendable (
        _ seats: [PanelSeat],
        _ brief: String,
        _ targetPath: String,
        _ projectRoot: String
    ) async -> [SeatResult]

    public enum StartError: Swift.Error, Sendable, Equatable {
        case emptyRoster
        case seatNotIsolated(workerId: String, message: String)
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
    private let now: @Sendable () -> Date
    private let idFactory: @Sendable () -> String

    public init(
        stateStore: PanelStateStore = PanelStateStore(),
        seatDispatch: SeatDispatch? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        idFactory: @escaping @Sendable () -> String = { PanelState.makeId() },
        workerRunner: (any WorkerInvoking)? = nil,
        models: [Model] = [],
        registry: DriverRegistry = DriverRegistry()
    ) {
        self.stateStore = stateStore
        self.now = now
        self.idFactory = idFactory
        if let seatDispatch {
            self.seatDispatch = seatDispatch
        } else {
            let runner = workerRunner
            let models = models
            let registry = registry
            self.seatDispatch = { seats, brief, targetPath, projectRoot in
                await PanelCoordinator.defaultDispatch(
                    seats: seats,
                    brief: brief,
                    targetPath: targetPath,
                    projectRoot: projectRoot,
                    workerRunner: runner,
                    models: models,
                    registry: registry
                )
            }
        }
    }

    // MARK: - start

    /// Creates a parked panel at `awaitingPM` with zero rounds. Does not dispatch.
    public func start(
        config: Config,
        models: [Model] = [],
        registry: DriverRegistry = DriverRegistry()
    ) -> Result<PanelState, StartError> {
        guard !config.seats.isEmpty else { return .failure(.emptyRoster) }
        for seat in config.seats {
            if let violation = PanelReadOnlyArgs.capabilityViolation(
                workerId: seat.workerId, models: models, registry: registry
            ) {
                return .failure(.seatNotIsolated(workerId: seat.workerId, message: violation.message))
            }
        }
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
        persist(state)
        return .success(state)
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
                    SeatResult(workerId: $0.workerId, lens: $0.lens, status: .empty, report: "")
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
            seatsToRun, resolvedBrief, state.targetPath, state.projectRoot
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
    /// convergence). In-flight rounds refuse.
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
        return .success(state)
    }

    // MARK: - helpers

    private func persist(_ state: PanelState) {
        _ = try? stateStore.save(state)
    }

    /// Resolve a possibly-relative target path against the project root.
    public static func resolveTargetPath(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix("/") { return path }
        return URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(path)
            .path
    }

    /// Production seat dispatch: answer-path only (no plan writer), per-seat prompts,
    /// RO-enforced manifests via `PanelReadOnlyArgs`. Falls back to failed seats when
    /// no runner is wired (tests should inject `seatDispatch`).
    private static func defaultDispatch(
        seats: [PanelSeat],
        brief: String,
        targetPath: String,
        projectRoot: String,
        workerRunner: (any WorkerInvoking)?,
        models: [Model],
        registry: DriverRegistry
    ) async -> [SeatResult] {
        guard let workerRunner else {
            return seats.map {
                SeatResult(
                    workerId: $0.workerId, lens: $0.lens, status: .failed,
                    reason: "no worker runner wired for panel dispatch", report: ""
                )
            }
        }

        // RO-enforce every manifest; refuse individual seats that still can't isolate
        // (start already checked, but defend in depth for direct callers).
        var enforced = registry
        var earlyFailures: [SeatResult] = []
        var runnableSeats: [PanelSeat] = []
        for seat in seats {
            if let violation = PanelReadOnlyArgs.capabilityViolation(
                workerId: seat.workerId, models: models, registry: registry
            ) {
                earlyFailures.append(SeatResult(
                    workerId: seat.workerId, lens: seat.lens, status: .failed,
                    reason: violation.message, report: ""
                ))
                continue
            }
            if let model = models.first(where: { $0.id == seat.workerId }),
               let manifest = registry.manifest(for: model),
               let ro = PanelReadOnlyArgs.enforce(on: manifest) {
                enforced = enforced.replacing(ro)
            }
            runnableSeats.append(seat)
        }

        guard !runnableSeats.isEmpty else { return earlyFailures }

        let workers: [Worker] = runnableSeats.map { seat in
            Worker(
                id: seat.workerId,
                modelId: seat.workerId,
                instanceIndex: 0,
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
            workerPrompts: workerPrompts
        )

        var results: [SeatResult] = earlyFailures
        for seat in runnableSeats {
            let answer = run.workerAnswers.first { $0.memberId == seat.workerId }
            let report = answer?.output ?? ""
            let dispatchStatus: SeatResult.Status
            switch answer?.result.status {
            case .done: dispatchStatus = .done
            case .timedOut: dispatchStatus = .timedOut
            case .failed, .cancelled, .skipped: dispatchStatus = .failed
            case .queued, .running, .none: dispatchStatus = report.isEmpty ? .empty : .done
            }
            results.append(PanelFindingsParser.seatResult(
                workerId: seat.workerId,
                lens: seat.lens,
                report: report,
                runId: run.id,
                dispatchStatus: dispatchStatus
            ))
        }
        return results
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
