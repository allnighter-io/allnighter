import Foundation
import AllnighterCore

/// Refusal from async `team start` before a run id is minted.
public struct AsyncTeamStartRefusal: Error, Sendable, Equatable {
    public var code: String
    public var message: String
    public var preset: String

    public init(code: String, message: String, preset: String = "") {
        self.code = code; self.message = message; self.preset = preset
    }
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
    }

    private let models: [Model]
    private let registry: DriverRegistry
    private let teams: [TeamPreset]
    private let config: ToolConfig
    private let runStore: RunStore
    private let commandRunner: CommandRunner
    private let governor: TeamGovernor
    private let idempotency: IdempotencyStore
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
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        governor: TeamGovernor? = nil,
        idempotency: IdempotencyStore = IdempotencyStore(),
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
        self.environment = environment
        self.invocations = invocations
        self.now = now
        self.idFactory = idFactory
    }

    // MARK: - start

    public func start(
        _ request: AsyncTeamStartRequest,
        origin: RunOrigin,
        readyModels: [Model]
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
        let resolved = TeamResolver.resolve(
            team: resolvedRequest.team, requestLane: resolvedRequest.lane,
            requestEffort: resolvedRequest.effort, readyModels: readyModels
        )
        guard resolved.isRunnable else {
            let reason = resolved.blockReason ?? "team cannot run"
            let code = reason.contains("plan/output writer") ? "PLAN_WRITER_FAILED" : "DEFAULT_TEAM_INVALID"
            return .failure(.init(code: code, message: reason, preset: resolvedRequest.team.id))
        }

        guard let slot = governor.acquire() else {
            return .failure(.init(code: "TEAM_GOVERNOR_BUSY", message: "busy: \(config.maxConcurrentTeamRuns) team runs already running",
                                  preset: resolvedRequest.team.id))
        }

        let (prompt, _) = assemblePrompt(request)
        let runId = idFactory()
        let acceptedAt = now()
        let answerAndReview = resolved.answerWorkers + resolved.reviewWorkers
        var run = TeamRun(
            id: runId,
            prompt: prompt,
            status: .fanningOut,
            origin: origin,
            originAgent: request.originAgent,
            presetId: resolved.teamPresetId,
            workers: resolved.allWorkers,
            workerAnswers: answerAndReview.map { WorkerAnswer(workerId: $0.id, modelId: $0.modelId, status: .queued) },
            createdAt: acceptedAt,
            lane: resolvedRequest.lane,
            type: resolvedRequest.type,
            effort: resolvedRequest.effort,
            teamDisplayName: resolved.teamDisplayName,
            outputKind: resolved.outputKind,
            posture: resolved.posture,
            mutating: resolved.mutating,
            warnings: resolved.warnings,
            threadId: request.threadId,
            originConversationId: request.originConversationId,
            originMessageId: request.originMessageId
        )
        persist(run)

        if let key = request.idempotencyKey, !key.isEmpty {
            try? idempotency.record(key: key, payload: canonical, runId: runId, now: acceptedAt)
        }

        let store = runStore
        let allModels = models
        let lane = resolvedRequest.lane
        let type = resolvedRequest.type
        let effort = resolvedRequest.effort
        let teamName = resolved.teamDisplayName
        let outputKind = resolved.outputKind
        let warnings = resolved.warnings
        let posture = resolved.posture
        let mutating = resolved.mutating

        @Sendable func stamped(_ r: TeamRun) -> TeamRun {
            var copy = r
            copy.lane = lane; copy.type = type; copy.effort = effort
            copy.teamDisplayName = teamName; copy.outputKind = outputKind; copy.warnings = warnings
            copy.posture = posture; copy.mutating = mutating
            copy.threadId = request.threadId
            copy.originConversationId = request.originConversationId
            copy.originMessageId = request.originMessageId
            return copy
        }
        let cancelledRuns = cancelledRuns
        let persistDuringRun: @Sendable (TeamRun) -> Void = { incoming in
            cancelledRuns.saveIfActive(runId) {
                try? store.save(stamped(incoming), models: allModels)
            }
        }

        let coordinator = CatalogRunCoordinator(
            workerRunner: WorkerRunner(commandRunner: commandRunner, invocations: invocations),
            registry: registry,
            idFactory: idFactory,
            now: now
        )

        let task = Task {
            _ = await coordinator.run(
                resolved: resolved, prompt: prompt, models: models,
                origin: origin, originAgent: request.originAgent,
                runId: runId, persist: persistDuringRun
            )
            self.finishActiveRun(runId: runId, slot: slot)
        }
        activeRuns[runId] = ActiveRun(slot: slot, task: task)

        return .success(startResponse(for: run, acceptedAt: acceptedAt))
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
            active.task.cancel()
        }
        // Flip the cancelled flag and write the terminal state under the same lock
        // the progress saves use, re-loading inside so we cancel the freshest run.
        cancelledRuns.cancelAndSave(runId) {
            var run = self.runStore.load(runId: runId) ?? loaded
            run.status = .cancelled
            for i in run.workerAnswers.indices where !run.workerAnswers[i].status.isTerminal {
                run.workerAnswers[i].status = .cancelled
            }
            try? self.runStore.save(run, models: self.models)
        }
        return TeamCancelResponse(runId: runId, status: .cancelled, cancelledAt: now())
    }

    // MARK: - helpers

    private func finishActiveRun(runId: String, slot: TeamGovernor.Slot) {
        activeRuns.removeValue(forKey: runId)
        _ = slot
    }

    private func persist(_ run: TeamRun) {
        cancelledRuns.saveIfActive(run.id) {
            try? self.runStore.save(run, models: self.models)
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
        if case .failure(let failure) = TeamRequestResolver.resolve(
            teams: teams, lane: request.lane, teamId: request.teamPresetId,
            type: request.type, effort: request.effort) {
            return failure.code
        }
        if preflight.blockedReason?.contains("plan/output writer") == true { return "PLAN_WRITER_FAILED" }
        return "DEFAULT_TEAM_INVALID"
    }
}
