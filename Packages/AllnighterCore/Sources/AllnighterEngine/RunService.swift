import Foundation
import AllnighterCore
import AgentOSTeam

/// One run request — message + optional preset + worker, against a repo root.
public struct RunRequest: Sendable, Equatable {
    public var message: String
    /// Canonical normalized repo root (cwd for every worker). Required.
    public var repoRoot: String
    /// The visible Allnighter thread this turn belongs to (Worker_Session_Continuity).
    /// Lets the run path resume the SAME vendor CLI session per (thread, source, model)
    /// instead of spawning a fresh, amnesiac process each turn. nil = no continuity.
    public var threadId: String?
    public var projectId: String?
    public var presetId: String?
    /// Override the resolved worker (model id) for execution / default chat.
    public var workerId: String?
    public var effort: EffortLevel?
    /// Lane hint when resolving an answer team without an explicit preset.
    public var lane: WorkLane?
    public var type: String?
    public var context: String?
    /// User-attached images/files, already staged into the workspace and frozen.
    /// Delivered per-worker (vision seats get the path block; non-vision seats get
    /// an explicit "can't see it" notice) by `CatalogRunCoordinator`.
    public var deliveries: [IncludedAttachmentDelivery]
    /// Try Fix (Try_Fix_Auto_Implement): the mutating executor team for the child fix attempt
    /// (default `build_slice`). Read by `FollowUpCoordinator`, which owns the chain — a
    /// plain `RunService.run` ignores it. Whether to run the chain at all is the caller's
    /// decision (the CLI `--try-fix` flag), not a field here.
    public var executorTeamId: String?
    /// Optional caller-seeded timing ladder. GUI callers add composer/context/thread
    /// stamps before the engine owns worker resolution and process timing.
    public var timing: RunTimingReport?
    /// Code-review advisory slice: findings-only writes; skips repo `RunWriteLock`.
    public var advisoryReview: Bool
    /// Override manifest `invoke.timeoutSeconds` (e.g. packet `stallTimeoutSeconds` for GLM review).
    /// Also the RLR-L8 `--idle-timeout` override (nil = per-manifest default).
    public var workerTimeoutSeconds: Int?
    /// RLR-L8 — runner-ready handshake bound (`--handshake-timeout`). Nil = `RunClockDefaults`.
    public var handshakeTimeoutSeconds: Int?
    /// RLR-L8 — first post-spawn activity bound (`--first-activity-timeout`). Nil = defaults.
    public var firstActivityTimeoutSeconds: Int?
    /// RLR-L8 — total wall ceiling (`--wall-timeout`). Nil = `RunClockDefaults`.
    public var wallTimeoutSeconds: Int?
    /// Override `DriverManifest.maxConcurrentSpawns` for this run (parallel CR fan-out).
    public var spawnConcurrencyLimit: Int?
    /// FR12 — exact commit message the worker should use (verification only; Allnighter does no git).
    public var commitMessage: String?
    /// FR12 — instruct the worker to leave changes uncommitted (mutually exclusive with `commitMessage`).
    public var noCommit: Bool
    /// FR13 — proof command to run after worker settlement (bounded subprocess at repo root).
    public var proofCommand: String?
    /// FR13 — override proof timeout (seconds); default 600.
    public var proofTimeoutSeconds: Int?
    /// RLR-L9 — transport idempotency key. When present, the run is claimed in
    /// `IdempotencyStore` at acceptance (same-key + same canonical payload replays
    /// the original run; a different payload is refused). nil = no idempotency.
    public var idempotencyKey: String?
    /// RLR-L9 — intentional retry: durably links this run to the prior run id via
    /// `RunLink.retryOf`. Requires prior tree verified stopped, or `acceptSurvivors`.
    public var retryOf: String?
    /// RLR-L9 — allow `--retry-of` even when the prior run still has identity-alive
    /// recorded workers (typed partial after a clock/kill).
    public var acceptSurvivors: Bool

    public init(
        message: String,
        repoRoot: String,
        threadId: String? = nil,
        projectId: String? = nil,
        presetId: String? = nil,
        workerId: String? = nil,
        effort: EffortLevel? = nil,
        lane: WorkLane? = nil,
        type: String? = nil,
        context: String? = nil,
        deliveries: [IncludedAttachmentDelivery] = [],
        executorTeamId: String? = nil,
        timing: RunTimingReport? = nil,
        advisoryReview: Bool = false,
        workerTimeoutSeconds: Int? = nil,
        handshakeTimeoutSeconds: Int? = nil,
        firstActivityTimeoutSeconds: Int? = nil,
        wallTimeoutSeconds: Int? = nil,
        spawnConcurrencyLimit: Int? = nil,
        commitMessage: String? = nil,
        noCommit: Bool = false,
        proofCommand: String? = nil,
        proofTimeoutSeconds: Int? = nil,
        idempotencyKey: String? = nil,
        retryOf: String? = nil,
        acceptSurvivors: Bool = false
    ) {
        self.message = message
        self.repoRoot = repoRoot
        self.threadId = threadId
        self.projectId = projectId
        self.presetId = presetId
        self.workerId = workerId
        self.effort = effort
        self.lane = lane
        self.type = type
        self.context = context
        self.deliveries = deliveries
        self.executorTeamId = executorTeamId
        self.timing = timing
        self.advisoryReview = advisoryReview
        self.workerTimeoutSeconds = workerTimeoutSeconds
        self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
        self.firstActivityTimeoutSeconds = firstActivityTimeoutSeconds
        self.wallTimeoutSeconds = wallTimeoutSeconds
        self.spawnConcurrencyLimit = spawnConcurrencyLimit
        self.commitMessage = commitMessage
        self.noCommit = noCommit
        self.proofCommand = proofCommand
        self.proofTimeoutSeconds = proofTimeoutSeconds
        self.idempotencyKey = idempotencyKey
        self.retryOf = retryOf
        self.acceptSurvivors = acceptSurvivors
    }
}

public enum RunServiceError: Error, Equatable, CustomStringConvertible {
    case repoRootUnavailable(String)
    case writeLockBusy(String)
    /// Per-root execution lane held after the harness wait bound (PO-S03).
    case executionLaneBusy(String)
    case teamResolution(String, code: String)
    case noWorker(String)
    /// Explicit `--worker` / `--dev-worker` could not be honored (PO-F10).
    case workerNotAvailable(String)
    /// The acceptance journal write failed — the run id never became durable,
    /// so acceptance is refused (RLR-L2: no id without a pollable journal).
    case journalUnavailable(String)

    public var description: String {
        switch self {
        case .repoRootUnavailable(let r): return "repo root unavailable: \(r)"
        case .writeLockBusy(let r): return "an agent is still editing this repo after a long wait — it looks stuck; stop it and retry (\(r))"
        case .executionLaneBusy(let r):
            return "execution lane busy on \(r) — do not busy-loop; poll status for laneBlocked (FIFO ticket) until the harness grants the lane"
        case .teamResolution(let m, _): return m
        case .noWorker(let m): return m
        case .workerNotAvailable(let m): return m
        case .journalUnavailable(let m):
            return "run journal could not be written — the run's durable record is unavailable, so it cannot be reported honestly; check disk space and permissions on the Allnighter support directory, then retry (\(m))"
        }
    }

    public var code: String {
        switch self {
        case .repoRootUnavailable: return "NO_PROJECT_ROOT"
        case .writeLockBusy: return "RUN_WRITE_LOCK_BUSY"
        case .executionLaneBusy: return "EXECUTION_LANE_BUSY"
        case .teamResolution(_, let code): return code
        case .noWorker: return "WORKER_NOT_READY"
        case .workerNotAvailable: return "WORKER_NOT_AVAILABLE"
        case .journalUnavailable: return "RUN_JOURNAL_UNAVAILABLE"
        }
    }
}

/// Unified run entry — one primitive for chat, execution, and answer teams.
/// Every project-scoped run spawns with `cwd = repoRoot`. Mutating runs take
/// `RunWriteLock`; answer runs never take it.
public actor RunService {
    private let models: [Model]
    private let registry: DriverRegistry
    private let teams: [TeamPreset]
    private let runStore: RunStore
    private let commandRunner: CommandRunner
    private let writeLock: RunWriteLockRegistry
    private let invocations: [String: ToolInvocation]
    private let now: @Sendable () -> Date
    // Auto (Default model) inputs — injectable so resolution is deterministic in tests.
    private let loadDefaultSettings: @Sendable () -> DefaultModelSettings
    private let loadProbeRecords: @Sendable () -> [ToolProbeRecord]
    /// Worker_Session_Continuity: the durable per-(thread, source, model) vendor session map.
    private let sessionStore: ExternalWorkerSessionStore
    /// Warm_Single_Lane_Chat: process-global warm-worker registry (default = shared singleton so
    /// warmth survives the per-turn RunService instances; tests inject a fresh pool).
    private let warmPool: WarmWorkerPool
    private let gitObserver: GitObserver
    /// RLR-L9 durable idempotency (same store as async `team start`). Injectable
    /// so tests isolate the claim file from the real config home.
    private let idempotency: IdempotencyStore

    /// How long a mutating run waits in the per-repo FIFO before refusing. Generous on purpose:
    /// normal queuing clears in seconds-to-minutes (and a stuck holder is killed by its own
    /// worker timeout/watchdog, freeing the lock far sooner). This only trips for a holder wedged
    /// beyond all of that — the bound that stops one stuck run from hanging every later run.
    static let writeLockWaitTimeout: Duration = .seconds(1800)

    public init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset] = TeamCatalog.all,
        runStore: RunStore = RunStore(),
        // PO-S02: process-group leaders via posix_spawn SETPGROUP so turn kill reaps
        // the whole worker tree. Tests inject Mock/SequencedCommandRunner doubles.
        commandRunner: CommandRunner = ProcessGroupCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
        writeLock: RunWriteLockRegistry = .shared,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init,
        defaultSettings: @escaping @Sendable () -> DefaultModelSettings = { DefaultModelSettingsPersistence().load() },
        probeRecords: @escaping @Sendable () -> [ToolProbeRecord] = { SetupStore().load().records },
        sessionStore: ExternalWorkerSessionStore = ExternalWorkerSessionStore(),
        warmPool: WarmWorkerPool = .shared,
        gitObserver: GitObserver = GitObserver(),
        idempotency: IdempotencyStore = IdempotencyStore()
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.runStore = runStore
        self.commandRunner = commandRunner
        self.writeLock = writeLock
        self.invocations = invocations
        self.now = now
        self.loadDefaultSettings = defaultSettings
        self.loadProbeRecords = probeRecords
        self.sessionStore = sessionStore
        self.warmPool = warmPool
        self.gitObserver = gitObserver
        self.idempotency = idempotency
    }

    /// Bench display name for a model id — used by relay prompt assembly (FR4).
    public func workerDisplayName(forModelId id: String) -> String {
        models.first { $0.id == id }?.displayName ?? id
    }

    private func readyModels() -> [Model] { models.filter(\.enabled) }

    /// PO-F10 / MR-S04: honor an explicit worker id or fail with `WORKER_NOT_AVAILABLE`.
    /// Never returns a substitute model. Display names fail closed via ExactIdResolver.
    public func resolveExplicitWorker(_ id: String) -> Result<Model, RunServiceError> {
        switch ExactIdResolver.resolveWorker(id, flag: "--worker", models: models, readyModelIds: Set(sourceReadyModelIds())) {
        case .failure(let failure):
            return .failure(.workerNotAvailable(failure.message))
        case .success(let m):
            guard m.enabled else {
                return .failure(.workerNotAvailable(
                    "\(id) is disabled — run `alln models enable \(id)`, or pick a ready worker; see `alln menu --json` / `alln doctor`."
                ))
            }
            guard sourceReadyModelIds().contains(m.id) else {
                return .failure(.workerNotAvailable(
                    "\(id) is notReady — check `alln doctor` (or run `alln doctor --full`); see `alln menu --json`."
                ))
            }
            return .success(m)
        }
    }

    // MARK: - Try Fix support (FollowUpCoordinator)

    /// Resolve the chosen executor team to the facts the Try Fix gate needs: does it exist,
    /// is it mutating, can it run on this bench, and does it resolve to exactly one worker.
    public func tryFixExecutorFacts(teamId: String) -> TryFixGate.ExecutorFacts {
        guard let team = teams.first(where: { $0.id == teamId }) ?? TeamCatalog.get(teamId) else {
            return .init(teamId: teamId, exists: false, isMutating: false, isRunnable: false, workerCount: 0)
        }
        let resolved = TeamResolver.resolve(
            team: team, requestLane: team.lane, requestEffort: team.defaultEffort, readyModels: readyModels())
        // A mutating team runs exactly one worker (the execution path); count its resolved
        // answer worker(s) — the catalog enforces one row for mutating teams.
        let workerCount = team.mutating ? resolved.answerWorkers.count : resolved.allWorkers.count
        return .init(teamId: teamId, exists: true, isMutating: team.mutating,
                     isRunnable: resolved.isRunnable, workerCount: workerCount)
    }

    /// Re-persist a run (used to record Try Fix parent/child links after both runs settle).
    /// Returns false if the write failed so the caller can note that the diagnosis<->fix link
    /// didn't durably persist (the runs themselves already saved during `run()`; this only
    /// re-writes the `links`).
    @discardableResult
    public func save(_ run: TeamRun) -> Bool {
        do {
            try runStore.save(run, models: models, forceArtifacts: run.status.isTerminal)
            return true
        } catch {
            return false
        }
    }

    /// RLR-S02a — enrich the durable blocker with the FIFO ticket facts while the mutating
    /// run is parked in the write-lock queue. Runs off the `ExecutionLaneRegistry` actor as the
    /// `onTicket` callback (hence `nonisolated static`, capturing only Sendable state). Loads
    /// the just-saved queued run, sets `holderId`/`holderKind`/`ticketPosition`/`holderAcquiredAt`
    /// and re-saves in one revision. It never changes `phase` or clears `resource`/`scopeRoot`, so
    /// the RLR-L3 atomic phase/blocker rule is not intersected — the blocker is only enriched.
    /// A vanished run or an already-cleared blocker is a no-op (the wait moved on).
    nonisolated static func recordBlockerTicket(
        runId: String,
        ticket: ExecutionLaneTicket,
        store: RunStore,
        models: [Model],
        now: @Sendable () -> Date
    ) {
        guard var run = store.loadRaw(runId: runId), var blocker = run.blocker else { return }
        blocker.holderId = ticket.holder.id
        // RLR-L4: P0 public holderKind is always `run`, never the internal site kind.
        blocker.holderKind = "run"
        blocker.ticketPosition = ticket.position
        blocker.holderAcquiredAt = now().addingTimeInterval(-ticket.heldSinceSeconds)
        run.blocker = blocker
        try? store.save(run, models: models)
    }

    /// Model ids that are a runnable substitute *right now*: ON the Bench AND their
    /// source CLI is installed + probe-ready. Mirrors the readiness the `defaults` /
    /// `models` projections show, so Auto's "→ Opus 4.8" preview equals what actually
    /// runs and a down CLI is genuinely routed around (source-health, not just enabled).
    private func sourceReadyModelIds() -> Set<ModelID> {
        let records = loadProbeRecords()
        let cooling = coolingSources()
        return Set(BenchReadiness.readyModels(
            models: models,
            probeRecords: records,
            coolingDriverIds: cooling,
            knownDriverIds: Set(registry.all.map(\.id))
        ).map(\.id))
    }

    /// Sources cooling down right now (a rate-limit / cooldown that hasn't reset),
    /// derived from prior runs' failed worker answers. Routed around pre-dispatch.
    func coolingSources(now: Date = Date()) -> Set<String> {
        SourceCapacityLedger.coolingSources(observations: recentCapacityObservations(now: now), now: now)
    }

    private func recentCapacityObservations(now: Date) -> [CapacityObservation] {
        return runStore.list()
            .flatMap { run in
                var observations =
                    run.failedWorkerAnswers.compactMap(\.result.capacityObservation)
                    + run.attempts.compactMap(\.capacityObservation)
                if let blocker = run.blocker,
                   blocker.resource == .vendorBackoff,
                   var parked = blocker.capacityObservation {
                    // Project the resident's conservative park boundary into
                    // the existing ledger fact. Unknown-reset parks use their
                    // bounded local cadence without claiming vendor reset truth.
                    parked.wakeAfter = blocker.wakeAfter ?? run.attempts.last.map {
                        VendorBackoffPolicy.unknownResetWakeAfter(
                            attemptNumber: $0.attemptNumber,
                            observedAt: $0.endedAt
                                ?? $0.capacityObservation?.observedAt
                                ?? run.createdAt
                        )
                    }
                    observations.append(parked)
                }
                return observations
            }
            // Do not prefilter by run age: weekly/monthly windows must survive
            // the retired 12-hour scan boundary. The ledger expires by wake time.
            .filter {
                guard let until = $0.wakeAfter ?? $0.observedResetAt else { return false }
                return until > now
            }
    }

    /// RLR-L9 sync-path idempotency claim at acceptance. Returns:
    /// - `.success(nil)` — key claimed, mint/spawn `runId`.
    /// - `.success(run)` — same key + same payload already owns a run → replay it
    ///   (return the ORIGINAL run, never a second worker).
    /// - `.failure` — conflict (`IDEMPOTENCY_CONFLICT`), expired (`IDEMPOTENCY_EXPIRED`),
    ///   or store error.
    ///
    /// Mirrors `AsyncTeamService.claimIdempotency` minus the detached-handshake
    /// wait: the sync run has already persisted its journal by the time a peer
    /// could observe the claim, so a live replay entry always has a loadable run;
    /// a vanished peer is taken over with `forceClaim`.
    private func claimSyncIdempotency(
        key: String, payload: AsyncTeamCanonicalPayload, runId: String
    ) -> Result<TeamRun?, RunServiceError> {
        let store = idempotency
        func conflict() -> RunServiceError {
            .teamResolution(
                "idempotency key was already used with a different payload",
                code: "IDEMPOTENCY_CONFLICT")
        }
        func expired() -> RunServiceError {
            .teamResolution(
                "idempotency key has expired (replay window \(Int(IdempotencyStore.retention))s); use a new key",
                code: "IDEMPOTENCY_EXPIRED")
        }
        do {
            switch try store.claim(key: key, payload: payload, runId: runId) {
            case .claimed:
                return .success(nil)
            case .conflict:
                return .failure(conflict())
            case .expired:
                return .failure(expired())
            case .replay(let entry):
                if let run = runStore.load(runId: entry.runId) ?? runStore.loadRaw(runId: entry.runId) {
                    return .success(run)
                }
                // Peer claimed then vanished before persisting — take over.
                switch try store.forceClaim(
                    key: key, payload: payload, runId: runId,
                    runExists: { [runStore] in runStore.loadRaw(runId: $0) != nil }
                ) {
                case .claimed:
                    return .success(nil)
                case .conflict:
                    return .failure(conflict())
                case .expired:
                    return .failure(expired())
                case .replay(let again):
                    if let run = runStore.load(runId: again.runId) ?? runStore.loadRaw(runId: again.runId) {
                        return .success(run)
                    }
                    return .failure(.teamResolution(
                        "idempotency replay run \(again.runId) never appeared", code: "INTERNAL_ERROR"))
                }
            }
        } catch {
            return .failure(.teamResolution("idempotency claim failed: \(error)", code: "INTERNAL_ERROR"))
        }
    }

    /// RLR-L9: `--retry-of` requires the prior tree verified stopped (no
    /// identity-alive recorded workers), or `--accept-survivors`.
    private func assertRetryOfAllowed(_ request: RunRequest) -> RunServiceError? {
        guard let priorId = request.retryOf, !priorId.isEmpty else { return nil }
        guard runStore.loadRaw(runId: priorId) != nil || runStore.load(runId: priorId) != nil else {
            return .teamResolution("retry-of run not found: \(priorId)", code: "RUN_NOT_FOUND")
        }
        if request.acceptSurvivors { return nil }
        guard let dir = try? runStore.runDirectory(forRunId: priorId) else { return nil }
        let workers = ProcessOwnership.readWorkerOwners(inRunDirectory: dir)
        let live = workers.compactMap { workerId, identity in
            ProcessOwnership.isIdentityAlive(identity) ? workerId : nil
        }
        if live.isEmpty { return nil }
        return .teamResolution(
            "prior run \(priorId) still has identity-alive workers (\(live.joined(separator: ", "))); pass --accept-survivors to retry anyway",
            code: "RETRY_OF_SURVIVORS"
        )
    }

    /// Resume one journal already leased by the resident coordinator. This is an
    /// in-process continuation of the same run id — never a child `alln run`.
    public func resumeParkedRun(
        runId: String,
        coordinatorId: String,
        selectionOrigin: String = MorningReceipt.automaticResumeOrigin,
        substituteModelId: String? = nil
    ) async -> Result<TeamRun, RunServiceError> {
        guard var parked = runStore.loadRaw(runId: runId),
              parked.status == .queued,
              parked.phase == .waitingForVendor,
              parked.blocker?.resource == .vendorBackoff,
              parked.blocker?.holderId == coordinatorId,
              parked.blocker?.holderKind == "coordinator",
              parked.mutating,
              parked.workers.count == 1,
              let rootValue = parked.repoRoot,
              let parkedModelId = parked.workers.first?.modelId else {
            return .failure(.teamResolution(
                "vendor wake lease is missing or run is not a single-worker park",
                code: "VENDOR_WAKE_NOT_CLAIMED"
            ))
        }
        let root = RunWriteLock.normalize(rootValue) ?? rootValue
        guard let presetId = parked.presetId,
              let preset = teams.first(where: { $0.id == presetId }) ?? TeamCatalog.get(presetId),
              preset.runShape == .execution else {
            return .failure(.teamResolution(
                "parked run's execution team is unavailable",
                code: "DEFAULT_TEAM_INVALID"
            ))
        }

        let wakeModelResolution = resolveParkedWakeModel(
            parked: parked,
            preset: preset,
            parkedModelId: parkedModelId,
            substituteModelId: substituteModelId,
            selectionOrigin: selectionOrigin
        )
        guard case .success(let wakeModel) = wakeModelResolution else {
            if case .failure(let error) = wakeModelResolution { return .failure(error) }
            return .failure(.teamResolution("vendor wake model resolution failed", code: "INTERNAL_ERROR"))
        }
        let modelId = wakeModel.modelId
        let resumeOrigin = wakeModel.selectionOrigin
        let substitutionOfAttempt = wakeModel.substitutionOfAttempt

        let lockKey = RunWriteLock.key(repoRoot: root)
        parked.status = .queued
        parked.phase = .waitingForWriteLock
        parked.blocker = RunBlocker(resource: .repoWriteLock, scopeRoot: root)
        do {
            try runStore.save(parked, models: models)
        } catch {
            return .failure(.journalUnavailable("\(error)"))
        }

        let claim = ExecutionLane.Claim.current(
            id: runId, kind: ExecutionLaneSite.mutatingRun.rawValue
        ) ?? ExecutionLane.Claim(
            id: runId,
            kind: ExecutionLaneSite.mutatingRun.rawValue,
            identity: ProcessOwnership.OwnerIdentity(
                pid: ProcessInfo.processInfo.processIdentifier,
                pgid: nil, startTimeTicks: 0, kind: .inProcess
            )
        )
        let store = runStore
        let allModels = models
        let clock = now
        guard let token = await writeLock.waitToAcquire(
            lockKey,
            claim: claim,
            timeout: Self.writeLockWaitTimeout,
            onTicket: { ticket in
                Self.recordBlockerTicket(
                    runId: runId, ticket: ticket, store: store,
                    models: allModels, now: clock
                )
            },
            shouldAbandon: { _ in
                store.loadRaw(runId: runId)?.status.isTerminal ?? false
            }
        ) else {
            if let terminal = runStore.loadRaw(runId: runId), terminal.status.isTerminal {
                return .success(terminal)
            }
            parked.status = .failed
            parked.phase = nil
            parked.blocker = nil
            parked.endReason = .failed
            parked.warnings.append("vendor wake could not reacquire the repository write lock")
            try? runStore.save(parked, models: models)
            return .failure(.writeLockBusy(root))
        }

        if let terminal = runStore.loadRaw(runId: runId), terminal.status.isTerminal {
            await writeLock.release(lockKey, token: token)
            return .success(terminal)
        }
        parked.phase = .spawningWorker
        parked.blocker = nil
        try? runStore.save(parked, models: models)

        let runner = WorkerInvokerFactory.makeWorkerInvoker(
            commandRunner: (commandRunner as? StreamingCommandRunner)
                ?? CommandRunnerAsStreaming(commandRunner),
            invocations: invocations,
            defaultWorkingDirectory: root
        )
        if let runDir = try? runStore.runDirectory(forRunId: runId) {
            ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: runDir)
            if let coordinator = ProcessOwnership.OwnerIdentity.current(kind: .inProcess) {
                try? ProcessOwnership.writeOwnerIdentity(coordinator, in: runDir)
            }
        }
        let result = await runExecution(
            preset: preset,
            prompt: parked.prompt,
            context: nil,
            threadId: parked.threadId,
            effort: parked.effort ?? preset.defaultEffort,
            repoRoot: root,
            requestLane: parked.lane,
            explicitTeamChosen: true,
            laneContextOnly: parked.laneContextOnly == true,
            explicitWorkerIds: parked.explicitWorkerIds,
            projectId: nil,
            workerOverride: modelId,
            origin: parked.origin,
            originAgent: parked.originAgent,
            runId: runId,
            runner: runner,
            requestedAt: now(),
            timing: parked.timing ?? RunTimingReport(),
            events: nil,
            workerTimeoutSeconds: VendorBackoffPolicy.probeTimeoutSeconds,
            commitMessage: parked.requestedCommitMessage,
            noCommit: parked.noCommitOrdered == true,
            retryLinks: parked.links,
            clockBudgets: parked.clockBudgets,
            existingRun: parked,
            resumeSelectionOrigin: resumeOrigin,
            substitutionOfAttempt: substitutionOfAttempt
        )
        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: nil)
        await writeLock.release(lockKey, token: token)
        if case .failure(let error) = result,
           var failed = runStore.loadRaw(runId: runId),
           !failed.status.isTerminal {
            failed.status = .failed
            failed.phase = nil
            failed.blocker = nil
            failed.endReason = .failed
            failed.warnings.append("vendor resume failed: \(error.code)")
            _ = try? runStore.save(failed, models: models)
        }
        return result
    }

    /// Manual "Use another model" — same run id, user-authorized substitute.
    public func substituteParkedRun(
        runId: String,
        modelId: String,
        coordinatorId: String
    ) async -> Result<TeamRun, RunServiceError> {
        return await resumeParkedRun(
            runId: runId,
            coordinatorId: coordinatorId,
            selectionOrigin: RunSelectionOrigin.manualSubstitute,
            substituteModelId: modelId
        )
    }

    /// Run and persist. Returns the settled `TeamRun` (RunRecord substrate).
    public func run(
        _ request: RunRequest,
        origin: RunOrigin,
        originAgent: String? = nil,
        runId: String? = nil,
        events: AsyncStream<RunEvent>.Continuation? = nil
    ) async -> Result<TeamRun, RunServiceError> {
        defer { events?.finish() }

        // PO-F10: opportunistic stale-lane GC so a fresh run is never confused by
        // prior-run cruft (dead-holder dirs with an unheld flock).
        _ = ExecutionLaneFlock.garbageCollectStaleLanes()
        _ = ProcessOwnershipGarbageCollector(runStore: runStore).collect()

        // Queue-wait clock: stamp BEFORE the write-lock acquire (the real blocking wait) and
        // resolution/staging, so `queueMs = worker.startedAt − requestedAt` captures all of it.
        let requestedAt = now()
        var timing = request.timing ?? RunTimingReport()
        timing.stamp(RunTimingKey.runRequested, at: requestedAt)
        timing.set(RunTimingKey.contextBytes, int: request.context?.utf8.count ?? 0)
        let root = RunWriteLock.normalize(request.repoRoot) ?? request.repoRoot
        guard RootNormalization.observeRootState(key: root) == .available else {
            return .failure(.repoRootUnavailable(root))
        }

        // SH-S01: one resolver owns team/worker/Auto selection (same as dry-run).
        let invocation = RunInvocationResolver.resolve(
            RunInvocationInput(request: request, flagMode: .foreground),
            context: RunInvocationResolveContext(
                models: models,
                teams: teams.isEmpty ? TeamCatalog.all : teams,
                readyModels: readyModels(),
                readyModelIds: sourceReadyModelIds(),
                defaultSettings: loadDefaultSettings()
            )
        )
        if !invocation.canStart {
            let reason = invocation.blockedReason ?? "run cannot start"
            if invocation.explicitWorkerChosen {
                return .failure(.workerNotAvailable(reason))
            }
            return .failure(.teamResolution(reason, code: "DEFAULT_TEAM_INVALID"))
        }

        let preset = invocation.preset
        let effectiveWorkerId = invocation.workerId
        let explicitTeamChosen = invocation.explicitTeamChosen
        let laneContextOnly = request.lane != nil && !(request.workerId ?? "").isEmpty
        // ADP-S01: the explicit `--worker` selection, canonicalized to the resolved
        // id so a `reproduceCommand` replay resolves to the same seat. Nil when the
        // worker was default-team/Auto resolved (no explicit `--worker`).
        let explicitWorkerIds: [String]? = invocation.explicitWorkerChosen
            ? (effectiveWorkerId.map { [$0] } ?? request.workerId.map { [$0] })
            : nil
        let effectiveLane = invocation.lane
        let effort = invocation.effort
        let lockKey = invocation.lockKey
        var lockToken: RunWriteLock.Token?
        let takesWriteLock = invocation.takesWriteLock

        var prompt = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let starter = preset.starterPrompts.first, !starter.isEmpty, preset.mutating {
            prompt = starter + "\n\n" + prompt
        }
        // NOTE: thread context is appended below per-path. The execution path appends it
        // CONDITIONALLY (Worker_Session_Continuity: when resuming a live vendor session the
        // CLI already holds the history, so we don't re-dump it); the answer path always does.

        // RLR-L1: the canonical id is minted BEFORE any long wait so the emitted
        // id and the durable journal always exist together.
        let id = runId ?? UUID().uuidString

        // RLR-L9: `--retry-of` gate before mint/claim — refuse when prior workers
        // are still identity-alive unless `--accept-survivors`.
        if let error = assertRetryOfAllowed(request) {
            return .failure(error)
        }

        let clockBudgets = RunClockBudgets.resolved(
            handshake: request.handshakeTimeoutSeconds,
            firstActivity: request.firstActivityTimeoutSeconds,
            idle: request.workerTimeoutSeconds,
            wall: request.wallTimeoutSeconds
        )

        // RLR-L9: persist the idempotency key + full canonical payload hash at
        // acceptance (same store as async `team start`). A same-key + same-payload
        // replay returns the ORIGINAL run — never a second worker; a different
        // payload is `IDEMPOTENCY_CONFLICT`; past retention is `IDEMPOTENCY_EXPIRED`.
        if let key = request.idempotencyKey, !key.isEmpty {
            let canonical = AsyncTeamCanonicalPayload(
                prompt: prompt,
                lane: effectiveLane.rawValue,
                teamPresetId: preset.id,
                effort: effort.rawValue,
                modelId: effectiveWorkerId,
                type: request.type,
                context: request.context,
                repoRoot: root,
                attachmentDigests: request.deliveries.map(\.storedSha256),
                threadId: request.threadId,
                resolvedTeamId: preset.id,
                resolvedWorkerIds: effectiveWorkerId.map { [$0] } ?? [],
                handshakeTimeout: Int(clockBudgets.handshakeTimeoutSeconds),
                firstActivityTimeout: Int(clockBudgets.firstActivityTimeoutSeconds),
                idleTimeout: request.workerTimeoutSeconds,
                wallTimeout: Int(clockBudgets.wallTimeoutSeconds),
                proofCommand: request.proofCommand,
                commitMessage: request.commitMessage,
                noCommit: request.noCommit,
                contractVersion: ContractRegistry.contractVersion
            )
            switch claimSyncIdempotency(key: key, payload: canonical, runId: id) {
            case .success(let existing?):
                return .success(existing)          // transport replay — the original run
            case .success(.none):
                break                              // claimed — proceed with `id`
            case .failure(let error):
                return .failure(error)
            }
        }

        let retryLinks: [RunLink]? = request.retryOf.map { [RunLink(kind: .retryOf, runId: $0)] }

        if takesWriteLock {
            // RLR-L2: mint + persist a durable, pollable run BEFORE the long lock
            // wait so a second process can already identify it and see WHAT it is
            // waiting on (queued / waitingForWriteLock + a repoWriteLock blocker
            // stub). The full FIFO/ticket facts land in S02.
            var pending = TeamRun(
                id: id, prompt: prompt, status: .queued, phase: .waitingForWriteLock,
                origin: origin, originAgent: originAgent, presetId: preset.id,
                createdAt: now(), lane: effectiveLane, effort: effort,
                teamDisplayName: RunIdentity.teamDisplayName(
                    presetId: preset.id, catalogDisplayName: preset.displayName,
                    explicitTeamChosen: explicitTeamChosen),
                outputKind: preset.outputKind, mutating: true, repoRoot: root,
                laneContextOnly: laneContextOnly ? true : nil,
                explicitWorkerIds: explicitWorkerIds,
                blocker: RunBlocker(resource: .repoWriteLock, scopeRoot: root),
                clockBudgets: clockBudgets,
                links: retryLinks)
            do {
                // Hard gate, not best-effort: acceptance IS this save (RLR-L2).
                // If it fails the id must never be emitted as accepted.
                try runStore.save(pending, models: models)
            } catch {
                return .failure(.journalUnavailable("\(error)"))
            }

            // One writer per repo root. If another mutating run holds the lock, WAIT our turn
            // (FIFO) and then run — a second back-to-back agent turn queues behind the first
            // instead of erroring. The bounded timeout is the safety valve: if a wedged holder
            // outlives even its own worker timeout/watchdog, we stop queueing forever and refuse
            // honestly (RUN_WRITE_LOCK_BUSY, retryable). Read-only runs never reach here.
            //
            // RLR-S02a: claim the lane by our own `runId` (so `holder.json.id` and a second
            // run's ticket name THIS run's canonical id, not a throwaway UUID) and consume the
            // FIFO ticket via `onTicket` to durably record who holds the lock + our queue
            // position while blocked. The ticket write only enriches the blocker (phase stays
            // `waitingForWriteLock`), so RLR-L3's atomic phase/blocker rule is untouched.
            let claim = ExecutionLane.Claim.current(
                id: id, kind: ExecutionLaneSite.mutatingRun.rawValue
            ) ?? ExecutionLane.Claim(
                id: id,
                kind: ExecutionLaneSite.mutatingRun.rawValue,
                identity: ProcessOwnership.OwnerIdentity(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    pgid: nil, startTimeTicks: 0, kind: .inProcess))
            let ticketStore = runStore
            let ticketModels = models
            let ticketClock = now
            let abandonStore = runStore
            guard let token = await writeLock.waitToAcquire(
                lockKey, claim: claim, timeout: Self.writeLockWaitTimeout,
                onTicket: { ticket in
                    Self.recordBlockerTicket(
                        runId: id, ticket: ticket,
                        store: ticketStore, models: ticketModels, now: ticketClock)
                },
                // RLR-S02c: a SECOND process can cancel/kill this blocked run (stamping the
                // journal terminal + withdrawing our on-disk waiter) but cannot reach our
                // parked continuation. Self-abandon the wait once our own journal has gone
                // terminal so we stop queueing instead of parking to the full timeout.
                shouldAbandon: { _ in
                    abandonStore.loadRaw(runId: id)?.status.isTerminal ?? false
                }
            ) else {
                // `waitToAcquire` returned nil: either a genuine timeout (laneBusy) or we
                // self-abandoned because a second process made the run terminal (RLR-S02c).
                // If the run is ALREADY terminal on disk, that cancel/kill is the truth —
                // never overwrite it with `failed`; return the durable terminal run.
                if let terminal = runStore.loadRaw(runId: id), terminal.status.isTerminal {
                    return .success(terminal)
                }
                // Still durable + non-terminal — stamp it terminal HONESTLY rather than
                // letting it vanish (RLR-L2). Write-lock wait exhaustion never acquired
                // the lane; the honest terminal is `failed`.
                pending.status = .failed
                pending.phase = nil
                pending.blocker = nil
                pending.endReason = .failed
                try? runStore.save(pending, models: models)
                return .failure(.writeLockBusy(root))
            }
            lockToken = token
            // RLR-S02c pre-spawn terminal guard: the grant may have handed us the lane for
            // an already-terminal run — a cross-process kill stamped the journal terminal and
            // withdrew our waiter file, but the in-process grant still fired before our
            // self-abandon poll. Do NOT resurrect a corpse or spawn a worker. Release the lane
            // explicitly here (this early return is INSIDE the takesWriteLock block, before the
            // release `defer` below is registered) and return the durable terminal run.
            if let terminal = runStore.loadRaw(runId: id), terminal.status.isTerminal {
                await writeLock.release(lockKey, token: token)
                lockToken = nil
                return .success(terminal)
            }
            // Lock acquired → advance to spawningWorker and clear the blocker in the
            // same revision (RLR-L3 atomic rule).
            pending.phase = .spawningWorker
            pending.blocker = nil
            try? runStore.save(pending, models: models)
        }
        let runner = WorkerInvokerFactory.makeWorkerInvoker(
            commandRunner: (commandRunner as? StreamingCommandRunner) ?? CommandRunnerAsStreaming(commandRunner),
            invocations: invocations, defaultWorkingDirectory: root
        )

        // RLR-S04a: this foreground process IS the (in-process) coordinator.
        // Record it as a separate root owner (never PG-killed — it is a receipt
        // the contradiction surface reads) and point worker process-group spawns
        // at this run dir so each worker records `runtimeOwnership` keyed by id.
        if let runDir = try? runStore.runDirectory(forRunId: id) {
            ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: runDir)
            if let coordinator = ProcessOwnership.OwnerIdentity.current(kind: .inProcess) {
                try? ProcessOwnership.writeOwnerIdentity(coordinator, in: runDir)
            }
        }
        defer { ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: nil) }

        if preset.runShape == .execution {
            let autoResolved = invocation.autoResolved
            let explicitPin = invocation.explicitWorkerChosen || laneContextOnly
            let provisionalWorker = Worker(
                id: Worker.makeID(modelId: effectiveWorkerId ?? "unknown", instanceIndex: 0),
                modelId: effectiveWorkerId ?? "unknown",
                instanceIndex: 0,
                skillId: "first_principles_builder",
                purpose: .answer
            )
            let initialSelectionOrigin = VendorSubstitutionPolicy.inferInitialSelectionOrigin(
                autoResolved: autoResolved,
                explicitWorkerPin: explicitPin,
                explicitTeamChosen: explicitTeamChosen,
                teamHasDeclaredFallbacks: VendorSubstitutionPolicy.teamHasDeclaredFallbacks(
                    worker: provisionalWorker,
                    team: preset
                )
            )
            let result = await runExecution(
                preset: preset, prompt: prompt, context: request.context, threadId: request.threadId,
                effort: effort, repoRoot: root, requestLane: request.lane,
                explicitTeamChosen: explicitTeamChosen, laneContextOnly: laneContextOnly,
                explicitWorkerIds: explicitWorkerIds,
                projectId: request.projectId, workerOverride: effectiveWorkerId,
                origin: origin, originAgent: originAgent, runId: id, runner: runner,
                deliveries: request.deliveries, requestedAt: requestedAt, timing: timing, events: events,
                workerTimeoutSeconds: request.workerTimeoutSeconds,
                spawnConcurrencyLimit: request.spawnConcurrencyLimit,
                commitMessage: request.commitMessage, noCommit: request.noCommit,
                proofCommand: request.proofCommand, proofTimeoutSeconds: request.proofTimeoutSeconds,
                retryLinks: retryLinks,
                clockBudgets: clockBudgets,
                initialSelectionOrigin: initialSelectionOrigin
            )
            // Parking must release the write lock before the parked journal is
            // returned to the caller; an un-awaited defer could freeze this repo.
            if let lockToken {
                await writeLock.release(lockKey, token: lockToken)
            }
            return result
        }

        // Answer (team) path: no vendor-session continuity — always include the context inline.
        var answerPrompt = prompt
        if let context = request.context, !context.isEmpty {
            answerPrompt += "\n\n# Context\n\(context)"
        }
        let result = await runAnswer(
            preset: preset, prompt: answerPrompt, effort: effort, repoRoot: root,
            projectId: request.projectId, lane: request.lane ?? preset.lane,
            explicitTeamChosen: explicitTeamChosen, laneContextOnly: laneContextOnly,
            explicitWorkerIds: explicitWorkerIds,
            workerOverride: effectiveWorkerId,
            origin: origin, originAgent: originAgent, runId: id, runner: runner,
            deliveries: request.deliveries, timing: timing, events: events,
            retryLinks: retryLinks,
            clockBudgets: clockBudgets
        )
        if let lockToken {
            await writeLock.release(lockKey, token: lockToken)
        }
        return result
    }

    /// SH-S01 / CR-S02 — read-only resolution preview for `alln run --dry-run`.
    /// `RunService` is the sole owner of team/worker/Auto selection, canonical-root
    /// normalization, and write-lock reasoning; the CLI only parses flags, looks up the
    /// registered project, and prints this projection. Resolution runs through the SAME
    /// `RunInvocationResolver` as `run()`; no worker is started (dry-run never dispatches).
    ///
    /// `readyModels` and the governor verdict are live runtime facts the caller observes
    /// (bench probe/cooling state, concurrency capacity). The CLI supplies those facts but
    /// owns no resolution — team shape, write policy, and the live write-lock probe are all
    /// resolved here, not in the CLI.
    public func dryRun(
        _ request: RunRequest,
        readyModels: [Model],
        agent: String? = nil,
        conversationId: String? = nil,
        messageId: String? = nil,
        governorAvailable: Bool = true,
        governorBlockedReason: String? = nil
    ) async -> RunDryRunJSON {
        let root = RunWriteLock.normalize(request.repoRoot) ?? request.repoRoot
        let teamsForResolution = teams.isEmpty ? TeamCatalog.all : teams
        // Only a mutating run needs the live write-lock probe. Resolve the provisional
        // write policy from the same team catalog the resolver uses so the probe input
        // matches the resolved plan — write-lock REASONING lives here, never in the CLI.
        let provisionalMutating = teamsForResolution.first(where: { $0.id == (request.presetId ?? "") })?.mutating
            ?? (request.presetId == nil ? TeamCatalog.defaultRunTeam()?.mutating : nil)
            ?? false
        var writeLockHeld: Bool?
        if provisionalMutating {
            writeLockHeld = await writeLock.isHeld(RunWriteLock.key(repoRoot: root))
        }
        let input = RunInvocationInput(
            message: request.message,
            projectRoot: root,
            flagMode: .dryRun,
            flags: RunInvocationNormalizedFlags(
                projectId: request.projectId,
                teamId: request.presetId,
                workerId: request.workerId,
                effort: request.effort,
                lane: request.lane,
                type: request.type,
                context: request.context,
                json: true,
                noCommit: request.noCommit,
                acceptSurvivors: request.acceptSurvivors,
                commitMessage: request.commitMessage,
                proofCommand: request.proofCommand,
                executorTeamId: request.executorTeamId,
                idleTimeoutSeconds: request.workerTimeoutSeconds,
                handshakeTimeoutSeconds: request.handshakeTimeoutSeconds,
                firstActivityTimeoutSeconds: request.firstActivityTimeoutSeconds,
                wallTimeoutSeconds: request.wallTimeoutSeconds,
                idempotencyKey: request.idempotencyKey,
                retryOf: request.retryOf,
                threadId: request.threadId,
                conversationId: conversationId,
                messageId: messageId,
                agent: agent
            )
        )
        let resolved = RunInvocationResolver.resolve(
            input,
            context: RunInvocationResolveContext(
                models: models,
                teams: teamsForResolution,
                readyModels: readyModels,
                readyModelIds: Set(readyModels.map(\.id)),
                defaultSettings: loadDefaultSettings(),
                writeLockHeld: writeLockHeld,
                governorAvailable: governorAvailable,
                governorBlockedReason: governorBlockedReason
            )
        )
        var payload = resolved.makeDryRunJSON()
        // MR-S04: an explicit worker that resolved not-runnable teaches `alln models`.
        if !resolved.canStart, resolved.explicitWorkerChosen {
            let reason = resolved.blockedReason ?? ""
            if reason.localizedCaseInsensitiveContains("notReady")
                || reason.localizedCaseInsensitiveContains("disabled")
                || reason.localizedCaseInsensitiveContains("unknown")
                || reason.localizedCaseInsensitiveContains("not a runnable") {
                payload.nextAction = AgentNextAction(
                    kind: "listModels",
                    label: "List models",
                    command: "alln models --json")
            }
        }
        return payload
    }

    // MARK: - Execution (one worker, mutating)

    private func runExecution(
        preset: TeamPreset,
        prompt: String,
        context: String? = nil,
        threadId: String? = nil,
        effort: EffortLevel,
        repoRoot: String,
        requestLane: WorkLane?,
        explicitTeamChosen: Bool,
        laneContextOnly: Bool,
        explicitWorkerIds: [String]? = nil,
        projectId: String?,
        workerOverride: String?,
        origin: RunOrigin,
        originAgent: String?,
        runId: String,
        runner: any WorkerInvoking,
        deliveries: [IncludedAttachmentDelivery] = [],
        requestedAt: Date? = nil,
        timing seedTiming: RunTimingReport,
        events: AsyncStream<RunEvent>.Continuation?,
        workerTimeoutSeconds: Int? = nil,
        spawnConcurrencyLimit: Int? = nil,
        commitMessage: String? = nil,
        noCommit: Bool = false,
        proofCommand: String? = nil,
        proofTimeoutSeconds: Int? = nil,
        retryLinks: [RunLink]? = nil,
        clockBudgets: RunClockBudgets? = nil,
        existingRun: TeamRun? = nil,
        resumeSelectionOrigin: String? = nil,
        initialSelectionOrigin: String? = nil,
        substitutionOfAttempt: Int? = nil
    ) async -> Result<TeamRun, RunServiceError> {
        var timing = seedTiming
        let timeoutOverride = workerTimeoutSeconds.map { Duration.seconds($0) }
        var seq: Int64 = 0
        // RLR-S03a: durable activity truth on the sync `alln run` seam. Every
        // emitted event is projected onto `run.json.lastActivityAt` (streaming
        // kinds flush coalesced; spawn/queued map to nil — RLR-L6).
        let activityRecorder = RunActivityRecorder()
        let activityStore = runStore
        func emit(_ kind: String, _ payload: [String: JSONValue]) {
            seq += 1
            let event = RunEvent(id: UUID().uuidString, seq: seq, ts: now(), kind: kind, payload: payload)
            events?.yield(event)
            RunActivityJournalProjection.observe(
                event, runId: runId, store: activityStore, recorder: activityRecorder
            )
        }

        let bench = readyModels()
        timing.stamp(RunTimingKey.workerResolveStart)
        let resolved = TeamResolver.resolve(
            team: preset, requestLane: preset.lane, requestEffort: effort, readyModels: bench
        )
        // SH-S01: an explicit/Auto worker override owns the seat — team roster
        // resolution is only required when we still need the team's preferred pick.
        if workerOverride == nil || (workerOverride ?? "").isEmpty {
            guard resolved.isRunnable else {
                return .failure(.teamResolution(resolved.blockReason ?? "team cannot run", code: "DEFAULT_TEAM_INVALID"))
            }
        }

        let worker: Worker
        var model: Model
        if let override = workerOverride {
            if existingRun != nil {
                // A due same-source wake is the readiness probe. It must bypass
                // the pre-dispatch cooling filter for this one leased attempt,
                // while still requiring the exact enabled model/driver.
                guard let m = models.first(where: { $0.id == override }), m.enabled,
                      registry.manifest(for: m)?.kind == .headlessCLI else {
                    return .failure(.workerNotAvailable(
                        "\(override) is no longer an enabled runnable CLI"
                    ))
                }
                worker = Worker(
                    id: Worker.makeID(modelId: m.id, instanceIndex: 0),
                    modelId: m.id,
                    instanceIndex: 0,
                    skillId: resolved.answerWorkers.first?.skillId ?? "first_principles_builder",
                    purpose: .answer
                )
                model = m
            } else {
                // PO-F10: explicit --worker / --dev-worker is honored or fails LOUD — never
                // silently substitute a different model when the named id is disabled,
                // notReady, or unknown.
                switch resolveExplicitWorker(override) {
                case .failure(let error):
                    return .failure(error)
                case .success(let m):
                    guard let manifest = registry.manifest(for: m), manifest.kind == .headlessCLI else {
                        return .failure(.workerNotAvailable(
                            "\(override) is not a runnable CLI — pick a ready worker; see `alln models` / `alln doctor`."
                        ))
                    }
                    worker = Worker(
                        id: Worker.makeID(modelId: m.id, instanceIndex: 0),
                        modelId: m.id,
                        instanceIndex: 0,
                        skillId: resolved.answerWorkers.first?.skillId ?? "first_principles_builder",
                        purpose: .answer
                    )
                    model = m
                }
            }
        } else if let first = resolved.answerWorkers.first,
                  let m = bench.first(where: { $0.id == first.modelId }) {
            worker = first
            model = m
        } else {
            return .failure(.noWorker("no ready worker for execution team"))
        }

        guard var manifest = registry.manifest(for: model) else {
            return .failure(.noWorker("no driver manifest for \(model.driverId)"))
        }
        timing.stamp(RunTimingKey.workerResolveEnd)
        timing.set(RunTimingKey.modelId, string: model.id)
        timing.set(RunTimingKey.modelDisplayName, string: model.displayName)
        timing.set(RunTimingKey.sourceId, string: manifest.id)
        timing.set(RunTimingKey.commandModelFlag, string: model.resolvedLabel(at: effort))
        timing.set(RunTimingKey.streamingCapable, bool: manifest.canStream)
        timing.stamp(RunTimingKey.driverCommandResolved)

        // Worker_Session_Continuity: resume THIS thread's vendor session for (source, model)
        // if one's alive; on a first turn / model switch, mint or capture a fresh one.
        let sessionKey: ExternalWorkerSession.Key? = threadId.map {
            .init(threadId: $0, sourceId: manifest.id, modelId: model.id, repoRoot: repoRoot)
        }
        let resumable = sessionKey.flatMap { sessionStore.resumable($0) }
        let parkedSessionId = existingRun?.attempts.reversed()
            .compactMap(\.vendorSessionId).first
        let sessionPlan: WorkerSessionPlan? = {
            guard (sessionKey != nil || parkedSessionId != nil), let session = manifest.session,
                  session.continuity == .vendorSession else { return nil }
            if let vendorSessionId = parkedSessionId ?? resumable?.vendorSessionId {
                return WorkerSessionPlan(session: session, resumeSessionId: vendorSessionId, mintSessionId: nil)
            }
            let mint = session.acquire == .set ? UUID().uuidString.lowercased() : nil
            return WorkerSessionPlan(session: session, resumeSessionId: nil, mintSessionId: mint)
        }()

        // Founder rule: only seed the thread context when we are NOT resuming a live vendor
        // session (the CLI already remembers it). First turn / model switch → include it.
        let founderPrompt: String
        if parkedSessionId != nil || resumable != nil {
            founderPrompt = prompt
        } else if let context, !context.isEmpty {
            founderPrompt = prompt + "\n\n# Context\n\(context)"
        } else {
            founderPrompt = prompt
        }

        let skillId = worker.skillId
        let baseAssembled = SkillCatalog.assemblePrompt(skillId: skillId, founderPrompt: founderPrompt)
        // Attach the user's images: a vision worker gets the path block; a non-vision
        // worker gets an explicit notice so it never claims to have seen them.
        var assembled = deliveries.isEmpty ? baseAssembled
            : TeamRunAttachmentMapper.teamRunSeatPrompt(
                basePrompt: baseAssembled,
                deliveries: deliveries,
                readsImages: manifest.canReadImages)
        if !assembled.contains(ProvenanceConvention.trailerMarker) {
            assembled += "\n\n" + ProvenanceConvention.commitTrailerAsk(displayName: model.displayName)
        }
        assembled = Self.appendRunVerificationPrompt(
            assembled,
            commitMessage: commitMessage,
            noCommit: noCommit,
            proofCommand: proofCommand)
        let baselineHead = gitObserver.observe(rootPath: repoRoot).head
        let startedAt = now()
        let effectiveLane = requestLane ?? preset.lane
        // RLR-L3: the default route is a single worker — it never fans out.
        var run: TeamRun
        if var existingRun {
            existingRun.status = .running
            existingRun.phase = .working
            existingRun.blocker = nil
            existingRun.endReason = nil
            existingRun.workers = [worker]
            existingRun.workerAnswers = [
                TeamAnswer(
                    memberId: worker.id,
                    modelId: model.id,
                    role: worker.purpose?.rawValue ?? WorkerStage.answer.rawValue,
                    result: WorkerRunResult(status: .running)
                )
            ]
            existingRun.executionSourceId = model.driverId
            existingRun.repoRoot = repoRoot
            existingRun.threadId = threadId
            if existingRun.clockBudgets == nil { existingRun.clockBudgets = clockBudgets }
            existingRun.attempts.append(RunAttempt(
                attemptNumber: existingRun.attempts.count + 1,
                requestedSourceId: model.driverId,
                requestedModelId: model.id,
                resolvedSourceId: model.driverId,
                resolvedModelId: model.id,
                startedAt: startedAt,
                vendorSessionId: parkedSessionId,
                selectionOrigin: resumeSelectionOrigin,
                substitutionOfAttempt: substitutionOfAttempt
            ))
            run = existingRun
        } else {
            run = TeamRun(
                id: runId, prompt: prompt, status: .running, phase: .working,
                origin: origin, originAgent: originAgent,
                presetId: preset.id, workers: [worker],
                workerAnswers: [TeamAnswer(
                    memberId: worker.id, modelId: model.id,
                    role: worker.purpose?.rawValue ?? WorkerStage.answer.rawValue,
                    result: WorkerRunResult(status: .running)
                )],
                createdAt: startedAt, lane: effectiveLane, effort: effort,
                teamDisplayName: RunIdentity.teamDisplayName(
                    presetId: preset.id, catalogDisplayName: preset.displayName,
                    explicitTeamChosen: explicitTeamChosen),
                outputKind: preset.outputKind,
                // The run's source is where the worker ACTUALLY ran — the chosen
                // model's driver, including Auto overrides.
                mutating: true, executionSourceId: model.driverId,
                threadId: threadId, repoRoot: repoRoot,
                laneContextOnly: laneContextOnly ? true : nil,
                explicitWorkerIds: explicitWorkerIds,
                attempts: [RunAttempt(
                    attemptNumber: 1,
                    requestedSourceId: model.driverId,
                    requestedModelId: model.id,
                    resolvedSourceId: model.driverId,
                    resolvedModelId: model.id,
                    startedAt: startedAt,
                    selectionOrigin: initialSelectionOrigin
                )],
                clockBudgets: clockBudgets,
                links: retryLinks
            )
        }
        timing.count(RunTimingKey.runStoreSaveCount, by: 1)
        run.timing = timing
        // RLR-L2 (item 8): persist BEFORE emitting the status change, so a peer that
        // observes the `running` event can always round-trip the durable journal.
        try? runStore.save(run, models: models)
        emit(RunEventKind.runStatusChanged, [
            "runId": .string(runId), "from": .string(RunStatus.draft.rawValue),
            "to": .string(RunStatus.running.rawValue), "origin": .string(origin.rawValue),
            "presetId": .string(preset.id)
        ])
        var startedPayload: [String: JSONValue] = [
            "runId": .string(runId), "workerId": .string(worker.id), "modelId": .string(model.id),
            "from": .string(WorkerAnswerStatus.queued.rawValue), "to": .string(WorkerAnswerStatus.running.rawValue)
        ]
        if let skillId { startedPayload["skillId"] = .string(skillId) }
        emit(RunEventKind.workerStatusChanged, startedPayload)

        // Stream the single execution worker live when it can: emit accumulated
        // visible answer (`workerAnswerDelta`) AND reasoning (`workerReasoningDelta`)
        // on a time cadence so even short replies visibly stream. If streaming yields
        // nothing usable, FALL BACK to the proven one-shot invoke so the worker always
        // answers.
        var outcome: WorkerRunOutcome
        // Warm_Single_Lane_Chat §5 S4: warm-capable sources (grok, cursor_agent) run as ONE persistent
        // ACP worker per thread — the repo index loads once, then every turn is model-time only.
        if existingRun == nil,
           WarmWorkerCapability.supportsACPStdio(manifest.id),
           let threadId,
           let invoke = manifest.invoke,
           let profile = ACPTransportProfile.make(sourceId: manifest.id, model: model.resolvedLabel(at: effort)) {
            var answer = StreamingPartialBuffer()
            var reasoning = ""
            var lastAnswerEmit = now()
            func emitWarmAnswer() {
                emit(RunEventKind.workerAnswerDelta, [
                    "runId": .string(runId), "workerId": .string(worker.id),
                    "text": .string(answer.visibleText), "truncated": .bool(answer.isTruncated)])
                lastAnswerEmit = now()
            }
            func emitWarmReasoning() {
                emit(RunEventKind.workerReasoningDelta, [
                    "runId": .string(runId), "workerId": .string(worker.id), "text": .string(reasoning)])
            }
            let startedAt = now()
            var firstTokenAt: Date?
            var firstAnswerDeltaAt: Date?
            var lastAnswerDeltaAt: Date?
            var warmAnswerDeltaCount = 0
            var warmReasoningDeltaCount = 0
            var warmReportedUsage: ReportedTokenUsage?
            do {
                let warmKey = ExternalWorkerSession.Key(
                    threadId: threadId, sourceId: manifest.id, modelId: model.id, repoRoot: repoRoot)
                let command = invoke.command
                let warm = try await warmPool.worker(for: warmKey) { key in
                    let transport = try ProcessACPTransport(command: command, profile: profile, cwd: repoRoot)
                    let driver: any WarmSessionDriver = profile.makeDriver(transport: transport)
                    return WarmWorker(key: key, driver: driver, cwd: repoRoot)
                }
                for try await event in try await warm.prompt(assembled) {
                    switch event {
                    case .answerDelta(let text):
                        let t = now()
                        if firstTokenAt == nil { firstTokenAt = t }
                        if firstAnswerDeltaAt == nil { firstAnswerDeltaAt = t }
                        lastAnswerDeltaAt = t
                        warmAnswerDeltaCount += 1
                        let due = answer.append(text)
                        if due || now().timeIntervalSince(lastAnswerEmit) >= 0.1 { emitWarmAnswer() }
                    case .reasoningDelta(let text):
                        if firstTokenAt == nil { firstTokenAt = now() }
                        warmReasoningDeltaCount += 1
                        reasoning += text; emitWarmReasoning()
                    case .reportedUsage(let usage):
                        warmReportedUsage = (warmReportedUsage ?? ReportedTokenUsage()).merged(with: usage)
                    case .toolActivity:
                        break
                    }
                }
                emitWarmAnswer(); if !reasoning.isEmpty { emitWarmReasoning() }
                let text = answer.visibleText
                var warmOutcome = WorkerRunOutcome(status: text.isEmpty ? .failed : .done)
                warmOutcome.timing.startedAt = startedAt
                warmOutcome.timing.finishedAt = now()
                warmOutcome.output = text.isEmpty ? nil : text
                if text.isEmpty { warmOutcome.errorKind = .emptyOutput; warmOutcome.errorReason = "warm worker returned no text" }
                warmOutcome.timing.durationMs = Int(now().timeIntervalSince(startedAt) * 1000)
                if let firstTokenAt {
                    warmOutcome.timing.firstTokenAt = firstTokenAt
                    warmOutcome.timing.ttftMs = Int(firstTokenAt.timeIntervalSince(startedAt) * 1000)
                }
                // Capture the vendor session id the warm driver established, so a later turn can
                // durably resume after the warm worker dies (and so Codex image harvest can map
                // the run to its rollout). The warm worker persists in-memory continuity already;
                // this is the durable record.
                warmOutcome.capturedSessionId = await warm.vendorSessionId()
                warmOutcome.timing.firstAnswerDeltaAt = firstAnswerDeltaAt
                warmOutcome.timing.lastAnswerDeltaAt = lastAnswerDeltaAt
                warmOutcome.timing.answerDeltaCount = warmAnswerDeltaCount
                warmOutcome.timing.reasoningDeltaCount = warmReasoningDeltaCount
                warmOutcome.reportedTokenUsage = warmReportedUsage
                outcome = warmOutcome
            } catch {
                StreamDebugLog.log("WARM FALLBACK source=\(manifest.id): \(error) — cold invoke")
                outcome = await ProcessOwnership.$currentWorkerId.withValue(worker.id) {
                    await runner.collect(WorkerInvocation(
                        model: model, manifest: manifest, prompt: assembled, effort: effort,
                        workingDirectory: repoRoot, timeout: timeoutOverride,
                        sessionPlan: sessionPlan,
                        spawnConcurrencyLimit: spawnConcurrencyLimit
                    ))
                }
            }
        } else {
            // Every other driver — including `opencode`, routed to its warm serve HTTP
            // client by `OpenCodeRoutingWorkerRunner` inside the composed `runner` — drives
            // through the ONE `WorkerInvoking` seam. `DefaultWorkerRunner` degrades
            // internally to a terminal-only stream when a driver has no parser / can't
            // stream (see `WorkerInvoking`'s doc comment), so there is no separate
            // "streaming vs not, opencode vs CLI" branch to maintain here anymore, and no
            // manual spawn-gate juggling (`GatedWorkerRunner` in the composed stack already
            // gates both routes uniformly). The old "stream gave empty output -> retry via
            // a second invoke" fallback is dropped too: a second call through the SAME seam
            // deterministically reproduces the same result, not a different degraded code
            // path — that distinct path no longer exists (F2_B.3c).
            var answer = StreamingPartialBuffer()
            var reasoning = ""
            var lastAnswerEmit = now()
            var lastReasoningEmit = now()
            var terminal: WorkerRunOutcome?
            func emitAnswer() {
                emit(RunEventKind.workerAnswerDelta, [
                    "runId": .string(runId), "workerId": .string(worker.id),
                    "text": .string(answer.visibleText), "truncated": .bool(answer.isTruncated),
                ])
                lastAnswerEmit = now()
            }
            func emitReasoning() {
                emit(RunEventKind.workerReasoningDelta, [
                    "runId": .string(runId), "workerId": .string(worker.id), "text": .string(reasoning),
                ])
                lastReasoningEmit = now()
            }
            do {
                let invocationStream = ProcessOwnership.$currentWorkerId.withValue(worker.id) {
                    runner.invoke(WorkerInvocation(
                        model: model, manifest: manifest, prompt: assembled, effort: effort,
                        workingDirectory: repoRoot, timeout: timeoutOverride, sessionPlan: sessionPlan,
                        spawnConcurrencyLimit: spawnConcurrencyLimit
                    ))
                }
                for try await streamEvent in invocationStream {
                    switch streamEvent {
                    case .answerDelta(let text, _, _):
                        let byteDue = answer.append(text)
                        if byteDue || now().timeIntervalSince(lastAnswerEmit) >= 0.1 { emitAnswer() }
                    case .reasoningDelta(let text, _):
                        reasoning += text
                        if now().timeIntervalSince(lastReasoningEmit) >= 0.1 { emitReasoning() }
                    case .completed(let o), .failed(let o):
                        terminal = o
                    case .started, .rawEvent, .toolActivity:
                        break
                    }
                }
            } catch { /* terminal handled below */ }
            emitAnswer()
            if !reasoning.isEmpty { emitReasoning() }
            outcome = terminal ?? WorkerRunOutcome(
                status: .failed, errorKind: .emptyOutput,
                errorReason: "stream ended without a terminal event")
        }
        // A long park can outlive the vendor's stored session. One rejected
        // resume gets exactly one fresh-session handoff; capacity rejections
        // never take this path (they re-park below).
        if existingRun != nil,
           sessionPlan?.resumeSessionId != nil,
           outcome.capacityObservation.map(VendorBackoffPolicy.shouldPark) != true,
           Self.isRejectedVendorSession(outcome),
           let session = manifest.session {
            if let sessionKey { sessionStore.invalidate(sessionKey) }
            let freshPlan = WorkerSessionPlan(
                session: session,
                resumeSessionId: nil,
                mintSessionId: session.acquire == .set
                    ? UUID().uuidString.lowercased()
                    : nil
            )
            let handoff = Self.freshSessionHandoff(
                originalGoal: prompt,
                priorReason: existingRun?.attempts.reversed().first(where: { $0.reason != nil })?.reason
            )
            outcome = await ProcessOwnership.$currentWorkerId.withValue(worker.id) {
                await runner.collect(WorkerInvocation(
                    model: model,
                    manifest: manifest,
                    prompt: handoff,
                    effort: effort,
                    workingDirectory: repoRoot,
                    timeout: timeoutOverride,
                    sessionPlan: freshPlan,
                    spawnConcurrencyLimit: spawnConcurrencyLimit
                ))
            }
        }
        // A non-streaming worker (agy) can carry its step narration separated from the answer
        // (AGY transcript normalizer). It has no live deltas, so surface it once as a reasoning
        // delta — the turn then shows a clean answer + a "Thought for Ns" bar with the steps.
        if let reasoning = outcome.reasoning, !reasoning.isEmpty {
            emit(RunEventKind.workerReasoningDelta, [
                "runId": .string(runId), "workerId": .string(worker.id), "text": .string(reasoning)])
        }
        let checkpointSessionId = outcome.capturedSessionId
            ?? sessionPlan?.resumeSessionId
            ?? sessionPlan?.mintSessionId

        // RLC-S02 precedence: a sourced parkable account limit on this
        // single-worker accepted run parks BEFORE any SeatReseat consideration.
        // Answer-team parallel rounds never enter this execution-only branch.
        if let observation = outcome.capacityObservation,
           VendorBackoffPolicy.shouldPark(observation) {
            let queueMs: Int? = {
                guard let requestedAt, let invokedAt = outcome.timing.startedAt else { return nil }
                return max(0, Int(invokedAt.timeIntervalSince(requestedAt) * 1000))
            }()
            let answer = TeamAnswer(
                memberId: worker.id,
                modelId: model.id,
                role: worker.purpose?.rawValue ?? WorkerStage.answer.rawValue,
                result: outcome,
                queueMs: queueMs
            )
            run.workerAnswers = [answer]
            Self.settleLatestAttempt(
                in: &run,
                endedAt: outcome.timing.finishedAt ?? now(),
                observation: observation,
                vendorSessionId: checkpointSessionId,
                status: outcome.status,
                reason: outcome.errorReason
            )

            let wakeAfter = VendorBackoffPolicy.computeWakeAfter(
                from: observation,
                now: now()
            )
            if VendorSubstitutionPolicy.prefersSubstitutionOverPark(
                wakeAfter: wakeAfter,
                observation: observation
            ),
               let candidate = automaticSubstituteCandidate(
                run: run,
                failedModelId: model.id,
                preset: preset,
                lane: effectiveLane
               ),
               let runDir = try? runStore.runDirectory(forRunId: runId),
               VendorSubstitutionRuntime.isOriginalWorkerQuiescent(
                runDirectory: runDir,
                run: run
               ) {
                let priorAttempt = run.attempts.last?.attemptNumber
                if let key = sessionKey,
                   let vendorId = checkpointSessionId, !vendorId.isEmpty {
                    sessionStore.upsert(ExternalWorkerSession(
                        threadId: key.threadId,
                        sourceId: key.sourceId,
                        modelId: key.modelId,
                        repoRoot: key.repoRoot,
                        vendorSessionId: vendorId,
                        continuityTier: .vendorSession,
                        createdAt: resumable?.createdAt ?? now(),
                        lastUsedAt: now(),
                        lastRunId: runId
                    ))
                    await warmPool.shutdown(key: key)
                }
                try? runStore.save(run, models: models)
                return await runExecution(
                    preset: preset,
                    prompt: prompt,
                    context: context,
                    threadId: threadId,
                    effort: effort,
                    repoRoot: repoRoot,
                    requestLane: requestLane,
                    explicitTeamChosen: explicitTeamChosen,
                    laneContextOnly: laneContextOnly,
                    explicitWorkerIds: explicitWorkerIds,
                    projectId: projectId,
                    workerOverride: candidate.modelId,
                    origin: origin,
                    originAgent: originAgent,
                    runId: runId,
                    runner: runner,
                    deliveries: deliveries,
                    requestedAt: requestedAt,
                    timing: timing,
                    events: events,
                    workerTimeoutSeconds: workerTimeoutSeconds,
                    spawnConcurrencyLimit: spawnConcurrencyLimit,
                    commitMessage: commitMessage,
                    noCommit: noCommit,
                    proofCommand: proofCommand,
                    proofTimeoutSeconds: proofTimeoutSeconds,
                    retryLinks: retryLinks,
                    clockBudgets: clockBudgets,
                    existingRun: run,
                    resumeSelectionOrigin: candidate.selectionOrigin,
                    substitutionOfAttempt: priorAttempt
                )
            }

            if let key = sessionKey,
               let vendorId = checkpointSessionId, !vendorId.isEmpty {
                sessionStore.upsert(ExternalWorkerSession(
                    threadId: key.threadId,
                    sourceId: key.sourceId,
                    modelId: key.modelId,
                    repoRoot: key.repoRoot,
                    vendorSessionId: vendorId,
                    continuityTier: .vendorSession,
                    createdAt: resumable?.createdAt ?? now(),
                    lastUsedAt: now(),
                    lastRunId: runId
                ))
                await warmPool.shutdown(key: key)
            }

            if run.attempts.count >= VendorBackoffPolicy.maximumAttempts {
                run.status = .failed
                run.phase = nil
                run.blocker = nil
                run.endReason = .failed
                run.warnings.append(
                    "vendor capacity resume attempt limit reached; human attention required"
                )
                try? runStore.save(run, models: models)
                emit(RunEventKind.runStatusChanged, [
                    "runId": .string(runId),
                    "from": .string(RunStatus.running.rawValue),
                    "to": .string(RunStatus.failed.rawValue),
                    "origin": .string(origin.rawValue),
                    "presetId": .string(preset.id)
                ])
                return .success(run)
            }

            run.status = .queued
            run.phase = .waitingForVendor
            run.endReason = nil
            run.blocker = RunBlocker(
                resource: .vendorBackoff,
                quotaScope: observation.source,
                wakeAfter: wakeAfter,
                capacityObservation: observation
            )
            run.repoDelta = gitObserver.repoDelta(
                rootPath: repoRoot,
                baseline: baselineHead,
                head: gitObserver.observe(rootPath: repoRoot).head
            )
            // One atomic run.json revision carries both phase and blocker.
            do {
                try runStore.save(run, models: models)
            } catch {
                return .failure(.journalUnavailable("vendor park: \(error)"))
            }
            emit(RunEventKind.runStatusChanged, [
                "runId": .string(runId),
                "from": .string(RunStatus.running.rawValue),
                "to": .string(RunStatus.queued.rawValue),
                "origin": .string(origin.rawValue),
                "presetId": .string(preset.id)
            ])
            return .success(run)
        }
        // Persist the vendor session this turn established/resumed, so the next turn in this
        // thread resumes it (success only). Only the streaming path carries a captured id;
        // the non-streaming fallback is not session-aware in v1.
        if outcome.status == .done, let key = sessionKey,
           let vendorId = outcome.capturedSessionId, !vendorId.isEmpty {
            sessionStore.upsert(ExternalWorkerSession(
                threadId: key.threadId, sourceId: key.sourceId, modelId: key.modelId, repoRoot: key.repoRoot,
                vendorSessionId: vendorId, continuityTier: .vendorSession,
                createdAt: resumable?.createdAt ?? now(), lastUsedAt: now(), lastRunId: runId))
        }
        // Queue wait: request accepted → CLI spawned. Lane/lock wait + resolution + staging.
        let queueMs: Int? = {
            guard let requestedAt, let startedAt = outcome.timing.startedAt else { return nil }
            return max(0, Int(startedAt.timeIntervalSince(requestedAt) * 1000))
        }()
        let answer = TeamAnswer(
            memberId: worker.id, modelId: model.id, role: worker.purpose?.rawValue ?? WorkerStage.answer.rawValue,
            result: outcome, queueMs: queueMs
        )
        var workerPayload: [String: JSONValue] = [
            "runId": .string(runId), "workerId": .string(worker.id), "modelId": .string(model.id),
            "from": .string(WorkerAnswerStatus.running.rawValue), "to": .string(answer.result.status.rawValue)
        ]
        if let durationMs = answer.result.timing.durationMs { workerPayload["durationMs"] = .int(durationMs) }
        if let reason = answer.result.errorReason { workerPayload["reason"] = .string(reason) }
        emit(RunEventKind.workerStatusChanged, workerPayload)
        timing.stamp(RunTimingKey.processSpawnStart, at: outcome.timing.startedAt ?? startedAt)
        if let firstStderrAt = outcome.timing.firstStderrAt {
            timing.stamp(RunTimingKey.firstStderr, at: firstStderrAt)
        }
        if let firstStdoutAt = outcome.timing.firstStdoutAt {
            timing.stamp(RunTimingKey.firstStdoutChunk, at: firstStdoutAt)
        }
        if let firstParsedEventAt = outcome.timing.firstParsedEventAt {
            timing.stamp(RunTimingKey.firstParsedEvent, at: firstParsedEventAt)
        }
        if let firstAnswerDeltaAt = outcome.timing.firstAnswerDeltaAt {
            timing.stamp(RunTimingKey.firstAnswerDelta, at: firstAnswerDeltaAt)
        }
        if let lastAnswerDeltaAt = outcome.timing.lastAnswerDeltaAt {
            timing.stamp(RunTimingKey.lastAnswerDelta, at: lastAnswerDeltaAt)
        }
        timing.stamp(RunTimingKey.processExit, at: outcome.timing.finishedAt ?? now())
        timing.count(RunTimingKey.rawStdoutChunks, by: outcome.timing.rawStdoutChunkCount)
        timing.count(RunTimingKey.rawStderrChunks, by: outcome.timing.rawStderrChunkCount)
        timing.count(RunTimingKey.parsedStreamEvents, by: outcome.timing.parsedStreamEventCount)
        timing.count(RunTimingKey.answerDeltaCount, by: outcome.timing.answerDeltaCount)
        timing.count(RunTimingKey.reasoningDeltaCount, by: outcome.timing.reasoningDeltaCount)
        run.workerAnswers = [answer]
        Self.settleLatestAttempt(
            in: &run,
            endedAt: outcome.timing.finishedAt ?? now(),
            observation: outcome.capacityObservation,
            vendorSessionId: checkpointSessionId,
            status: outcome.status,
            reason: outcome.errorReason
        )
        // RLR-L8: a worker timeout is a clock fire — settle the kill tree and stamp
        // `timedOut` terminal even when survivors remain (operator-vs-clock asymmetry).
        if answer.result.status == .timedOut {
            if let dir = try? runStore.runDirectory(forRunId: runId) {
                // Persist the in-memory answer first so KillSettlement sees a live journal.
                try? runStore.save(run, models: models)
                let clock = RunClockEnforcer.evaluate(
                    budgets: run.clockBudgets ?? clockBudgets ?? RunClockBudgets(),
                    createdAt: run.createdAt,
                    lastActivityAt: run.lastActivityAt,
                    now: now(),
                    lifecycle: .running,
                    phase: .working,
                    idleBudgetSeconds: workerTimeoutSeconds.map(Double.init)
                ) ?? .idle
                if let fired = RunClockEnforcer.fire(clock: clock, runDirectory: dir, runStore: runStore),
                   let stamped = runStore.loadRaw(runId: runId) {
                    run = stamped
                    _ = fired
                } else {
                    run.status = .timedOut
                    run.endReason = .timedOut
                    run.phase = nil
                }
            } else {
                run.status = .timedOut
                run.endReason = .timedOut
                run.phase = nil
            }
        } else {
            run.status = answer.result.status == .done ? .complete : .failed
            run.phase = nil // terminal clears phase (RLR-L3 atomic rule)
            if run.status == .complete || run.status == .partial || run.status == .done {
                run.endReason = .completed
            } else if run.status == .failed {
                run.endReason = .failed
            }
        }
        run.repoDelta = gitObserver.repoDelta(
            rootPath: repoRoot, baseline: baselineHead, head: gitObserver.observe(rootPath: repoRoot).head)
        run.requestedCommitMessage = commitMessage
        run.noCommitOrdered = noCommit ? true : nil
        if noCommit, run.repoDelta?.changed != true {
            run.uncommittedFileCount = gitObserver.dirtyFiles(rootPath: repoRoot).count
        }
        if let proofCommand, !proofCommand.isEmpty {
            // PO-S03: harness proof is build-class — holds the per-root execution lane.
            // (Dev turns already hold the lane for their full duration; a nested proof
            // re-uses the same key via FIFO handoff if this run is not the outer holder.)
            let laneKey = ExecutionLane.key(repoRoot: repoRoot)
            let proofClaim = ExecutionLane.Claim.current(id: runId, kind: ExecutionLaneSite.harnessProof.rawValue)
                ?? ExecutionLane.Claim(
                    id: runId,
                    kind: ExecutionLaneSite.harnessProof.rawValue,
                    identity: ProcessOwnership.OwnerIdentity(
                        pid: ProcessInfo.processInfo.processIdentifier,
                        pgid: nil,
                        startTimeTicks: 0,
                        kind: .inProcess
                    )
                )
            let proofToken = await writeLock.waitToAcquire(
                laneKey,
                claim: proofClaim,
                timeout: Self.writeLockWaitTimeout
            )
            defer {
                if let proofToken {
                    Task { await writeLock.release(laneKey, token: proofToken, endReason: "completed") }
                }
            }
            let proofRunner = RunProofRunner(commandRunner: commandRunner)
            if proofToken != nil {
                run.proofResult = await proofRunner.run(
                    command: proofCommand,
                    cwd: repoRoot,
                    timeoutSeconds: proofTimeoutSeconds ?? RunProofRunner.defaultTimeoutSeconds)
            } else {
                run.proofResult = RunProofResult(
                    command: proofCommand,
                    exitCode: nil,
                    passed: false,
                    timedOut: false,
                    outputTail: "EXECUTION_LANE_BUSY: harness proof could not acquire the per-root lane"
                )
            }
        }
        if answer.result.status == .done, let text = answer.output {
            let stageId = UUID().uuidString
            emit(RunEventKind.stageStarted, [
                "runId": .string(runId), "purpose": .string("plan"),
                "stageId": .string(stageId), "workerId": .string(worker.id)
            ])
            run.stages.append(StageOutput(
                id: stageId, purpose: .plan, producedByWorkerId: worker.id,
                promptProfileId: skillId, status: .done,
                payload: .plan(markdown: text), startedAt: startedAt, finishedAt: now()
            ))
            emit(RunEventKind.stageCompleted, [
                "runId": .string(runId), "purpose": .string("plan"),
                "stageId": .string(stageId), "workerId": .string(worker.id)
            ])
        }
        emit(RunEventKind.runStatusChanged, [
            "runId": .string(runId), "from": .string(RunStatus.running.rawValue),
            "to": .string(run.status.rawValue), "origin": .string(origin.rawValue),
            "presetId": .string(preset.id)
        ])
        timing.stamp(RunTimingKey.runOutcomePersisted)
        timing.count(RunTimingKey.runStoreSaveCount, by: 1)
        run.timing = timing
        // CR-S02: the terminal result is authoritative. A swallowed write here would
        // report success while the durable journal is lost — surface it (RUN_JOURNAL_UNAVAILABLE).
        do {
            try runStore.save(run, models: models)
        } catch {
            return .failure(.journalUnavailable("terminal execution result: \(error)"))
        }
        return .success(run)
    }

    // MARK: - Answer (N workers, read-only)

    private func runAnswer(
        preset: TeamPreset,
        prompt: String,
        effort: EffortLevel,
        repoRoot: String,
        projectId: String?,
        lane: WorkLane,
        explicitTeamChosen: Bool,
        laneContextOnly: Bool,
        explicitWorkerIds: [String]? = nil,
        workerOverride: String? = nil,
        origin: RunOrigin,
        originAgent: String?,
        runId: String,
        runner: any WorkerInvoking,
        deliveries: [IncludedAttachmentDelivery] = [],
        timing seedTiming: RunTimingReport,
        events: AsyncStream<RunEvent>.Continuation?,
        retryLinks: [RunLink]? = nil,
        clockBudgets: RunClockBudgets? = nil
    ) async -> Result<TeamRun, RunServiceError> {
        var timing = seedTiming
        let bench = readyModels()
        timing.stamp(RunTimingKey.workerResolveStart)
        var resolvedMut = TeamResolver.resolve(
            team: preset, requestLane: lane, requestEffort: effort, readyModels: bench
        )
        guard resolvedMut.isRunnable else {
            return .failure(.teamResolution(resolvedMut.blockReason ?? "team cannot run", code: "DEFAULT_TEAM_INVALID"))
        }

        // AE-S03 / PO-F10: explicit --worker on the answer path is honored or fails
        // loud — never accepted into the idempotency payload and then dropped.
        if let override = workerOverride, !override.isEmpty {
            switch resolveExplicitWorker(override) {
            case .failure(let error):
                return .failure(error)
            case .success(let m):
                guard let manifest = registry.manifest(for: m), manifest.kind == .headlessCLI else {
                    return .failure(.workerNotAvailable(
                        "\(override) is not a runnable CLI — pick a ready worker; see `alln models` / `alln doctor`."
                    ))
                }
                let skillId = resolvedMut.answerWorkers.first?.skillId ?? "first_principles_builder"
                let skillName = resolvedMut.answerWorkers.first?.skillName
                let pinned = Worker(
                    id: Worker.makeID(modelId: m.id, instanceIndex: 0),
                    modelId: m.id,
                    instanceIndex: 0,
                    skillId: skillId,
                    skillName: skillName,
                    purpose: .answer
                )
                resolvedMut.scoutWorker = nil
                resolvedMut.answerWorkers = [pinned]
                resolvedMut.reviewWorkers = []
                TeamSourceFacts.enrich(&resolvedMut, models: models)
            }
        }
        let resolved = resolvedMut
        timing.stamp(RunTimingKey.workerResolveEnd)

        let store = runStore
        let allModels = models
        let coordinator = CatalogRunCoordinator(workerRunner: runner, registry: registry)
        let forwarder: Task<Void, Never>? = events.map { sink in
            Task { for await event in coordinator.events { sink.yield(event) } }
        }
        @Sendable func stamped(_ run: TeamRun) -> TeamRun {
            var r = run
            r.lane = lane; r.effort = effort
            r.laneContextOnly = laneContextOnly ? true : nil
            r.explicitWorkerIds = explicitWorkerIds
            r.teamDisplayName = RunIdentity.teamDisplayName(
                presetId: preset.id, catalogDisplayName: resolved.teamDisplayName,
                explicitTeamChosen: explicitTeamChosen)
            r.outputKind = resolved.outputKind
            r.warnings = resolved.warnings; r.mutating = false
            if let retryLinks { r.links = retryLinks }   // RLR-L9 durable retry link
            if r.clockBudgets == nil { r.clockBudgets = clockBudgets }
            return r
        }
        let persist: @Sendable (TeamRun) -> Void = { try? store.save(stamped($0), models: allModels) }

        // CR-S02: research Teams are observational, not mechanically read-only. Capture
        // the canonical repo's exact Git state before dispatch so an unexpected write by a
        // "read-only" worker is surfaced (never reset) after settlement.
        let researchBaseline = gitObserver.researchSnapshot(rootPath: repoRoot)

        var run = await coordinator.run(
            resolved: resolved, prompt: prompt, models: models,
            origin: origin, originAgent: originAgent, runId: runId,
            repoRoot: repoRoot, deliveries: deliveries, persist: persist
        )
        await forwarder?.value
        run = stamped(run)
        // CR-S02: compare post-settlement Git state against the pre-existing baseline.
        // `changed == true` is a research-write violation — surface it visibly; files are
        // never reset or repaired (Git remains the owner of the working tree).
        let researchObservation = gitObserver.researchObservation(
            rootPath: repoRoot, baseline: researchBaseline)
        run.researchGitObservation = researchObservation
        if researchObservation.changed {
            let pathList = researchObservation.changedPaths.isEmpty
                ? "" : " (\(researchObservation.changedPaths.joined(separator: ", "))\(researchObservation.truncated ? ", …" : ""))"
            run.warnings.append(
                "research-write violation: this read-only research run changed the repository's Git state\(pathList) — Allnighter left the changes in place; review and reset them yourself if unintended.")
        }
        timing.stamp(RunTimingKey.runOutcomePersisted)
        timing.count(RunTimingKey.runStoreSaveCount, by: 1)
        run.timing = timing
        // CR-S02: authoritative terminal result — never swallow a failed journal write.
        do {
            try runStore.save(run, models: models)
        } catch {
            return .failure(.journalUnavailable("terminal research result: \(error)"))
        }
        return .success(run)
    }

    private struct ParkedWakeModel: Sendable {
        var modelId: String
        var selectionOrigin: String
        var substitutionOfAttempt: Int?
    }

    private func automaticSubstituteCandidate(
        run: TeamRun,
        failedModelId: String,
        preset: TeamPreset,
        lane: WorkLane
    ) -> VendorSubstitutionPolicy.Candidate? {
        VendorSubstitutionPolicy.nextAutomaticCandidate(
            run: run,
            failedModelId: failedModelId,
            preset: preset,
            settings: loadDefaultSettings(),
            models: models,
            readyModels: readyModels(),
            coolingSourceIds: coolingSources(),
            lane: lane
        )
    }

    private func resolveParkedWakeModel(
        parked: TeamRun,
        preset: TeamPreset,
        parkedModelId: String,
        substituteModelId: String?,
        selectionOrigin: String
    ) -> Result<ParkedWakeModel, RunServiceError> {
        guard let runDir = try? runStore.runDirectory(forRunId: parked.id) else {
            return .failure(.journalUnavailable("run directory missing for \(parked.id)"))
        }
        guard VendorSubstitutionRuntime.isOriginalWorkerQuiescent(
            runDirectory: runDir,
            run: parked
        ) else {
            return .failure(.teamResolution(
                "original worker is not quiescent — substitution refused",
                code: "WORKER_NOT_QUIESCENT"
            ))
        }

        let settings = loadDefaultSettings()
        let ready = readyModels()
        let cooling = coolingSources()
        let lane = parked.lane ?? preset.lane
        let priorAttempt = parked.attempts.last?.attemptNumber

        if let substituteModelId {
            guard VendorSubstitutionPolicy.acceptsManualCandidate(
                substituteModelId,
                run: parked,
                failedModelId: parkedModelId,
                preset: preset,
                settings: settings,
                models: models,
                readyModels: ready,
                coolingSourceIds: cooling,
                lane: lane
            ) else {
                return .failure(.teamResolution(
                    "model \(substituteModelId) is not an authorized substitute",
                    code: "SUBSTITUTE_NOT_ALLOWED"
                ))
            }
            return .success(ParkedWakeModel(
                modelId: substituteModelId,
                selectionOrigin: RunSelectionOrigin.manualSubstitute,
                substitutionOfAttempt: priorAttempt
            ))
        }

        let wakeAfter = parked.blocker?.wakeAfter
        let observation = parked.blocker?.capacityObservation
        if VendorSubstitutionPolicy.prefersSubstitutionOverPark(
            wakeAfter: wakeAfter,
            observation: observation
        ),
           let candidate = automaticSubstituteCandidate(
            run: parked,
            failedModelId: parkedModelId,
            preset: preset,
            lane: lane
           ) {
            return .success(ParkedWakeModel(
                modelId: candidate.modelId,
                selectionOrigin: candidate.selectionOrigin,
                substitutionOfAttempt: priorAttempt
            ))
        }

        return .success(ParkedWakeModel(
            modelId: parkedModelId,
            selectionOrigin: selectionOrigin,
            substitutionOfAttempt: nil
        ))
    }

    private static func settleLatestAttempt(
        in run: inout TeamRun,
        endedAt: Date,
        observation: CapacityObservation?,
        vendorSessionId: String?,
        status: WorkerAnswerStatus,
        reason: String?
    ) {
        guard let prior = run.attempts.popLast() else { return }
        run.attempts.append(RunAttempt(
            attemptNumber: prior.attemptNumber,
            requestedSourceId: prior.requestedSourceId,
            requestedModelId: prior.requestedModelId,
            resolvedSourceId: prior.resolvedSourceId,
            resolvedModelId: prior.resolvedModelId,
            startedAt: prior.startedAt,
            endedAt: endedAt,
            capacityObservation: observation,
            vendorSessionId: vendorSessionId ?? prior.vendorSessionId,
            selectionOrigin: prior.selectionOrigin,
            substitutionOfAttempt: prior.substitutionOfAttempt,
            terminalStatus: status,
            reason: reason,
            diagnosticSnippet: reason ?? observation?.rawSnippet
        ))
    }

    private static func isRejectedVendorSession(_ outcome: WorkerRunOutcome) -> Bool {
        guard outcome.status == .failed else { return false }
        let text = [outcome.errorReason, outcome.output]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let cues = [
            "session not found",
            "unknown session",
            "invalid session",
            "session expired",
            "conversation not found",
            "thread not found",
        ]
        return cues.contains { text.contains($0) }
    }

    private static func freshSessionHandoff(
        originalGoal: String,
        priorReason: String?
    ) -> String {
        let boundedGoal = String(originalGoal.prefix(4_000))
        let boundedReason = priorReason.map { String($0.prefix(400)) }
            ?? "The prior vendor session could not be resumed."
        return """
        Continue the same accepted Allnighter run in a fresh vendor session.
        Re-read the current repository state before changing anything; prior work may be uncommitted.

        Original goal:
        \(boundedGoal)

        Prior-attempt summary:
        \(boundedReason)
        """
    }

    /// FR12/FR13 prompt blocks — each injected at most once via marker checks.
    static func appendRunVerificationPrompt(
        _ prompt: String,
        commitMessage: String?,
        noCommit: Bool,
        proofCommand: String?
    ) -> String {
        var assembled = prompt
        if let commitMessage, !commitMessage.isEmpty,
           !assembled.contains(ProvenanceConvention.commitMessageMarker) {
            assembled += "\n\n" + ProvenanceConvention.commitMessageVerbatimBlock(message: commitMessage)
        } else if noCommit, !assembled.contains(ProvenanceConvention.noCommitMarker) {
            assembled += "\n\n" + ProvenanceConvention.noCommitBlock()
        }
        if let proofCommand, !proofCommand.isEmpty,
           !assembled.contains(ProvenanceConvention.proofVerificationMarker) {
            assembled += "\n\n" + ProvenanceConvention.proofVerificationLine(command: proofCommand)
        }
        return assembled
    }
}
