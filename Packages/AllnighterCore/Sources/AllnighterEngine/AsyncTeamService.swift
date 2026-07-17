import Foundation
import AllnighterCore
import AgentOSTeam

/// Refusal from async `team start` before a run id is minted (or after a refused handshake).
public struct AsyncTeamStartRefusal: Error, Sendable, Equatable {
    public var code: String
    public var message: String
    public var preset: String

    public init(code: String, message: String, preset: String = "") {
        self.code = code; self.message = message; self.preset = preset
    }
}

/// How `AsyncTeamService.start` owns the work after accepting (PO-S01).
public enum AsyncTeamStartOwnership: Sendable {
    /// Coordinator + heartbeat run in this process (unit tests + detached runner child).
    case inProcess
    /// Fork a session-leader runner; this process waits for the runner_ready handshake.
    case detachedRunner(executablePath: String)
}

/// Serializes a run's persists against its cancellation so cancel is always the
/// last write. The background coordinator task persists progress OFF the actor
/// (`persistDuringRun` is a plain `@Sendable` closure), so without this an
/// in-flight progress save could pass a "not cancelled" check, then `cancel`
/// writes `.cancelled`, then the progress save resumes and clobbers it back to a
/// running status — a TOCTOU race on the file store. Holding one lock across both
/// the cancelled-flag flip and the save removes the interleaving entirely.
private final class CancelledRunRegistry: @unchecked Sendable {
    private var ids = Set<String>()
    private let lock = NSLock()

    func contains(_ runId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ids.contains(runId)
    }

    /// Run `save` only if the run is not cancelled — atomically with `cancelAndSave`.
    func saveIfActive(_ runId: String, _ save: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if ids.contains(runId) { return }
        save()
    }

    /// Mark cancelled AND perform the terminal save under the same lock, so no
    /// concurrent progress save can land between the flip and the write.
    func cancelAndSave(_ runId: String, _ save: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        ids.insert(runId)
        save()
    }
}

/// Async team lifecycle — start/status/result/cancel over the shared journal.
public actor AsyncTeamService {
    private struct ActiveRun {
        var slot: TeamGovernor.Slot
        var task: Task<Void, Never>
        var heartbeatTask: Task<Void, Never>?
    }

    private let models: [Model]
    private let registry: DriverRegistry
    private let teams: [TeamPreset]
    private let config: ToolConfig
    public let runStore: RunStore
    private let commandRunner: CommandRunner
    private let governor: TeamGovernor
    private let idempotency: IdempotencyStore
    private let remoteEventJournal: RemoteRunEventJournal
    private let now: @Sendable () -> Date
    private let environment: [String: String]
    private let invocations: [String: ToolInvocation]
    private let idFactory: @Sendable () -> String
    private let cancelledRuns = CancelledRunRegistry()
    private var activeRuns: [String: ActiveRun] = [:]

    public init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset] = TeamCatalog.all,
        config: ToolConfig = ToolConfig(),
        runStore: RunStore = RunStore(),
        commandRunner: CommandRunner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
        governor: TeamGovernor? = nil,
        idempotency: IdempotencyStore = IdempotencyStore(),
        remoteEventJournal: RemoteRunEventJournal? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.runStore = runStore
        self.commandRunner = commandRunner
        self.governor = governor ?? TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.idempotency = idempotency
        self.remoteEventJournal = remoteEventJournal ?? RemoteRunEventJournal(rootDirectory: runStore.rootDirectory)
        self.environment = environment
        self.invocations = invocations
        self.now = now
        self.idFactory = idFactory
    }

    // MARK: - start

    public func start(
        _ request: AsyncTeamStartRequest,
        origin: RunOrigin,
        readyModels: [Model],
        ownership: AsyncTeamStartOwnership = .inProcess
    ) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        let preflight = TeamPreflight.preflight(
            teams: teams,
            lane: request.lane,
            teamId: request.teamPresetId,
            type: request.type,
            effort: request.effort,
            readyModels: readyModels
        )
        guard preflight.canStart else {
            return .failure(.init(code: preflightCode(request, preflight), message: preflight.blockedReason ?? "team cannot start", preset: preflight.teamPresetId ?? ""))
        }

        let canonical = AsyncTeamCanonicalPayload(from: request)
        if let key = request.idempotencyKey, !key.isEmpty {
            if let existing = idempotency.lookup(key: key, now: now()) {
                let digest = IdempotencyStore.digest(canonical)
                if existing.payloadDigest != digest {
                    return .failure(.init(code: "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
                                          message: "idempotency key was already used with a different payload"))
                }
                // Same key + payload → same run id; never spawn a second runner.
                if let run = runStore.loadRaw(runId: existing.runId) ?? runStore.load(runId: existing.runId) {
                    return .success(startResponse(for: run, acceptedAt: existing.acceptedAt))
                }
            }
        }

        if RecursionGuard.atOrOverCeiling(config.maxTeamRunDepth, environment: environment) {
            return .failure(.init(code: "NESTED_TEAM_BLOCKED", message: "already inside a team; nested teams are disabled"))
        }

        guard let resolvedRequest = resolveRequest(request) else {
            return .failure(.init(code: "CLI_USAGE_ERROR", message: "invalid lane/team/effort combination"))
        }
        var resolved = TeamResolver.resolve(
            team: resolvedRequest.team, requestLane: resolvedRequest.lane,
            requestEffort: resolvedRequest.effort, readyModels: readyModels
        )
        guard resolved.isRunnable else {
            let reason = resolved.blockReason ?? "team cannot run"
            let code = reason.contains("plan/output writer") ? "PLAN_WRITER_FAILED" : "DEFAULT_TEAM_INVALID"
            return .failure(.init(code: code, message: reason, preset: resolvedRequest.team.id))
        }

        if let modelId = Self.normalizedModelId(request.modelId) {
            if let pinned = Self.applyModelPin(modelId, to: resolved, readyModels: readyModels) {
                resolved = pinned
            } else if resolved.mutating && resolved.answerWorkers.count == 1 {
                return .failure(.init(
                    code: "CLI_USAGE_ERROR",
                    message: "model is not ready: \(modelId)",
                    preset: resolvedRequest.team.id
                ))
            }
        }

        let sourceGate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels)
        if let blocker = sourceGate.sourceGateBlocker {
            return .failure(.init(code: blocker.code, message: blocker.message, preset: resolvedRequest.team.id))
        }

        switch ownership {
        case .inProcess:
            return startInProcess(
                request: request, origin: origin,
                resolvedRequest: resolvedRequest, resolved: resolved, canonical: canonical
            )
        case .detachedRunner(let executablePath):
            return startDetached(
                request: request, origin: origin,
                resolvedRequest: resolvedRequest, resolved: resolved,
                canonical: canonical, executablePath: executablePath
            )
        }
    }

    private func startInProcess(
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        resolvedRequest: TeamRequestResolver.Resolved,
        resolved: ResolvedTeamRun,
        canonical: AsyncTeamCanonicalPayload
    ) -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        let slot: TeamGovernor.Slot
        switch governor.acquireDetailed() {
        case .acquired(let acquired):
            slot = acquired
        case .busy:
            return .failure(.init(code: "TEAM_GOVERNOR_BUSY", message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                                  preset: resolvedRequest.team.id))
        case .unavailable(let reason):
            return .failure(.init(code: "TEAM_GOVERNOR_UNAVAILABLE", message: reason,
                                  preset: resolvedRequest.team.id))
        }

        let (prompt, _) = assemblePrompt(request)
        let runId = idFactory()
        let acceptedAt = now()
        let run = mintRun(
            runId: runId, prompt: prompt, request: request, origin: origin,
            resolved: resolved, resolvedRequest: resolvedRequest, acceptedAt: acceptedAt
        )
        persist(run, endReasonIfTerminal: nil)

        if let key = request.idempotencyKey, !key.isEmpty {
            _ = try? idempotency.record(key: key, payload: canonical, runId: runId, now: acceptedAt)
        }

        launchInProcess(
            run: run, resolved: resolved, request: request, origin: origin,
            prompt: prompt, slot: slot
        )
        return .success(startResponse(for: run, acceptedAt: acceptedAt))
    }

    /// Detached path: truthful accept via runner_ready handshake (PO-S01 v2).
    /// Parent never prints accepted until the runner holds the governor slot.
    private func startDetached(
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        resolvedRequest: TeamRequestResolver.Resolved,
        resolved: ResolvedTeamRun,
        canonical: AsyncTeamCanonicalPayload,
        executablePath: String
    ) -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        // Fast-path refuse when clearly full — no run dir, no runner (TOCTOU test).
        // Truthful accept still happens in the runner when we do spawn.
        switch governor.availability() {
        case .available:
            break
        case .busy:
            return .failure(.init(code: "TEAM_GOVERNOR_BUSY", message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                                  preset: resolvedRequest.team.id))
        case .unavailable(let reason):
            return .failure(.init(code: "TEAM_GOVERNOR_UNAVAILABLE", message: reason,
                                  preset: resolvedRequest.team.id))
        }

        let (prompt, _) = assemblePrompt(request)
        let runId = idFactory()
        let stagedAt = now()
        let run = mintRun(
            runId: runId, prompt: prompt, request: request, origin: origin,
            resolved: resolved, resolvedRequest: resolvedRequest, acceptedAt: stagedAt
        )

        // Stage journal + request BEFORE spawn so the runner can claim them.
        // Not yet "accepted" to the caller — only after runner_ready.
        persist(run, endReasonIfTerminal: nil)

        // Reserve the idempotency key before spawn so a retry mid-handshake
        // returns the same run id and never launches a second runner.
        if let key = request.idempotencyKey, !key.isEmpty {
            _ = try? idempotency.record(key: key, payload: canonical, runId: runId, now: stagedAt)
        }

        let directory: URL
        do {
            directory = try runStore.runDirectory(forRunId: runId)
        } catch {
            return .failure(.init(code: "INTERNAL_ERROR", message: "run directory unavailable: \(error)"))
        }

        let payload = AsyncTeamRunnerRequest(request: request, origin: origin, acceptedAt: stagedAt)
        do {
            try CoreJSON.encode(payload).write(
                to: directory.appendingPathComponent(ProcessOwnership.runnerRequestFileName),
                options: .atomic
            )
        } catch {
            removeRunDirectory(runId: runId)
            return .failure(.init(code: "INTERNAL_ERROR", message: "could not stage runner request: \(error)"))
        }

        let stdoutPath = directory.appendingPathComponent(ProcessOwnership.runnerStdoutFileName).path
        let stderrPath = directory.appendingPathComponent(ProcessOwnership.runnerStderrFileName).path
        let workingDir = request.repoRoot ?? FileManager.default.currentDirectoryPath

        var extraEnv: [String: String] = ["ALLN_TEAM_RUNNER": "1"]
        if let support = environment["ALLNIGHTER_SUPPORT_DIR"] ?? ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"] {
            extraEnv["ALLNIGHTER_SUPPORT_DIR"] = support
        }

        do {
            _ = try ProcessOwnership.spawnDetachedRunner(
                executablePath: executablePath,
                arguments: ["team", "__runner", "--run-id", runId],
                workingDirectory: workingDir,
                stdoutPath: stdoutPath,
                stderrPath: stderrPath,
                extraEnvironment: extraEnv
            )
        } catch {
            removeRunDirectory(runId: runId)
            return .failure(.init(code: "INTERNAL_ERROR", message: "could not spawn runner: \(error)"))
        }

        // Block until the runner holds the slot and writes the handshake.
        guard let handshake = ProcessOwnership.waitForRunnerReady(in: directory) else {
            _ = ProcessOwnership.terminateRecordedOwnerIfSafe(in: directory)
            removeRunDirectory(runId: runId)
            return .failure(.init(code: "INTERNAL_ERROR", message: "runner did not report ready in time",
                                  preset: resolvedRequest.team.id))
        }

        switch handshake.outcome {
        case .accepted:
            let acceptedAt = handshake.acceptedAt ?? stagedAt
            // Refresh acceptedAt on the reserved key once the slot is truly held.
            if let key = request.idempotencyKey, !key.isEmpty {
                _ = try? idempotency.record(key: key, payload: canonical, runId: runId, now: acceptedAt)
            }
            let acceptedRun = runStore.loadRaw(runId: runId) ?? run
            return .success(startResponse(for: acceptedRun, acceptedAt: acceptedAt))
        case .refused:
            // No accepted envelope; drop the staged run so nothing stays "accepted".
            // Idempotency lookup falls through when the journal is gone, so a same-key
            // retry after a typed refuse can mint a new attempt.
            removeRunDirectory(runId: runId)
            return .failure(.init(
                code: handshake.refusalCode ?? "TEAM_GOVERNOR_BUSY",
                message: handshake.refusalMessage ?? "runner refused start",
                preset: handshake.refusalPreset ?? resolvedRequest.team.id
            ))
        }
    }

    private func mintRun(
        runId: String,
        prompt: String,
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        resolved: ResolvedTeamRun,
        resolvedRequest: TeamRequestResolver.Resolved,
        acceptedAt: Date
    ) -> TeamRun {
        let answerAndReview = resolved.answerWorkers + resolved.reviewWorkers
        return TeamRun(
            id: runId,
            prompt: prompt,
            status: .fanningOut,
            origin: origin,
            originAgent: request.originAgent,
            presetId: resolved.teamPresetId,
            workers: resolved.allWorkers,
            workerAnswers: answerAndReview.map {
                TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? WorkerStage.answer.rawValue,
                          result: WorkerRunResult(status: .queued))
            },
            createdAt: acceptedAt,
            lane: resolvedRequest.lane,
            type: resolvedRequest.type,
            effort: resolvedRequest.effort,
            teamDisplayName: resolved.teamDisplayName,
            outputKind: resolved.outputKind,
            mutating: resolved.mutating,
            executionSourceId: resolved.executionSourceId,
            warnings: resolved.warnings,
            threadId: request.threadId,
            originConversationId: request.originConversationId,
            originMessageId: request.originMessageId,
            repoRoot: request.repoRoot
        )
    }

    private func removeRunDirectory(runId: String) {
        let directory = runStore.rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    /// Detached runner entry: claim ownership, acquire governor, write handshake,
    /// then execute. Called from `alln team __runner`.
    public func executeRunner(runId: String, readyModels: [Model]) async -> Result<Void, AsyncTeamStartRefusal> {
        let directory: URL
        do {
            directory = try runStore.runDirectory(forRunId: runId)
        } catch {
            return .failure(.init(code: "INTERNAL_ERROR", message: "run directory unavailable: \(error)"))
        }

        let requestURL = directory.appendingPathComponent(ProcessOwnership.runnerRequestFileName)
        guard let data = try? Data(contentsOf: requestURL),
              let payload = try? CoreJSON.decode(AsyncTeamRunnerRequest.self, from: data) else {
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "INTERNAL_ERROR", message: "missing runner request for \(runId)"),
                in: directory
            )
            return .failure(.init(code: "INTERNAL_ERROR", message: "missing runner request for \(runId)"))
        }

        // Claim identity as detached runner (pgid recorded; may be PG-killed).
        if let identity = ProcessOwnership.OwnerIdentity.current(kind: .detachedRunner) {
            try? ProcessOwnership.writeOwnerIdentity(identity, in: directory)
        }
        try? ProcessOwnership.recordProgress(in: directory, phase: "runner_starting", now: now())

        // Read raw journal (skip projection).
        guard var run = runStore.loadRaw(runId: runId) else {
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "RUN_NOT_FOUND", message: "no journal for \(runId)"),
                in: directory
            )
            return .failure(.init(code: "RUN_NOT_FOUND", message: "no journal for \(runId)"))
        }
        if run.status.isTerminal {
            try? ProcessOwnership.writeRunnerReady(
                .accepted(runId: runId, at: payload.acceptedAt),
                in: directory
            )
            return .success(())
        }

        let request = payload.request
        guard let resolvedRequest = resolveRequest(request) else {
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "CLI_USAGE_ERROR", message: "invalid lane/team/effort combination"),
                in: directory
            )
            return .failure(.init(code: "CLI_USAGE_ERROR", message: "invalid lane/team/effort combination"))
        }
        var resolved = TeamResolver.resolve(
            team: resolvedRequest.team, requestLane: resolvedRequest.lane,
            requestEffort: resolvedRequest.effort, readyModels: readyModels
        )
        guard resolved.isRunnable else {
            let reason = resolved.blockReason ?? "team cannot run"
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "DEFAULT_TEAM_INVALID", message: reason, preset: resolvedRequest.team.id),
                in: directory
            )
            return .failure(.init(code: "DEFAULT_TEAM_INVALID", message: reason, preset: resolvedRequest.team.id))
        }
        if let modelId = Self.normalizedModelId(request.modelId),
           let pinned = Self.applyModelPin(modelId, to: resolved, readyModels: readyModels) {
            resolved = pinned
        }

        // Acquire governor BEFORE accepted handshake — truthful accept.
        let slot: TeamGovernor.Slot
        switch governor.acquireDetailed() {
        case .acquired(let acquired):
            slot = acquired
        case .busy:
            try? ProcessOwnership.writeRunnerReady(
                .refused(
                    runId: runId,
                    code: "TEAM_GOVERNOR_BUSY",
                    message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                    preset: resolvedRequest.team.id
                ),
                in: directory
            )
            return .failure(.init(code: "TEAM_GOVERNOR_BUSY", message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                                  preset: resolvedRequest.team.id))
        case .unavailable(let reason):
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "TEAM_GOVERNOR_UNAVAILABLE", message: reason, preset: resolvedRequest.team.id),
                in: directory
            )
            return .failure(.init(code: "TEAM_GOVERNOR_UNAVAILABLE", message: reason,
                                  preset: resolvedRequest.team.id))
        }

        let acceptedAt = now()
        try? ProcessOwnership.writeRunnerReady(
            .accepted(runId: runId, at: acceptedAt),
            in: directory
        )
        try? ProcessOwnership.recordProgress(in: directory, phase: "accepted", now: acceptedAt)

        let (prompt, _) = assemblePrompt(request)
        launchInProcess(
            run: run, resolved: resolved, request: request, origin: payload.origin,
            prompt: prompt, slot: slot
        )
        if let active = activeRuns[runId] {
            await active.task.value
        }
        return .success(())
    }

    // MARK: - launch helpers

    private func launchInProcess(
        run: TeamRun,
        resolved: ResolvedTeamRun,
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        prompt: String,
        slot: TeamGovernor.Slot
    ) {
        let runId = run.id
        let store = runStore
        let allModels = models
        let lane = run.lane
        let type = run.type
        let effort = run.effort
        let teamName = run.teamDisplayName
        let outputKind = run.outputKind
        let warnings = run.warnings
        let mutating = run.mutating

        @Sendable func stamped(_ r: TeamRun) -> TeamRun {
            var copy = r
            copy.lane = lane; copy.type = type; copy.effort = effort
            copy.teamDisplayName = teamName; copy.outputKind = outputKind; copy.warnings = warnings
            copy.mutating = mutating
            copy.threadId = request.threadId
            copy.originConversationId = request.originConversationId
            copy.originMessageId = request.originMessageId
            copy.repoRoot = request.repoRoot
            // Never infer endReason from status. Coordinator/cancel/reconcile
            // stamp what they know; missing on a terminal run → honest unknown.
            if copy.status.isTerminal, copy.endReason == nil {
                copy.endReason = .unknown
            }
            return copy
        }
        let cancelledRuns = cancelledRuns
        let persistDuringRun: @Sendable (TeamRun) -> Void = { incoming in
            cancelledRuns.saveIfActive(runId) {
                _ = try? store.save(stamped(incoming), models: allModels)
                // Progress-truth: touch on real progress (persist = worker/state change).
                if let directory = try? store.runDirectory(forRunId: runId) {
                    let phase = incoming.status.rawValue
                    try? ProcessOwnership.recordProgress(in: directory, phase: phase)
                }
            }
        }

        let coordinator = CatalogRunCoordinator(
            workerRunner: WorkerInvokerFactory.makeWorkerInvoker(
                commandRunner: (commandRunner as? StreamingCommandRunner) ?? CommandRunnerAsStreaming(commandRunner), invocations: invocations),
            registry: registry,
            idFactory: idFactory,
            now: now
        )
        let remoteEventJournal = remoteEventJournal
        let heartbeatDirectory = try? store.runDirectory(forRunId: runId)

        // Timer floor only — does not bump progress sequence.
        let heartbeatTask = Task {
            guard let heartbeatDirectory else { return }
            while !Task.isCancelled {
                try? ProcessOwnership.touchHeartbeatFloor(in: heartbeatDirectory)
                try? await Task.sleep(nanoseconds: UInt64(ProcessOwnership.heartbeatIntervalSeconds * 1_000_000_000))
            }
        }

        let task = Task {
            async let eventRecorder: Void = Self.recordRemoteEvents(coordinator.events, to: remoteEventJournal)
            _ = await coordinator.run(
                resolved: resolved, prompt: prompt, models: models,
                origin: origin, originAgent: request.originAgent,
                runId: runId, repoRoot: request.repoRoot, persist: persistDuringRun
            )
            await eventRecorder
            heartbeatTask.cancel()
            self.finishActiveRun(runId: runId, slot: slot)
        }
        activeRuns[runId] = ActiveRun(slot: slot, task: task, heartbeatTask: heartbeatTask)
    }

    private nonisolated static func recordRemoteEvents(
        _ events: AsyncStream<RunEvent>,
        to journal: RemoteRunEventJournal
    ) async {
        for await event in events {
            do {
                _ = try journal.append(event)
            } catch {
                StreamDebugLog.log("REMOTE_EVENT_JOURNAL_APPEND_FAILED event=\(event.id) error=\(error)")
            }
        }
    }

    // MARK: - status / result / cancel / reconcile

    /// Explicit path: may reconcile (kill + terminal write) under per-run flock.
    public func status(runId: String) -> TeamStatusResponse? {
        _ = runStore.reconcileRun(runId: runId, models: models)
        guard let run = runStore.load(runId: runId) else { return nil }
        var response = AsyncTeamStatusMapper.statusResponse(for: run)
        if let directory = try? runStore.runDirectory(forRunId: runId) {
            response.lastProgressAt = ProcessOwnership.lastProgressAt(in: directory)
            if !run.status.isTerminal,
               !ProcessOwnership.isOwnerIdentityDead(in: directory),
               ProcessOwnership.isProgressStale(in: directory) {
                response.progressStale = true
            }
        }
        return AsyncTeamStatusMapper.withWaitGuidance(response)
    }

    /// In-process blocking wait for a live status (PO-F3). Single process; sleeps
    /// on `waitHintSeconds` between re-reads — no tight poll spin, no second
    /// process. Returns on target match, non-matching terminal, or timeout.
    public func waitForStatus(
        runId: String,
        target: TeamStatusWaitTarget,
        timeout: Duration
    ) async -> TeamStatusWaitOutcome? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            guard let response = status(runId: runId) else { return nil }
            if target.matches(response.status) {
                var matched = response
                matched.waitHintSeconds = 0
                matched.nextAction = AsyncTeamStatusMapper.nextAction(
                    for: response.status, runId: runId
                )
                return TeamStatusWaitOutcome(
                    response: matched, timedOut: false, terminalMismatch: false
                )
            }
            // Different terminal state: stop waiting — the run will not reverse.
            if response.status.isTerminal {
                return TeamStatusWaitOutcome(
                    response: response, timedOut: false, terminalMismatch: true
                )
            }
            let now = clock.now
            if now >= deadline {
                // Keep waitHint for the agent; stamp timeout on the outcome.
                return TeamStatusWaitOutcome(
                    response: response, timedOut: true, terminalMismatch: false
                )
            }
            let remaining = deadline - now
            let hintMs = max(50, response.nextPollAfterMs)
            let sleepFor = min(Duration.milliseconds(hintMs), remaining)
            try? await Task.sleep(for: sleepFor, clock: ContinuousClock())
        }
    }

    /// Explicit reconcile path (`alln team reconcile`). Returns only runs this
    /// call newly reaped (never lists already-terminal or still-alive runs).
    public func reconcile(runId: String?) -> [TeamRun] {
        if let runId {
            if let detail = runStore.reconcileRunDetailed(runId: runId, models: models), detail.reaped {
                return [detail.run]
            }
            return []
        }
        return runStore.reconcileAll(models: models)
    }

    public enum ResultOutcome: Sendable, Equatable {
        case ready(TeamRun)
        case notReady(TeamResultNotReady)
        case notFound
    }

    public func result(runId: String) -> ResultOutcome {
        _ = runStore.reconcileRun(runId: runId, models: models)
        guard let run = runStore.load(runId: runId) else { return .notFound }
        let live = AsyncTeamStatusMapper.liveStatus(for: run)
        if AsyncTeamStatusMapper.resultAvailable(for: run) {
            return .ready(run)
        }
        return .notReady(TeamResultNotReady(
            runId: runId,
            status: live,
            resultAvailable: false,
            nextPollAfterMs: AsyncTeamStatusMapper.nextPollAfterMs(for: live),
            error: ErrorEnvelope(
                code: "RESULT_NOT_READY",
                message: "run is not terminal yet; poll team status",
                requiresManual: false,
                retryable: true
            )
        ))
    }

    public func cancel(runId: String) -> TeamCancelResponse? {
        // Explicit path: reconcile first under flock semantics, then cancel.
        _ = runStore.reconcileRun(runId: runId, models: models)
        guard let loaded = runStore.loadRaw(runId: runId) ?? runStore.load(runId: runId) else { return nil }
        guard !loaded.status.isTerminal else {
            return TeamCancelResponse(runId: runId, status: AsyncTeamStatusMapper.liveStatus(for: loaded), cancelledAt: now())
        }

        if let active = activeRuns.removeValue(forKey: runId) {
            active.heartbeatTask?.cancel()
            active.task.cancel()
        } else if let directory = try? runStore.runDirectory(forRunId: runId) {
            _ = ProcessOwnership.terminateRecordedOwnerIfSafe(in: directory)
        }

        cancelledRuns.cancelAndSave(runId) {
            ProcessOwnership.withRunLock(in: (try? self.runStore.runDirectory(forRunId: runId)) ?? self.runStore.rootDirectory) {
                var run = self.runStore.loadRaw(runId: runId) ?? loaded
                // Never clobber an existing terminal status.
                guard !run.status.isTerminal else { return }
                run.status = .cancelled
                run.endReason = .cancelled
                for i in run.workerAnswers.indices where !run.workerAnswers[i].result.status.isTerminal {
                    run.workerAnswers[i].result.status = .cancelled
                }
                _ = try? self.runStore.save(run, models: self.models)
            }
        }
        return TeamCancelResponse(runId: runId, status: .cancelled, cancelledAt: now())
    }

    public func cancelAll() -> StopAllResult {
        let runIds = Array(activeRuns.keys)
        var terminated = 0
        for runId in runIds {
            if cancel(runId: runId) != nil {
                terminated += 1
            }
        }
        return StopAllResult(terminated: terminated)
    }

    // MARK: - helpers

    private func finishActiveRun(runId: String, slot: TeamGovernor.Slot) {
        if let active = activeRuns.removeValue(forKey: runId) {
            active.heartbeatTask?.cancel()
        }
        _ = slot
    }

    private func persist(_ run: TeamRun, endReasonIfTerminal: RunEndReason?) {
        cancelledRuns.saveIfActive(run.id) {
            var r = run
            if r.status.isTerminal, r.endReason == nil {
                r.endReason = endReasonIfTerminal ?? .unknown
            }
            _ = try? self.runStore.save(r, models: self.models)
        }
    }

    private func resolveRequest(_ request: AsyncTeamStartRequest) -> TeamRequestResolver.Resolved? {
        switch TeamRequestResolver.resolve(teams: teams, lane: request.lane, teamId: request.teamPresetId,
                                          type: request.type, effort: request.effort) {
        case .success(let r): return r
        case .failure: return nil
        }
    }

    private func assemblePrompt(_ request: AsyncTeamStartRequest) -> (String, Bool) {
        var truncated = false
        var prompt = request.question
        if let context = request.context, !context.isEmpty {
            let bytes = Array(context.utf8)
            if bytes.count > config.contextByteLimit {
                let half = config.contextByteLimit / 2
                let head = String(decoding: bytes.prefix(half), as: UTF8.self)
                let tail = String(decoding: bytes.suffix(half), as: UTF8.self)
                prompt += "\n\n# Context\n\(head)\n[… truncated \(bytes.count - config.contextByteLimit) bytes …]\n\(tail)"
                truncated = true
            } else {
                prompt += "\n\n# Context\n\(context)"
            }
        }
        return (prompt, truncated)
    }

    private func startResponse(for run: TeamRun, acceptedAt: Date) -> TeamStartResponse {
        let live = AsyncTeamStatusMapper.liveStatus(for: run)
        return TeamStartResponse(
            runId: run.id,
            status: live,
            lane: run.lane?.rawValue,
            teamPresetId: run.presetId,
            teamDisplayName: run.teamDisplayName,
            effort: run.effort?.rawValue,
            acceptedAt: acceptedAt,
            nextPollAfterMs: AsyncTeamStatusMapper.nextPollAfterMs(for: live),
            nextActions: [
                .init(kind: "poll", tool: "team_status", runId: run.id),
                .init(kind: "result", tool: "team_result", runId: run.id),
            ]
        )
    }

    private func preflightCode(_ request: AsyncTeamStartRequest, _ preflight: TeamPreflight.Result) -> String {
        if preflight.sourceGateStatus == SourceGateStatus.blocked.rawValue {
            return ExecutionTeamSourceGate.mixedSourcesCode
        }
        if case .failure(let failure) = TeamRequestResolver.resolve(
            teams: teams, lane: request.lane, teamId: request.teamPresetId,
            type: request.type, effort: request.effort) {
            return failure.code
        }
        if preflight.blockedReason?.contains("plan/output writer") == true { return "PLAN_WRITER_FAILED" }
        return "DEFAULT_TEAM_INVALID"
    }

    private static func normalizedModelId(_ modelId: String?) -> String? {
        guard let modelId else { return nil }
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Pin a ready bench model on single-worker mutating teams (Default Team / Auto).
    private static func applyModelPin(
        _ modelId: String,
        to resolved: ResolvedTeamRun,
        readyModels: [Model]
    ) -> ResolvedTeamRun? {
        guard readyModels.contains(where: { $0.id == modelId }) else { return nil }
        guard resolved.mutating, resolved.answerWorkers.count == 1 else { return nil }

        var pinned = resolved
        var worker = pinned.answerWorkers[0]
        if worker.modelId == modelId {
            return pinned
        }
        worker.substitutedFromModelId = worker.modelId
        worker.modelId = modelId
        worker.id = Worker.makeID(modelId: modelId, instanceIndex: worker.instanceIndex)
        pinned.answerWorkers[0] = worker
        TeamSourceFacts.enrich(&pinned, models: readyModels)
        return pinned
    }
}
