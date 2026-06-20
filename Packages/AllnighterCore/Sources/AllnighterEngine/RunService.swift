import Foundation
import AllnighterCore

/// One run request — message + optional preset + worker, against a repo root.
public struct RunRequest: Sendable, Equatable {
    public var message: String
    /// Canonical normalized repo root (cwd for every worker). Required.
    public var repoRoot: String
    public var projectId: String?
    public var presetId: String?
    /// Override the resolved worker (model id) for execution / default chat.
    public var workerId: String?
    public var effort: EffortLevel?
    /// Lane hint when resolving an answer team without an explicit preset.
    public var lane: WorkLane?
    public var type: String?
    public var context: String?

    public init(
        message: String,
        repoRoot: String,
        projectId: String? = nil,
        presetId: String? = nil,
        workerId: String? = nil,
        effort: EffortLevel? = nil,
        lane: WorkLane? = nil,
        type: String? = nil,
        context: String? = nil
    ) {
        self.message = message
        self.repoRoot = repoRoot
        self.projectId = projectId
        self.presetId = presetId
        self.workerId = workerId
        self.effort = effort
        self.lane = lane
        self.type = type
        self.context = context
    }
}

public enum RunServiceError: Error, Equatable, CustomStringConvertible {
    case repoRootUnavailable(String)
    case writeLockBusy(String)
    case teamResolution(String, code: String)
    case noWorker(String)

    public var description: String {
        switch self {
        case .repoRootUnavailable(let r): return "repo root unavailable: \(r)"
        case .writeLockBusy(let r): return "an agent is already editing this repo — wait or stop it (\(r))"
        case .teamResolution(let m, _): return m
        case .noWorker(let m): return m
        }
    }

    public var code: String {
        switch self {
        case .repoRootUnavailable: return "NO_PROJECT_ROOT"
        case .writeLockBusy: return "RUN_WRITE_LOCK_BUSY"
        case .teamResolution(_, let code): return code
        case .noWorker: return "WORKER_NOT_READY"
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

    public init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset] = TeamCatalog.all,
        runStore: RunStore = RunStore(),
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        writeLock: RunWriteLockRegistry = .shared,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.runStore = runStore
        self.commandRunner = commandRunner
        self.writeLock = writeLock
        self.invocations = invocations
        self.now = now
    }

    private func readyModels() -> [Model] { models.filter(\.enabled) }

    /// Run and persist. Returns the settled `TeamRun` (RunRecord substrate).
    public func run(
        _ request: RunRequest,
        origin: RunOrigin,
        originAgent: String? = nil,
        runId: String? = nil,
        events: AsyncStream<RunEvent>.Continuation? = nil
    ) async -> Result<TeamRun, RunServiceError> {
        defer { events?.finish() }

        let root = RunWriteLock.normalize(request.repoRoot) ?? request.repoRoot
        guard RootNormalization.observeRootState(key: root) == .available else {
            return .failure(.repoRootUnavailable(root))
        }

        let preset: TeamPreset
        if let presetId = request.presetId, !presetId.isEmpty {
            guard let team = teams.first(where: { $0.id == presetId }) ?? TeamCatalog.get(presetId) else {
                return .failure(.teamResolution("unknown team: \(presetId)", code: "TEAM_NOT_FOUND"))
            }
            preset = team
        } else {
            guard let team = TeamCatalog.defaultRunTeam() else {
                return .failure(.teamResolution("no default team configured", code: "DEFAULT_TEAM_INVALID"))
            }
            preset = team
        }

        var prompt = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let starter = preset.starterPrompts.first, !starter.isEmpty, preset.mutating {
            prompt = starter + "\n\n" + prompt
        }
        if let context = request.context, !context.isEmpty {
            prompt += "\n\n# Context\n\(context)"
        }

        let effort = request.effort ?? preset.defaultEffort
        let lockKey = RunWriteLock.key(repoRoot: root)
        var acquiredLock = false
        if preset.writePolicy == .mutating {
            guard await writeLock.acquire(lockKey) else {
                return .failure(.writeLockBusy(root))
            }
            acquiredLock = true
        }
        defer {
            if acquiredLock { Task { await writeLock.release(lockKey) } }
        }

        let runner = WorkerRunner(
            commandRunner: commandRunner, invocations: invocations, defaultWorkingDirectory: root
        )
        let id = runId ?? UUID().uuidString

        if preset.runShape == .execution {
            return await runExecution(
                preset: preset, prompt: prompt, effort: effort, repoRoot: root,
                projectId: request.projectId, workerOverride: request.workerId,
                origin: origin, originAgent: originAgent, runId: id, runner: runner, events: events
            )
        }

        return await runAnswer(
            preset: preset, prompt: prompt, effort: effort, repoRoot: root,
            projectId: request.projectId, lane: request.lane ?? preset.lane,
            origin: origin, originAgent: originAgent, runId: id, runner: runner, events: events
        )
    }

    // MARK: - Execution (one worker, mutating)

    private func runExecution(
        preset: TeamPreset,
        prompt: String,
        effort: EffortLevel,
        repoRoot: String,
        projectId: String?,
        workerOverride: String?,
        origin: RunOrigin,
        originAgent: String?,
        runId: String,
        runner: WorkerRunner,
        events: AsyncStream<RunEvent>.Continuation?
    ) async -> Result<TeamRun, RunServiceError> {
        var seq: Int64 = 0
        func emit(_ kind: String, _ payload: [String: JSONValue]) {
            seq += 1
            events?.yield(RunEvent(id: UUID().uuidString, seq: seq, ts: now(), kind: kind, payload: payload))
        }

        let bench = readyModels()
        let resolved = TeamResolver.resolve(
            team: preset, requestLane: preset.lane, requestEffort: effort, readyModels: bench
        )
        guard resolved.isRunnable else {
            return .failure(.teamResolution(resolved.blockReason ?? "team cannot run", code: "DEFAULT_TEAM_INVALID"))
        }

        let worker: Worker
        let model: Model
        if let override = workerOverride, let m = bench.first(where: { $0.id == override }) {
            guard let manifest = registry.manifest(for: m), manifest.kind == .headlessCLI else {
                return .failure(.noWorker("worker \(override) is not a runnable CLI"))
            }
            worker = Worker(
                id: Worker.makeID(modelId: m.id, instanceIndex: 0),
                modelId: m.id,
                instanceIndex: 0,
                skillId: resolved.answerWorkers.first?.skillId ?? "first_principles_builder",
                purpose: .answer
            )
            model = m
        } else if let first = resolved.answerWorkers.first,
                  let m = bench.first(where: { $0.id == first.modelId }) {
            worker = first
            model = m
        } else {
            return .failure(.noWorker("no ready worker for execution team"))
        }

        guard let manifest = registry.manifest(for: model) else {
            return .failure(.noWorker("no driver manifest for \(model.driverId)"))
        }

        let skillId = worker.skillId
        let assembled = SkillCatalog.assemblePrompt(skillId: skillId, founderPrompt: prompt)
        let startedAt = now()
        emit(RunEventKind.runStatusChanged, [
            "runId": .string(runId), "from": .string(RunStatus.draft.rawValue),
            "to": .string(RunStatus.fanningOut.rawValue), "origin": .string(origin.rawValue),
            "presetId": .string(preset.id)
        ])
        var startedPayload: [String: JSONValue] = [
            "runId": .string(runId), "workerId": .string(worker.id), "modelId": .string(model.id),
            "from": .string(WorkerAnswerStatus.queued.rawValue), "to": .string(WorkerAnswerStatus.running.rawValue)
        ]
        if let skillId { startedPayload["skillId"] = .string(skillId) }
        emit(RunEventKind.workerStatusChanged, startedPayload)
        var run = TeamRun(
            id: runId, prompt: prompt, status: .fanningOut, origin: origin, originAgent: originAgent,
            presetId: preset.id, workers: [worker],
            workerAnswers: [WorkerAnswer(workerId: worker.id, modelId: model.id, status: .running)],
            createdAt: startedAt, lane: preset.lane, effort: effort,
            teamDisplayName: preset.displayName, outputKind: preset.outputKind,
            mutating: true, executionSourceId: preset.executionSourceId ?? model.driverId
        )
        try? runStore.save(run, models: models)

        // Stream the single execution worker live when it can: emit the accumulated
        // visible answer as `workerAnswerDelta` events so the timeline updates before
        // the process exits. Otherwise the one-shot invoke. Same terminal outcome.
        let outcome: WorkerRunOutcome
        if manifest.canStream, runner.supportsStreaming,
           let parser = WorkerStreamParsers.make(for: manifest) {
            var buffer = StreamingPartialBuffer()
            var terminal: WorkerRunOutcome?
            do {
                for try await streamEvent in runner.invokeStreaming(
                    worker: model, manifest: manifest, prompt: assembled, parser: parser,
                    effort: effort, workingDirectoryOverride: repoRoot
                ) {
                    switch streamEvent {
                    case .answerDelta(let text, _, _):
                        if buffer.append(text) {
                            emit(RunEventKind.workerAnswerDelta, [
                                "runId": .string(runId), "workerId": .string(worker.id),
                                "text": .string(buffer.visibleText),
                                "truncated": .bool(buffer.isTruncated),
                            ])
                        }
                    case .completed(let o), .failed(let o):
                        terminal = o
                    case .started, .rawEvent, .toolActivity:
                        break
                    }
                }
            } catch { /* terminal handled below */ }
            // Flush the final accumulated text before settlement.
            emit(RunEventKind.workerAnswerDelta, [
                "runId": .string(runId), "workerId": .string(worker.id),
                "text": .string(buffer.visibleText), "truncated": .bool(buffer.isTruncated),
            ])
            outcome = terminal ?? WorkerRunOutcome(
                status: .failed, errorKind: .emptyOutput,
                errorReason: "stream ended without a terminal event")
        } else {
            outcome = await runner.invoke(
                worker: model, manifest: manifest, prompt: assembled, effort: effort,
                workingDirectoryOverride: repoRoot
            )
        }
        let answer = WorkerAnswer(
            workerId: worker.id, modelId: model.id, status: outcome.status, output: outcome.output,
            errorKind: outcome.errorKind, errorReason: outcome.errorReason,
            startedAt: outcome.startedAt, finishedAt: outcome.finishedAt,
            durationMs: outcome.durationMs, exitCode: outcome.exitCode
        )
        var workerPayload: [String: JSONValue] = [
            "runId": .string(runId), "workerId": .string(worker.id), "modelId": .string(model.id),
            "from": .string(WorkerAnswerStatus.running.rawValue), "to": .string(answer.status.rawValue)
        ]
        if let durationMs = answer.durationMs { workerPayload["durationMs"] = .int(durationMs) }
        if let reason = answer.errorReason { workerPayload["reason"] = .string(reason) }
        emit(RunEventKind.workerStatusChanged, workerPayload)
        run.workerAnswers = [answer]
        run.status = answer.status == .done ? .complete : .failed
        if answer.status == .done, let text = answer.output {
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
            "runId": .string(runId), "from": .string(RunStatus.fanningOut.rawValue),
            "to": .string(run.status.rawValue), "origin": .string(origin.rawValue),
            "presetId": .string(preset.id)
        ])
        try? runStore.save(run, models: models)
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
        origin: RunOrigin,
        originAgent: String?,
        runId: String,
        runner: WorkerRunner,
        events: AsyncStream<RunEvent>.Continuation?
    ) async -> Result<TeamRun, RunServiceError> {
        let bench = readyModels()
        let resolved = TeamResolver.resolve(
            team: preset, requestLane: lane, requestEffort: effort, readyModels: bench
        )
        guard resolved.isRunnable else {
            return .failure(.teamResolution(resolved.blockReason ?? "team cannot run", code: "DEFAULT_TEAM_INVALID"))
        }

        let store = runStore
        let allModels = models
        let coordinator = CatalogRunCoordinator(workerRunner: runner, registry: registry)
        let forwarder: Task<Void, Never>? = events.map { sink in
            Task { for await event in coordinator.events { sink.yield(event) } }
        }
        @Sendable func stamped(_ run: TeamRun) -> TeamRun {
            var r = run
            r.lane = lane; r.effort = effort
            r.teamDisplayName = resolved.teamDisplayName; r.outputKind = resolved.outputKind
            r.warnings = resolved.warnings; r.mutating = false
            return r
        }
        let persist: @Sendable (TeamRun) -> Void = { try? store.save(stamped($0), models: allModels) }

        var run = await coordinator.run(
            resolved: resolved, prompt: prompt, models: models,
            origin: origin, originAgent: originAgent, runId: runId, persist: persist
        )
        await forwarder?.value
        run = stamped(run)
        return .success(run)
    }
}
