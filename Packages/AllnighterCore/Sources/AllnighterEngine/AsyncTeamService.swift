import Foundation
import AllnighterCore
import AgentOSTeam

/// Refusal from async `team start` before a run id is minted.
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
    /// Fork a session-leader runner; this process only accepts and returns.
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
                if let run = runStore.load(runId: existing.runId) {
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

        // Detached parent only probes capacity — the runner process holds the flock
        // so it outlives the accepting CLI. In-process holds the slot here.
        let slot: TeamGovernor.Slot?
        switch ownership {
        case .inProcess:
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
        case .detachedRunner:
            switch governor.availability() {
            case .available:
                slot = nil
            case .busy:
                return .failure(.init(code: "TEAM_GOVERNOR_BUSY", message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                                      preset: resolvedRequest.team.id))
            case .unavailable(let reason):
                return .failure(.init(code: "TEAM_GOVERNOR_UNAVAILABLE", message: reason,
                                      preset: resolvedRequest.team.id))
            }
        }

        let (prompt, _) = assemblePrompt(request)
        let runId = idFactory()
        let acceptedAt = now()
        let answerAndReview = resolved.answerWorkers + resolved.reviewWorkers
        let run = TeamRun(
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
        persist(run)

        if let key = request.idempotencyKey, !key.isEmpty {
            _ = try? idempotency.record(key: key, payload: canonical, runId: runId, now: acceptedAt)
        }

        switch ownership {
        case .inProcess:
            guard let slot else {
                return .failure(.init(code: "INTERNAL_ERROR", message: "missing governor slot"))
            }
            launchInProcess(
                run: run, resolved: resolved, request: request, origin: origin,
                prompt: prompt, slot: slot
            )
        case .detachedRunner(let executablePath):
            if let refusal = spawnDetachedRunner(
                run: run, request: request, origin: origin,
                acceptedAt: acceptedAt, executablePath: executablePath
            ) {
                return .failure(refusal)
            }
        }

        return .success(startResponse(for: run, acceptedAt: acceptedAt))
    }

    /// Detached runner entry: claim ownership of an already-accepted run, heartbeat,
    /// acquire the governor, and execute. Called from `alln team __runner`.
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
            return .failure(.init(code: "INTERNAL_ERROR", message: "missing runner request for \(runId)"))
        }

        // Read raw journal (skip reconcile projection that could race our claim).
        let runURL = directory.appendingPathComponent("run.json")
        guard let raw = try? Data(contentsOf: runURL),
              var run = try? CoreJSON.decode(TeamRun.self, from: raw) else {
            return .failure(.init(code: "RUN_NOT_FOUND", message: "no journal for \(runId)"))
        }
        if run.status.isTerminal {
            return .success(())
        }

        // Claim ownership + fresh heartbeat before any external status poll.
        try? ProcessOwnership.writeOwnerPID(ProcessInfo.processInfo.processIdentifier, in: directory)
        try? ProcessOwnership.touchHeartbeat(in: directory)

        let request = payload.request
        guard let resolvedRequest = resolveRequest(request) else {
            return .failure(.init(code: "CLI_USAGE_ERROR", message: "invalid lane/team/effort combination"))
        }
        var resolved = TeamResolver.resolve(
            team: resolvedRequest.team, requestLane: resolvedRequest.lane,
            requestEffort: resolvedRequest.effort, readyModels: readyModels
        )
        guard resolved.isRunnable else {
            let reason = resolved.blockReason ?? "team cannot run"
            run.status = .failed
            run.endReason = .failed
            run.warnings.append(reason)
            _ = try? runStore.save(run, models: models)
            return .failure(.init(code: "DEFAULT_TEAM_INVALID", message: reason, preset: resolvedRequest.team.id))
        }
        if let modelId = Self.normalizedModelId(request.modelId),
           let pinned = Self.applyModelPin(modelId, to: resolved, readyModels: readyModels) {
            resolved = pinned
        }

        let slot: TeamGovernor.Slot
        switch governor.acquireDetailed() {
        case .acquired(let acquired):
            slot = acquired
        case .busy:
            run.status = .failed
            run.endReason = .failed
            run.warnings.append("team governor busy at runner launch")
            _ = try? runStore.save(run, models: models)
            return .failure(.init(code: "TEAM_GOVERNOR_BUSY", message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                                  preset: resolvedRequest.team.id))
        case .unavailable(let reason):
            run.status = .failed
            run.endReason = .failed
            run.warnings.append(reason)
            _ = try? runStore.save(run, models: models)
            return .failure(.init(code: "TEAM_GOVERNOR_UNAVAILABLE", message: reason,
                                  preset: resolvedRequest.team.id))
        }

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
            if copy.status.isTerminal, copy.endReason == nil {
                copy.endReason = RunEndReason.inferred(from: copy.status)
            }
            return copy
        }
        let cancelledRuns = cancelledRuns
        let persistDuringRun: @Sendable (TeamRun) -> Void = { incoming in
            cancelledRuns.saveIfActive(runId) {
                _ = try? store.save(stamped(incoming), models: allModels)
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

        let heartbeatTask = Task {
            guard let heartbeatDirectory else { return }
            while !Task.isCancelled {
                try? ProcessOwnership.touchHeartbeat(in: heartbeatDirectory)
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

    private func spawnDetachedRunner(
        run: TeamRun,
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        acceptedAt: Date,
        executablePath: String
    ) -> AsyncTeamStartRefusal? {
        let runId = run.id
        let directory: URL
        do {
            directory = try runStore.runDirectory(forRunId: runId)
        } catch {
            return .init(code: "INTERNAL_ERROR", message: "run directory unavailable: \(error)")
        }

        let payload = AsyncTeamRunnerRequest(
            request: request,
            origin: origin,
            acceptedAt: acceptedAt
        )
        do {
            try CoreJSON.encode(payload).write(
                to: directory.appendingPathComponent(ProcessOwnership.runnerRequestFileName),
                options: .atomic
            )
        } catch {
            return .init(code: "INTERNAL_ERROR", message: "could not stage runner request: \(error)")
        }

        let stdoutPath = directory.appendingPathComponent(ProcessOwnership.runnerStdoutFileName).path
        let stderrPath = directory.appendingPathComponent(ProcessOwnership.runnerStderrFileName).path
        let workingDir = request.repoRoot ?? FileManager.default.currentDirectoryPath

        var extraEnv: [String: String] = ["ALLN_TEAM_RUNNER": "1"]
        if let support = environment["ALLNIGHTER_SUPPORT_DIR"] ?? ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"] {
            extraEnv["ALLNIGHTER_SUPPORT_DIR"] = support
        }

        let childPid: Int32
        do {
            childPid = try ProcessOwnership.spawnDetachedRunner(
                executablePath: executablePath,
                arguments: ["team", "__runner", "--run-id", runId],
                workingDirectory: workingDir,
                stdoutPath: stdoutPath,
                stderrPath: stderrPath,
                extraEnvironment: extraEnv
            )
        } catch {
            var failed = run
            failed.status = .failed
            failed.endReason = .failed
            failed.warnings.append("could not spawn runner: \(error)")
            persist(failed)
            return .init(code: "INTERNAL_ERROR", message: "could not spawn runner: \(error)")
        }

        // Runner pid is the owner-of-record from the moment of spawn.
        try? ProcessOwnership.writeOwnerPID(childPid, in: directory)
        try? ProcessOwnership.touchHeartbeat(in: directory)
        return nil
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

    // MARK: - status / result / cancel

    public func status(runId: String) -> TeamStatusResponse? {
        guard let run = runStore.load(runId: runId) else { return nil }
        return AsyncTeamStatusMapper.statusResponse(for: run)
    }

    public enum ResultOutcome: Sendable, Equatable {
        case ready(TeamRun)
        case notReady(TeamResultNotReady)
        case notFound
    }

    public func result(runId: String) -> ResultOutcome {
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
        guard let loaded = runStore.load(runId: runId) else { return nil }
        guard !loaded.status.isTerminal else {
            return TeamCancelResponse(runId: runId, status: AsyncTeamStatusMapper.liveStatus(for: loaded), cancelledAt: now())
        }

        if let active = activeRuns.removeValue(forKey: runId) {
            active.heartbeatTask?.cancel()
            active.task.cancel()
        } else if let directory = try? runStore.runDirectory(forRunId: runId),
                  let ownerPid = ProcessOwnership.readOwnerPID(in: directory) {
            ProcessOwnership.terminateProcessGroup(of: ownerPid)
        }

        cancelledRuns.cancelAndSave(runId) {
            var run = self.runStore.load(runId: runId) ?? loaded
            if !run.status.isTerminal || run.status == .interrupted {
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

    private func persist(_ run: TeamRun) {
        cancelledRuns.saveIfActive(run.id) {
            var r = run
            if r.status.isTerminal, r.endReason == nil {
                r.endReason = RunEndReason.inferred(from: r.status)
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
