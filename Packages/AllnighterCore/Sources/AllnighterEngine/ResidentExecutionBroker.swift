import Foundation
import AllnighterCore

private actor ForegroundRunCompletion {
    private var result: Result<TeamRun, RunServiceError>?

    func finish(_ result: Result<TeamRun, RunServiceError>) { self.result = result }
    func current() -> Result<TeamRun, RunServiceError>? { result }
}

private final class ForegroundRunTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]

    func insert(_ task: Task<Void, Never>, runId: String) {
        lock.lock(); defer { lock.unlock() }
        tasks[runId] = task
    }

    func remove(runId: String) {
        lock.lock(); defer { lock.unlock() }
        tasks.removeValue(forKey: runId)
    }
}

private actor PanelRoundCompletion {
    private var result: Result<PanelCoordinator.RoundResult, PanelCoordinator.RoundError>?
    func finish(_ result: Result<PanelCoordinator.RoundResult, PanelCoordinator.RoundError>) { self.result = result }
    func current() -> Result<PanelCoordinator.RoundResult, PanelCoordinator.RoundError>? { result }
}

private final class PanelRoundTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]
    func insert(_ task: Task<Void, Never>, panelId: String) {
        lock.lock(); defer { lock.unlock() }
        tasks[panelId] = task
    }
    func remove(panelId: String) {
        lock.lock(); defer { lock.unlock() }
        tasks.removeValue(forKey: panelId)
    }
}

/// Coordinator-owned dispatcher for the closed resident operation union. This
/// is the only component that turns an accepted local request into a Team
/// runner; foreground clients only write/read the rendezvous files.
public final class ResidentExecutionBroker: @unchecked Sendable {
    public struct Dependencies: Sendable {
        public var asyncTeam: AsyncTeamService
        public var runService: RunService
        public var models: [Model]
        public var registry: DriverRegistry
        public var runStore: RunStore
        public var invocations: [String: ToolInvocation]
        public var readyModels: @Sendable () -> [Model]
        public var commandRunner: CommandRunner
        public var executablePath: @Sendable () -> String?
        public var doctor: ResidentDoctorService

        public init(
            asyncTeam: AsyncTeamService,
            runService: RunService? = nil,
            models: [Model] = [],
            registry: DriverRegistry = DefaultConfig.registry,
            runStore: RunStore = RunStore(),
            invocations: [String: ToolInvocation] = [:],
            readyModels: @escaping @Sendable () -> [Model],
            commandRunner: CommandRunner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
            executablePath: @escaping @Sendable () -> String? = ProcessOwnership.currentExecutablePath,
            doctor: ResidentDoctorService? = nil
        ) {
            self.asyncTeam = asyncTeam
            self.runService = runService ?? RunService(models: models, registry: registry, runStore: runStore)
            self.models = models
            self.registry = registry
            self.runStore = runStore
            self.invocations = invocations
            self.readyModels = readyModels
            self.commandRunner = commandRunner
            self.executablePath = executablePath
            self.doctor = doctor ?? ResidentDoctorService(models: models, registry: registry, binaryVersion: AllnighterVersionIdentity.binaryVersion)
        }
    }

    private let rendezvous: ResidentExecutionRendezvous
    private let dependencies: Dependencies
    private let foregroundTasks = ForegroundRunTaskRegistry()
    private let panelTasks = PanelRoundTaskRegistry()

    public init(rendezvous: ResidentExecutionRendezvous, dependencies: Dependencies) {
        self.rendezvous = rendezvous
        self.dependencies = dependencies
    }

    public func run(
        isCancelled: @escaping @Sendable () -> Bool,
        isDraining: @escaping @Sendable () -> Bool = { false }
    ) async {
        while !isCancelled() && !Task.isCancelled {
            if isDraining() {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            do {
                if let claim = try rendezvous.claimNext() {
                    await dispatch(claim)
                    continue
                }
            } catch {
                // A malformed/hostile entry is never executed. Leave forensic
                // evidence in the claimed inbox; the coordinator remains alive
                // for subsequent operator recovery rather than silently falling
                // back to caller-owned work.
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func dispatch(_ claim: ResidentExecutionRendezvous.Claim) async {
        let identity: ResidentExecutionRendezvous.Identity
        do {
            identity = try rendezvous.currentIdentity()
        } catch {
            try? rendezvous.reject(
                claim,
                code: "COORDINATOR_UNAVAILABLE",
                message: "resident coordinator identity is unavailable; enable it with `alln serve install`"
            )
            return
        }
        guard claim.request.client.binaryVersion == identity.binaryVersion,
              claim.request.client.binaryGitSha == identity.binaryGitSha,
              claim.request.client.contractVersion == identity.contractVersion else {
            try? rendezvous.reject(
                claim,
                code: "COORDINATOR_VERSION_MISMATCH",
                message: "client \(claim.request.client.binaryVersion)@\(claim.request.client.binaryGitSha.prefix(12))/\(claim.request.client.contractVersion) does not match coordinator \(identity.binaryVersion)@\(identity.binaryGitSha.prefix(12))/\(identity.contractVersion); run `alln serve install`"
            )
            return
        }
        switch claim.request.operation {
        case .teamRun(let request):
            guard let executable = dependencies.executablePath() else {
                try? rendezvous.reject(
                    claim,
                    code: "RESIDENT_REQUEST_REJECTED",
                    message: "resident coordinator could not resolve its alln executable"
                )
                return
            }
            let outcome = await dependencies.asyncTeam.start(
                request,
                origin: .cli,
                readyModels: dependencies.readyModels(),
                ownership: .detachedRunner(executablePath: executable)
            )
            switch outcome {
            case .success(let response):
                try? rendezvous.accept(
                    claim,
                    canonicalId: response.runId,
                    result: .teamStart(response)
                )
            case .failure(let refusal):
                try? rendezvous.reject(claim, code: refusal.code, message: refusal.message)
            }
        case .foregroundTeamRun(let request):
            await startForegroundRun(request, claim: claim)
        case .panelStart(let request):
            startPanel(request, claim: claim)
        case .panelRound(let request):
            await startPanelRound(request, claim: claim)
        case .panelDone(let request):
            finishPanel(request, claim: claim)
        case .sourceProbe(let request):
            if let sourceId = request.sourceId, dependencies.registry.manifest(id: sourceId) == nil {
                try? rendezvous.reject(claim, code: "SOURCE_NOT_FOUND", message: "no source manifest '\(sourceId)'")
                return
            }
            switch request.intent {
            case .doctor:
                let result = await dependencies.doctor.probe(request)
                try? rendezvous.accept(claim, canonicalId: request.sourceId ?? "all", result: .doctor(result))
            case .detect:
                guard request.sourceId == nil else {
                    try? rendezvous.reject(claim, code: "CLI_USAGE_ERROR", message: "source-specific detect is not supported")
                    return
                }
                let result = await dependencies.doctor.detect()
                try? rendezvous.accept(claim, canonicalId: "setup-detect", result: .detection(result))
            }
        case .boostSeed(let request):
            guard dependencies.registry.manifest(id: request.sourceId) != nil else {
                try? rendezvous.reject(claim, code: "UTILIZATION_SOURCE_NOT_FOUND", message: "unknown source: \(request.sourceId)")
                return
            }
            let settings = BoostWindowSettingsPersistence().load()
            guard settings.appliesToSet.contains(request.sourceId) else {
                try? rendezvous.reject(claim, code: "UTILIZATION_SOURCE_UNCONFIGURED", message: "\(request.sourceId) is not in appliesTo")
                return
            }
            let result = await UtilizationSeedExecutor(
                models: dependencies.models,
                registry: dependencies.registry,
                commandRunner: dependencies.commandRunner,
                invocations: dependencies.invocations
            ).execute(sourceId: request.sourceId, settings: settings, force: true)
            try? rendezvous.accept(claim, canonicalId: request.sourceId, result: .utilizationSeed(result))
        case .pendingRun(let request):
            await runPending(request, claim: claim)
        case .projectRecheck(let request):
            await recheckProject(request, claim: claim)
        case .query(let query) where query.kind == .health:
            try? rendezvous.accept(claim, canonicalId: claim.request.coordinatorId)
        case .query(let query) where query.kind == .runStatus:
            guard let runId = query.canonicalId, let status = await dependencies.asyncTeam.status(runId: runId) else {
                try? rendezvous.reject(claim, code: "RUN_NOT_FOUND", message: "no run matches \(query.canonicalId ?? "")")
                return
            }
            try? rendezvous.accept(claim, canonicalId: runId, result: .teamStatus(status))
        case .query(let query) where query.kind == .runResult:
            guard let runId = query.canonicalId else {
                try? rendezvous.reject(claim, code: "RUN_NOT_FOUND", message: "no run id was supplied")
                return
            }
            switch await dependencies.asyncTeam.result(runId: runId) {
            case .notFound:
                try? rendezvous.reject(claim, code: "RUN_NOT_FOUND", message: "no run matches \(runId)")
            case .notReady(let result):
                try? rendezvous.accept(claim, canonicalId: runId, result: .teamResultNotReady(result))
            case .ready(let run):
                let directory = try? dependencies.runStore.runDirectory(forRunId: run.id)
                let context = TeamRunJSONMapper.Context(
                    runJournalPath: directory?.appendingPathComponent("run.json").path ?? "",
                    runDirectory: directory
                )
                let result = TeamRunJSONMapper.map(
                    run,
                    models: dependencies.models,
                    manifests: dependencies.registry.all,
                    context: context
                )
                try? rendezvous.accept(claim, canonicalId: runId, result: .teamResult(result))
            }
        case .query(let query) where query.kind == .panelStatus:
            guard let panelId = query.canonicalId,
                  let state = resolvedPanelState(panelId: panelId) else {
                try? rendezvous.reject(claim, code: "PANEL_NOT_FOUND", message: "no panel matches \(query.canonicalId ?? "")")
                return
            }
            try? rendezvous.accept(
                claim, canonicalId: panelId,
                result: .panelStatus(PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion))
            )
        case .query(let query) where query.kind == .panelResult:
            guard let panelId = query.canonicalId,
                  let state = resolvedPanelState(panelId: panelId),
                  let round = state.rounds.last,
                  let attempt = round.attempts.last else {
                try? rendezvous.reject(claim, code: "PANEL_NOT_FOUND", message: "no settled panel round matches \(query.canonicalId ?? "")")
                return
            }
            try? rendezvous.accept(
                claim, canonicalId: panelId,
                result: .panelRound(panelRoundJSON(state: state, round: round, attempt: attempt))
            )
        case .query(let query) where query.kind == .processSnapshot:
            let snapshot = ProcessOwnershipSurface(runStore: dependencies.runStore).list(scopeRoot: query.scopeRoot)
            try? rendezvous.accept(claim, canonicalId: "process-snapshot", result: .ownership(snapshot))
        case .cancel(let request):
            let surface = ProcessOwnershipSurface(runStore: dependencies.runStore)
            if request.all {
                let result = surface.killAll(scopeRoot: request.scopeRoot)
                try? rendezvous.accept(claim, canonicalId: "ownership-kill-all", result: .ownershipKill(result))
            } else if let id = request.canonicalId {
                switch surface.kill(id: id) {
                case .success(let row):
                    try? rendezvous.accept(claim, canonicalId: id, result: .ownershipKill(.init(killed: [row])))
                case .failure(.notFound):
                    try? rendezvous.reject(claim, code: "OWNERSHIP_NOT_FOUND", message: "no owned process tree matches \(id)")
                case .failure(.alreadyTerminal(_, let end)):
                    try? rendezvous.reject(claim, code: "OWNERSHIP_ALREADY_TERMINAL", message: "\(id) is already terminal\(end.map { " (endReason=\($0))" } ?? "")")
                case .failure(.identityMismatch):
                    try? rendezvous.reject(claim, code: "OWNERSHIP_IDENTITY_MISMATCH", message: "refusing to signal \(id): recorded identity does not match the live process")
                }
            } else {
                try? rendezvous.reject(claim, code: "CLI_USAGE_ERROR", message: "cancel requires an object id or --all")
            }
        default:
            try? rendezvous.reject(
                claim,
                code: "RESIDENT_REQUEST_REJECTED",
                message: "operation \(claim.request.operation.kind.rawValue) is not enabled by this broker slice"
            )
        }
    }

    private func runPending(
        _ request: ResidentExecutionOperation.PendingRun,
        claim: ResidentExecutionRendezvous.Claim
    ) async {
        let executor = PendingRunExecutor(
            service: PendingService(store: PendingStore(), models: dependencies.models),
            registry: dependencies.registry,
            commandRunner: dependencies.commandRunner,
            invocations: dependencies.invocations,
            teams: TeamCatalog.all,
            runStore: dependencies.runStore
        )
        do {
            let item = try await executor.run(id: request.pendingItemId)
            try? rendezvous.accept(claim, canonicalId: item.id, result: .pendingItem(item))
        } catch let error as PendingServiceError {
            let rejection: (String, String)
            switch error {
            case .notFound:
                rejection = ("RUN_NOT_FOUND", "pending item not found: \(request.pendingItemId)")
            case .invalidWorker(let detail):
                rejection = ("MODEL_UNAVAILABLE", detail)
            case .invalidState(let detail), .unsupportedKind(let detail):
                rejection = ("CLI_USAGE_ERROR", detail)
            case .reorderInvalid(let detail):
                rejection = ("PENDING_REORDER_INVALID", detail)
            case .mutationDeferred:
                rejection = ("PENDING_MUTATION_DEFERRED", "mutating runs are outside Pending M1")
            case .sourceGateBlocked(let blocker):
                rejection = (blocker.code, blocker.message)
            }
            try? rendezvous.reject(claim, code: rejection.0, message: rejection.1)
        } catch {
            try? rendezvous.reject(
                claim,
                code: "RESIDENT_REQUEST_REJECTED",
                message: "resident pending run failed: \(error.localizedDescription)"
            )
        }
    }

    private func recheckProject(
        _ request: ResidentExecutionOperation.ProjectRecheck,
        claim: ResidentExecutionRendezvous.Claim
    ) async {
        let detector = ProjectWorkerReadinessDetector(runner: dependencies.commandRunner)
        let now = Date()
        var results: [ProjectWorkerReadiness] = []
        for manifest in dependencies.registry.all.sorted(by: { $0.id < $1.id }) {
            results.append(await detector.detect(
                projectId: request.projectId,
                rootPath: request.rootPath,
                manifest: manifest,
                probeKind: .explicitRecheck,
                now: now
            ))
        }
        do {
            try ProjectWorkerReadinessStore().save(projectId: request.projectId, results)
            try? rendezvous.accept(
                claim,
                canonicalId: request.projectId,
                result: .projectWorkerReadiness(results)
            )
        } catch {
            try? rendezvous.reject(
                claim,
                code: "RESIDENT_REQUEST_REJECTED",
                message: "resident project recheck could not save readiness: \(error.localizedDescription)"
            )
        }
    }

    private func panelCoordinator(stateStore: PanelStateStore = PanelStateStore()) -> PanelCoordinator {
        PanelCoordinator(
            stateStore: stateStore,
            threadProjector: PanelThreadProjector(),
            workerRunner: WorkerInvokerFactory.makeWorkerInvoker(invocations: dependencies.invocations),
            models: dependencies.models,
            registry: dependencies.registry
        )
    }

    private func startPanel(
        _ request: ResidentExecutionOperation.PanelStart,
        claim: ResidentExecutionRendezvous.Claim
    ) {
        let store = PanelStateStore()
        let coordinator = panelCoordinator(stateStore: store)
        let config = PanelCoordinator.Config(
            projectRoot: request.projectRoot,
            projectId: request.projectId,
            targetPath: request.targetPath,
            teamId: request.teamId,
            seats: request.seats,
            maxRounds: request.maxRounds
        )
        switch coordinator.start(config: config, models: dependencies.models, registry: dependencies.registry) {
        case .failure(.emptyRoster):
            try? rendezvous.reject(claim, code: "CLI_USAGE_ERROR", message: "panel roster is empty — pass --team or --seat")
        case .failure(.targetMissing(let path)):
            try? rendezvous.reject(claim, code: "PANEL_TARGET_MISSING", message: "target not found or unreadable: \(path)")
        case .success(let state):
            guard let scaffoldPath = try? PanelBriefScaffold.writeRoundFile(
                panelId: state.id, round: 1, stateStore: store
            ) else {
                try? rendezvous.reject(claim, code: "INTERNAL_ERROR", message: "could not write panel brief scaffold")
                return
            }
            if let teamId = request.teamId { try? PanelTeamStore().save(projectId: request.projectId, teamId: teamId) }
            let target = PanelCoordinator.resolveTargetPath(state.targetPath, projectRoot: state.projectRoot)
            let targetHash = PanelState.contentHash(ofFileAt: target) ?? ""
            let isolation = PanelCoordinator.isolationPlan(
                seats: state.seats, models: dependencies.models, registry: dependencies.registry
            )
            let modes = Dictionary(uniqueKeysWithValues: isolation.map { ($0.workerId, $0.mode.rawValue) })
            let payload = PanelStartJSON(
                contractVersion: ContractRegistry.contractVersion,
                panel: PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion, targetHash: targetHash, isolationBySeat: modes),
                roster: state.seats.map { PanelSeatJSON($0, isolation: modes[$0.workerId]) },
                targetHash: targetHash,
                scaffoldPath: scaffoldPath,
                nextCommand: "alln panel round --panel \(state.id)",
                teamId: state.teamId,
                rememberedTeam: request.rememberedTeam ? true : (request.laneDefault ? false : nil),
                isolation: isolation.map {
                    PanelSeatIsolationJSON(workerId: $0.workerId, mode: $0.mode.rawValue, driverId: $0.driverId, advisory: $0.advisory)
                }
            )
            try? rendezvous.accept(claim, canonicalId: state.id, result: .panelStart(payload))
        }
    }

    private func startPanelRound(
        _ request: ResidentExecutionOperation.PanelRound,
        claim: ResidentExecutionRendezvous.Claim
    ) async {
        let store = PanelStateStore()
        let coordinator = panelCoordinator(stateStore: store)
        let completion = PanelRoundCompletion()
        let tasks = panelTasks
        let task = Task {
            let result = await coordinator.runRound(
                panelId: request.panelId, brief: request.brief, seatFilter: request.seatFilter
            )
            await completion.finish(result)
            tasks.remove(panelId: request.panelId)
        }
        panelTasks.insert(task, panelId: request.panelId)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let state = store.load(id: request.panelId), state.status == .running {
                try? rendezvous.accept(
                    claim, canonicalId: request.panelId,
                    result: .panelStatus(PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion))
                )
                return
            }
            if let result = await completion.current() {
                switch result {
                case .success(let payload):
                    try? rendezvous.accept(
                        claim, canonicalId: request.panelId,
                        result: .panelRound(panelRoundJSON(state: payload.state, round: payload.round, attempt: payload.attempt))
                    )
                case .failure(let error):
                    try? rendezvous.reject(claim, code: panelErrorCode(error), message: panelErrorMessage(error))
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        task.cancel()
        panelTasks.remove(panelId: request.panelId)
        try? rendezvous.reject(claim, code: "RESIDENT_ACCEPT_TIMEOUT", message: "resident panel did not persist round acceptance")
    }

    private func resolvedPanelState(panelId: String) -> PanelState? {
        let store = PanelStateStore()
        guard var state = store.load(id: panelId) else { return nil }
        if state.status == .running && store.isOwnerDead(id: panelId) {
            state = store.reconcileIfOrphaned(state)
            PanelThreadProjector().sync(state: state, now: Date())
        }
        return state
    }

    private func finishPanel(
        _ request: ResidentExecutionOperation.PanelDone,
        claim: ResidentExecutionRendezvous.Claim
    ) {
        switch panelCoordinator().done(panelId: request.panelId, note: request.note) {
        case .success(let state):
            try? rendezvous.accept(
                claim, canonicalId: state.id,
                result: .panelStatus(PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion))
            )
        case .failure(.panelNotFound):
            try? rendezvous.reject(claim, code: "PANEL_NOT_FOUND", message: "no panel matches \(request.panelId)")
        case .failure(.roundInFlight):
            try? rendezvous.reject(claim, code: "PANEL_ROUND_IN_FLIGHT", message: "a round is already dispatching")
        case .failure(.alreadyDone):
            try? rendezvous.reject(claim, code: "PANEL_NOT_AWAITING", message: "panel is already done")
        }
    }

    private func panelRoundJSON(state: PanelState, round: PanelRound, attempt: PanelRoundAttempt) -> PanelRoundJSON {
        PanelRoundJSON(
            contractVersion: ContractRegistry.contractVersion,
            panel: PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion),
            round: round.roundNumber,
            attempt: attempt.attemptNumber,
            outcome: PanelRoundOutcome.project(from: round),
            targetHash: round.targetHash,
            briefSource: round.briefSource.rawValue,
            seatResults: round.seatResults.map(SeatResultJSON.init),
            unstructuredSeats: PanelUnstructuredSeats.project(from: round.seatResults),
            convergence: PanelConvergence.project(from: round.seatResults)
        )
    }

    private func panelErrorCode(_ error: PanelCoordinator.RoundError) -> String {
        switch error {
        case .panelNotFound: return "PANEL_NOT_FOUND"
        case .roundInFlight: return "PANEL_ROUND_IN_FLIGHT"
        case .notAwaitingPM: return "PANEL_NOT_AWAITING"
        case .targetMissing: return "PANEL_TARGET_MISSING"
        case .briefRequired, .maxRoundsReached, .unknownSeats, .emptySeatFilter: return "CLI_USAGE_ERROR"
        }
    }

    private func panelErrorMessage(_ error: PanelCoordinator.RoundError) -> String { "panel round refused: \(error)" }

    /// Begins a full foreground run in the coordinator process and accepts only
    /// after its canonical journal exists. That makes the receipt's run id
    /// immediately queryable while leaving no caller-owned worker path behind.
    private func startForegroundRun(
        _ request: ResidentExecutionOperation.ForegroundTeamRunRequest,
        claim: ResidentExecutionRendezvous.Claim
    ) async {
        let runId = UUID().uuidString.lowercased()
        let completion = ForegroundRunCompletion()
        let requestId = claim.request.requestId
        let runRequest = RunRequest(
            message: request.message,
            repoRoot: request.repoRoot,
            projectId: request.projectId,
            presetId: request.presetId,
            workerId: request.workerId,
            effort: request.effort,
            lane: request.lane,
            type: request.type,
            context: request.context,
            workerTimeoutSeconds: request.workerTimeoutSeconds,
            handshakeTimeoutSeconds: request.handshakeTimeoutSeconds,
            firstActivityTimeoutSeconds: request.firstActivityTimeoutSeconds,
            wallTimeoutSeconds: request.wallTimeoutSeconds,
            commitMessage: request.commitMessage,
            noCommit: request.noCommit,
            proofCommand: request.proofCommand,
            idempotencyKey: request.idempotencyKey,
            retryOf: request.retryOf,
            acceptSurvivors: request.acceptSurvivors
        )
        let service = dependencies.runService
        let tasks = foregroundTasks
        var continuation: AsyncStream<RunEvent>.Continuation?
        let eventStream = AsyncStream<RunEvent> { continuation = $0 }
        let rendezvous = rendezvous
        let eventPump = Task {
            for await event in eventStream {
                try? rendezvous.appendEvent(requestId: requestId, runEvent: event)
            }
        }
        let task = Task {
            let result = await service.run(
                runRequest, origin: .cli, originAgent: request.originAgent, runId: runId, events: continuation
            )
            await completion.finish(result)
            tasks.remove(runId: runId)
            _ = eventPump
        }
        foregroundTasks.insert(task, runId: runId)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let run = dependencies.runStore.loadRaw(runId: runId)
                ?? dependencies.runStore.load(runId: runId) {
                let status = AsyncTeamStatusMapper.statusResponse(for: run)
                let response = TeamStartResponse(
                    runId: run.id,
                    status: status.status,
                    lane: run.lane?.rawValue,
                    teamPresetId: run.presetId,
                    teamDisplayName: run.teamDisplayName,
                    effort: run.effort?.rawValue,
                    acceptedAt: Date(),
                    nextPollAfterMs: status.nextPollAfterMs,
                    nextActions: [.pollStatus(runId: run.id)]
                )
                try? rendezvous.accept(claim, canonicalId: run.id, result: .teamStart(response))
                return
            }
            if let result = await completion.current() {
                switch result {
                case .success(let run):
                    let status = AsyncTeamStatusMapper.statusResponse(for: run)
                    let response = TeamStartResponse(
                        runId: run.id, status: status.status, lane: run.lane?.rawValue,
                        teamPresetId: run.presetId, teamDisplayName: run.teamDisplayName,
                        effort: run.effort?.rawValue, acceptedAt: Date(),
                        nextPollAfterMs: status.nextPollAfterMs,
                        nextActions: [.fetchResult(runId: run.id)]
                    )
                    try? rendezvous.accept(claim, canonicalId: run.id, result: .teamStart(response))
                case .failure(let error):
                    try? rendezvous.reject(claim, code: error.code, message: error.description)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        task.cancel()
        foregroundTasks.remove(runId: runId)
        try? rendezvous.reject(
            claim,
            code: "RESIDENT_ACCEPT_TIMEOUT",
            message: "resident run did not create a durable journal before acceptance"
        )
    }
}
