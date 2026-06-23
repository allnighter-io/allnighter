import Foundation
import AllnighterCore

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
    /// (default `execution_playbook`). Read by `FollowUpCoordinator`, which owns the chain — a
    /// plain `RunService.run` ignores it. Whether to run the chain at all is the caller's
    /// decision (the CLI `--try-fix` flag), not a field here.
    public var executorTeamId: String?

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
        executorTeamId: String? = nil
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
        case .writeLockBusy(let r): return "an agent is still editing this repo after a long wait — it looks stuck; stop it and retry (\(r))"
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
    // Auto (Default model) inputs — injectable so resolution is deterministic in tests.
    private let loadDefaultSettings: @Sendable () -> DefaultModelSettings
    private let loadProbeRecords: @Sendable () -> [ToolProbeRecord]
    /// Worker_Session_Continuity: the durable per-(thread, source, model) vendor session map.
    private let sessionStore: ExternalWorkerSessionStore
    /// Warm_Single_Lane_Chat: process-global warm-worker registry (default = shared singleton so
    /// warmth survives the per-turn RunService instances; tests inject a fresh pool).
    private let warmPool: WarmWorkerPool

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
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        writeLock: RunWriteLockRegistry = .shared,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init,
        defaultSettings: @escaping @Sendable () -> DefaultModelSettings = { DefaultModelSettingsPersistence().load() },
        probeRecords: @escaping @Sendable () -> [ToolProbeRecord] = { SetupStore().load().records },
        sessionStore: ExternalWorkerSessionStore = ExternalWorkerSessionStore(),
        warmPool: WarmWorkerPool = .shared
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
    }

    private func readyModels() -> [Model] { models.filter(\.enabled) }

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

    /// Model ids that are a runnable substitute *right now*: ON the Bench AND their
    /// source CLI is installed + probe-ready. Mirrors the readiness the `defaults` /
    /// `models` projections show, so Auto's "→ Opus 4.8" preview equals what actually
    /// runs and a down CLI is genuinely routed around (source-health, not just enabled).
    private func sourceReadyModelIds() -> Set<ModelID> {
        let records = Dictionary(
            loadProbeRecords().map { ($0.driverId, $0) }, uniquingKeysWith: { a, _ in a })
        let manifestIDs = Set(registry.all.map(\.id))
        // A source that just hit a capacity wall is treated as NOT ready until it resets, so
        // Auto/team resolution substitutes around it pre-dispatch — no run-path retry. The
        // CLI can probe "green" yet be tapped out; capacity truth comes from prior runs.
        let cooling = coolingSources()
        return Set(models.filter { m in
            m.enabled && manifestIDs.contains(m.driverId)
                && (records[m.driverId]?.status.isReady ?? false)
                && !cooling.contains(m.driverId)
        }.map(\.id))
    }

    /// How far back to look for capacity observations — bounds the run-history scan; the
    /// `coolingUntil > now` filter is what actually expires a cooldown.
    private static let capacityLookbackSeconds: TimeInterval = 12 * 60 * 60

    /// Sources cooling down right now (a recent rate-limit / cooldown that hasn't reset),
    /// derived from prior runs' failed worker answers. Routed around pre-dispatch.
    func coolingSources(now: Date = Date()) -> Set<String> {
        SourceCapacityLedger.coolingSources(observations: recentCapacityObservations(now: now), now: now)
    }

    private func recentCapacityObservations(now: Date) -> [CapacityObservation] {
        let lookback = now.addingTimeInterval(-Self.capacityLookbackSeconds)
        return runStore.list()
            .filter { $0.createdAt >= lookback }
            .flatMap { $0.failedWorkerAnswers }
            .compactMap { $0.capacityObservation }
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

        // Queue-wait clock: stamp BEFORE the write-lock acquire (the real blocking wait) and
        // resolution/staging, so `queueMs = worker.startedAt − requestedAt` captures all of it.
        let requestedAt = now()
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

        // Auto (the no-pick / default route): resolve the worker model from the
        // Default-model tiers instead of the team's static preference — using the tier
        // default, or the first source-ready substitute on the same tier when it's down
        // (route around a down CLI, no prompt). A blocked tier fails clean ("Auto
        // waits"), never guesses. An explicit per-chat model pick (workerId) wins.
        var effectiveWorkerId = request.workerId
        if preset.id == TeamCatalog.defaultRunTeam()?.id, (request.workerId ?? "").isEmpty {
            let settings = loadDefaultSettings()
            let auto = SubstitutionResolver.resolveAuto(
                settings: settings, readyModelIds: sourceReadyModelIds())
            guard let modelId = auto.resolvedModelId else {
                return .failure(.teamResolution(
                    "Auto waits — no ready model on the \(settings.defaultTier.displayName) tier",
                    code: "DEFAULT_TEAM_INVALID"))
            }
            effectiveWorkerId = modelId
        }

        var prompt = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let starter = preset.starterPrompts.first, !starter.isEmpty, preset.mutating {
            prompt = starter + "\n\n" + prompt
        }
        // NOTE: thread context is appended below per-path. The execution path appends it
        // CONDITIONALLY (Worker_Session_Continuity: when resuming a live vendor session the
        // CLI already holds the history, so we don't re-dump it); the answer path always does.

        let effort = request.effort ?? preset.defaultEffort
        let lockKey = RunWriteLock.key(repoRoot: root)
        var acquiredLock = false
        if preset.writePolicy == .mutating {
            // One writer per repo root. If another mutating run holds the lock, WAIT our turn
            // (FIFO) and then run — a second back-to-back agent turn queues behind the first
            // instead of erroring. The bounded timeout is the safety valve: if a wedged holder
            // outlives even its own worker timeout/watchdog, we stop queueing forever and refuse
            // honestly (RUN_WRITE_LOCK_BUSY, retryable). Read-only runs never reach here.
            guard await writeLock.waitToAcquire(lockKey, timeout: Self.writeLockWaitTimeout) else {
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
                preset: preset, prompt: prompt, context: request.context, threadId: request.threadId,
                effort: effort, repoRoot: root,
                projectId: request.projectId, workerOverride: effectiveWorkerId,
                origin: origin, originAgent: originAgent, runId: id, runner: runner,
                deliveries: request.deliveries, requestedAt: requestedAt, events: events
            )
        }

        // Answer (team) path: no vendor-session continuity — always include the context inline.
        var answerPrompt = prompt
        if let context = request.context, !context.isEmpty {
            answerPrompt += "\n\n# Context\n\(context)"
        }
        return await runAnswer(
            preset: preset, prompt: answerPrompt, effort: effort, repoRoot: root,
            projectId: request.projectId, lane: request.lane ?? preset.lane,
            origin: origin, originAgent: originAgent, runId: id, runner: runner,
            deliveries: request.deliveries, events: events
        )
    }

    // MARK: - Execution (one worker, mutating)

    private func runExecution(
        preset: TeamPreset,
        prompt: String,
        context: String? = nil,
        threadId: String? = nil,
        effort: EffortLevel,
        repoRoot: String,
        projectId: String?,
        workerOverride: String?,
        origin: RunOrigin,
        originAgent: String?,
        runId: String,
        runner: WorkerRunner,
        deliveries: [IncludedAttachmentDelivery] = [],
        requestedAt: Date? = nil,
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

        // Worker_Session_Continuity: resume THIS thread's vendor session for (source, model)
        // if one's alive; on a first turn / model switch, mint or capture a fresh one.
        let sessionKey: ExternalWorkerSession.Key? = threadId.map {
            .init(threadId: $0, sourceId: manifest.id, modelId: model.id, repoRoot: repoRoot)
        }
        let resumable = sessionKey.flatMap { sessionStore.resumable($0) }
        let sessionPlan: WorkerSessionPlan? = {
            guard sessionKey != nil, let session = manifest.session,
                  session.continuity == .vendorSession else { return nil }
            if let resumable {
                return WorkerSessionPlan(session: session, resumeSessionId: resumable.vendorSessionId, mintSessionId: nil)
            }
            let mint = session.acquire == .set ? UUID().uuidString.lowercased() : nil
            return WorkerSessionPlan(session: session, resumeSessionId: nil, mintSessionId: mint)
        }()

        // Founder rule: only seed the thread context when we are NOT resuming a live vendor
        // session (the CLI already remembers it). First turn / model switch → include it.
        let founderPrompt: String
        if resumable != nil {
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
        let assembled = deliveries.isEmpty ? baseAssembled
            : TeamRunAttachmentMapper.teamRunSeatPrompt(
                basePrompt: baseAssembled,
                deliveries: deliveries,
                readsImages: manifest.canReadImages)
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
            // The run's source is where the worker ACTUALLY ran — the chosen model's
            // driver. For the default route, Auto/override can pick a model on a CLI
            // other than the preset's declared executionSourceId, so the model's driver
            // is the truth (lane safety keys on repo root, not this field).
            mutating: true, executionSourceId: model.driverId
        )
        try? runStore.save(run, models: models)

        // Stream the single execution worker live when it can: emit accumulated
        // visible answer (`workerAnswerDelta`) AND reasoning (`workerReasoningDelta`)
        // on a time cadence so even short replies visibly stream. If streaming yields
        // nothing usable, FALL BACK to the proven one-shot invoke so the worker always
        // answers.
        var outcome: WorkerRunOutcome
        // Warm_Single_Lane_Chat §5 S4: warm-capable sources (grok, cursor_agent) run as ONE persistent
        // ACP worker per thread — the repo index loads once, then every turn is model-time only.
        if WarmWorkerCapability.supportsACPStdio(manifest.id),
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
                        if firstTokenAt == nil { firstTokenAt = now() }
                        let due = answer.append(text)
                        if due || now().timeIntervalSince(lastAnswerEmit) >= 0.1 { emitWarmAnswer() }
                    case .reasoningDelta(let text):
                        reasoning += text; emitWarmReasoning()
                    case .toolActivity:
                        break
                    }
                }
                emitWarmAnswer(); if !reasoning.isEmpty { emitWarmReasoning() }
                let text = answer.visibleText
                var warmOutcome = WorkerRunOutcome(
                    status: text.isEmpty ? .failed : .done, startedAt: startedAt, finishedAt: now())
                warmOutcome.output = text.isEmpty ? nil : text
                if text.isEmpty { warmOutcome.errorKind = .emptyOutput; warmOutcome.errorReason = "warm worker returned no text" }
                warmOutcome.durationMs = Int(now().timeIntervalSince(startedAt) * 1000)
                if let firstTokenAt {
                    warmOutcome.firstTokenAt = firstTokenAt
                    warmOutcome.ttftMs = Int(firstTokenAt.timeIntervalSince(startedAt) * 1000)
                }
                // Capture the vendor session id the warm driver established, so a later turn can
                // durably resume after the warm worker dies (and so Codex image harvest can map
                // the run to its rollout). The warm worker persists in-memory continuity already;
                // this is the durable record.
                warmOutcome.capturedSessionId = await warm.vendorSessionId()
                outcome = warmOutcome
            } catch {
                StreamDebugLog.log("WARM FALLBACK source=\(manifest.id): \(error) — cold invoke")
                outcome = await runner.invoke(
                    worker: model, manifest: manifest, prompt: assembled, effort: effort,
                    workingDirectoryOverride: repoRoot)
            }
        } else if manifest.canStream, runner.supportsStreaming,
           let parser = WorkerStreamParsers.make(for: manifest) {
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
                for try await streamEvent in runner.invokeStreaming(
                    worker: model, manifest: manifest, prompt: assembled, parser: parser,
                    effort: effort, workingDirectoryOverride: repoRoot, sessionPlan: sessionPlan
                ) {
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
            // Robustness: if streaming produced no usable answer, retry non-streaming.
            if outcome.status != .done, (outcome.output ?? "").isEmpty {
                StreamDebugLog.log("FALLBACK source=\(manifest.id): streaming gave \(outcome.status.rawValue)/empty — retrying invoke")
                outcome = await runner.invoke(
                    worker: model, manifest: manifest, prompt: assembled, effort: effort,
                    workingDirectoryOverride: repoRoot)
            }
        } else {
            outcome = await runner.invoke(
                worker: model, manifest: manifest, prompt: assembled, effort: effort,
                workingDirectoryOverride: repoRoot
            )
        }
        // A non-streaming worker (agy) can carry its step narration separated from the answer
        // (AGY transcript normalizer). It has no live deltas, so surface it once as a reasoning
        // delta — the turn then shows a clean answer + a "Thought for Ns" bar with the steps.
        if let reasoning = outcome.reasoning, !reasoning.isEmpty {
            emit(RunEventKind.workerReasoningDelta, [
                "runId": .string(runId), "workerId": .string(worker.id), "text": .string(reasoning)])
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
            guard let requestedAt, let startedAt = outcome.startedAt else { return nil }
            return max(0, Int(startedAt.timeIntervalSince(requestedAt) * 1000))
        }()
        let answer = WorkerAnswer(
            workerId: worker.id, modelId: model.id, status: outcome.status, output: outcome.output,
            errorKind: outcome.errorKind, errorReason: outcome.errorReason,
            startedAt: outcome.startedAt, finishedAt: outcome.finishedAt,
            durationMs: outcome.durationMs, queueMs: queueMs, ttftMs: outcome.ttftMs,
            gateWaitMs: outcome.gateWaitMs,
            exitCode: outcome.exitCode,
            vendorSessionId: outcome.capturedSessionId
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
        deliveries: [IncludedAttachmentDelivery] = [],
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
            origin: origin, originAgent: originAgent, runId: runId,
            repoRoot: repoRoot, deliveries: deliveries, persist: persist
        )
        await forwarder?.value
        run = stamped(run)
        return .success(run)
    }
}
