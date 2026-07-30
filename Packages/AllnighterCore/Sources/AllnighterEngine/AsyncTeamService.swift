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
///
/// CR-S06 deleted detached team-start execution (the flag it used never actually
/// shipped as CLI grammar; RSC-S05 swept the last phantom references), so there is
/// exactly one ownership mode left: the caller's own process. Reintroducing a
/// forked runner is new work with its own packet.
public enum AsyncTeamStartOwnership: Sendable {
    /// Coordinator + heartbeat run in this process.
    case inProcess
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
    public let runStore: RunStore
    private let commandRunner: CommandRunner
    private let governor: TeamGovernor
    private let idempotency: IdempotencyStore
    private let remoteEventJournal: RemoteRunEventJournal
    private let pmTurnStore: PMTurnStore
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
        // RLR-S04a: record the worker's OWN process group (pgid == pid, atomic at
        // posix_spawn SETPGROUP) instead of AgentOS SubprocessCommandRunner's racy
        // post-hoc `setpgid` that detached the worker into an UNRECORDED group. Same
        // env policy (`AllnighterSpawnEnvironmentPolicy`) so driver env composition
        // is preserved; the worker tree is now genuinely addressable + recorded.
        commandRunner: CommandRunner = ProcessGroupCommandRunner(
            environmentPolicy: AllnighterSpawnEnvironmentPolicy(), spawnKind: .devTurn),
        governor: TeamGovernor? = nil,
        idempotency: IdempotencyStore = IdempotencyStore(),
        remoteEventJournal: RemoteRunEventJournal? = nil,
        pmTurnStore: PMTurnStore? = nil,
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
        self.pmTurnStore = pmTurnStore ?? PMTurnStore(runsRootDirectory: runStore.rootDirectory)
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
        let flagMode: RunInvocationFlagMode = .foreground
        let readyIds = Set(readyModels.map(\.id))
        let invocation = RunInvocationResolver.resolve(
            RunInvocationInput(request: request, flagMode: flagMode),
            context: RunInvocationResolveContext(
                models: models,
                teams: teams,
                readyModels: readyModels,
                readyModelIds: readyIds
            )
        )
        guard invocation.canStart else {
            return .failure(.init(
                code: invocation.explicitModelChosen ? "CLI_USAGE_ERROR" : "DEFAULT_TEAM_INVALID",
                message: invocation.blockedReason ?? "team cannot start",
                preset: invocation.teamPresetId
            ))
        }

        // Normalize request to the resolved selectors so downstream mint/idempotency
        // see the same team/worker dry-run projected (SH-S01 — no re-resolution).
        var request = request
        request.teamPresetId = invocation.teamPresetId
        request.lane = invocation.lane
        request.effort = invocation.effort
        if let worker = invocation.pinnedModelId {
            request.modelId = worker
        }
        if request.repoRoot == nil || request.repoRoot?.isEmpty == true {
            request.repoRoot = invocation.projectRoot.isEmpty ? nil : invocation.projectRoot
        }

        let canonical = AsyncTeamCanonicalPayload(from: request)
        // Fast-path sequential replay (F5b claim below is the cross-process gate).
        if let key = request.idempotencyKey, !key.isEmpty,
           let replay = replayIfPresent(key: key, canonical: canonical) {
            return replay
        }

        if RecursionGuard.atOrOverCeiling(config.maxTeamRunDepth, environment: environment) {
            return .failure(.init(code: "NESTED_TEAM_BLOCKED", message: "already inside a team; nested teams are disabled"))
        }

        let resolvedRequest: TeamRequestResolver.Resolved
        switch TeamRequestResolver.resolve(
            teams: teams,
            lane: invocation.lane,
            teamId: invocation.teamPresetId,
            type: invocation.type,
            effort: invocation.effort
        ) {
        case .success(let req):
            resolvedRequest = req
        case .failure(let failure):
            return .failure(.init(
                code: failure.code,
                message: failure.description,
                preset: invocation.teamPresetId
            ))
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
            } else if !resolved.mutating, invocation.explicitModelChosen {
                // Answer-team pin (matches RunService.runAnswer / dry-run seats).
                let skillId = resolved.answerWorkers.first?.skillId ?? "first_principles_builder"
                let skillName = resolved.answerWorkers.first?.skillName
                // Same roster seat as before the pin — only the model changes.
                let agentId = resolved.answerWorkers.first?.agentId
                let pinned = Agent(
                    id: Agent.makeID(modelId: modelId, instanceIndex: 0),
                    modelId: modelId,
                    instanceIndex: 0,
                    skillId: skillId,
                    skillName: skillName,
                    purpose: .answer,
                    agentId: agentId
                )
                resolved.scoutWorker = nil
                resolved.answerWorkers = [pinned]
                resolved.reviewWorkers = []
                TeamSourceFacts.enrich(&resolved, models: models)
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
                resolvedRequest: resolvedRequest, resolved: resolved, canonical: canonical,
                readyModels: readyModels
            )
        }
    }

    private func startInProcess(
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        resolvedRequest: TeamRequestResolver.Resolved,
        resolved: ResolvedTeamRun,
        canonical: AsyncTeamCanonicalPayload,
        readyModels: [Model]
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

        // F5b: claim before mint so concurrent same-key callers single-flight.
        if let key = request.idempotencyKey, !key.isEmpty {
            switch claimIdempotency(key: key, canonical: canonical, runId: runId, at: acceptedAt) {
            case .failure(let refusal):
                // Drop the unused slot (deinit releases flock).
                _ = slot
                return .failure(refusal)
            case .success(.replay(let response)):
                _ = slot
                return .success(response)
            case .success(.proceed):
                break
            }
        }

        let run = mintRun(
            runId: runId, prompt: prompt, request: request, origin: origin,
            resolved: resolved, resolvedRequest: resolvedRequest, acceptedAt: acceptedAt,
            readyModels: readyModels
        )
        persist(run, endReasonIfTerminal: nil)

        launchInProcess(
            run: run, resolved: resolved, request: request, origin: origin,
            prompt: prompt, slot: slot
        )
        return .success(startResponse(for: run, acceptedAt: acceptedAt))
    }

    /// Detached path: truthful accept via runner_ready handshake (PO-S01 v2).
    /// Parent never prints accepted until the runner holds the governor slot.
    private func mintRun(
        runId: String,
        prompt: String,
        request: AsyncTeamStartRequest,
        origin: RunOrigin,
        resolved: ResolvedTeamRun,
        resolvedRequest: TeamRequestResolver.Resolved,
        acceptedAt: Date,
        readyModels: [Model]
    ) -> TeamRun {
        let answerAndReview = resolved.answerWorkers + resolved.reviewWorkers
        // RLR-L3: accept as `queued`/`spawningWorker`. The coordinator picks the
        // running state (single-worker `running` vs multi-worker `fanning_out`)
        // by fan-out crew size once the runner takes over.
        return TeamRun(
            id: runId,
            prompt: prompt,
            status: .queued,
            phase: .spawningWorker,
            origin: origin,
            originAgent: request.originAgent,
            presetId: resolved.teamPresetId,
            workers: resolved.allWorkers,
            answers: answerAndReview.map {
                TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? AgentStage.answer.rawValue,
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
            repoRoot: request.repoRoot,
            resolvedBenchModelIds: readyModels.map(\.id).sorted()
        )
    }

    // MARK: - Idempotency (F5b)

    private enum IdempotencyClaimAction: Equatable {
        case proceed
        case replay(TeamStartResponse)
    }

    /// Sequential fast path when the journal is already durable.
    private func replayIfPresent(
        key: String,
        canonical: AsyncTeamCanonicalPayload
    ) -> Result<TeamStartResponse, AsyncTeamStartRefusal>? {
        guard let existing = idempotency.lookup(key: key, now: now()) else { return nil }
        let digest = IdempotencyStore.digest(canonical)
        if existing.payloadDigest != digest {
            return .failure(.init(
                code: "IDEMPOTENCY_CONFLICT",
                message: "idempotency key was already used with a different payload"
            ))
        }
        if let run = runStore.loadRaw(runId: existing.runId) ?? runStore.load(runId: existing.runId) {
            return .success(startResponse(for: run, acceptedAt: existing.acceptedAt))
        }
        return nil
    }

    /// Atomic same-key claim before mint/spawn. Concurrent identical callers
    /// resolve to one run id; digest mismatch stays a typed refusal.
    private func claimIdempotency(
        key: String,
        canonical: AsyncTeamCanonicalPayload,
        runId: String,
        at acceptedAt: Date
    ) -> Result<IdempotencyClaimAction, AsyncTeamStartRefusal> {
        let result: IdempotencyStore.ClaimResult
        do {
            result = try idempotency.claim(
                key: key,
                payload: canonical,
                runId: runId,
                now: acceptedAt
            )
        } catch {
            return .failure(.init(code: "INTERNAL_ERROR", message: "idempotency claim failed: \(error)"))
        }
        switch result {
        case .claimed:
            return .success(.proceed)
        case .conflict:
            return .failure(.init(
                code: "IDEMPOTENCY_CONFLICT",
                message: "idempotency key was already used with a different payload"
            ))
        case .expired:
            return .failure(.init(
                code: "IDEMPOTENCY_EXPIRED",
                message: "idempotency key has expired (replay window \(Int(IdempotencyStore.retention))s); use a new key"
            ))
        case .replay(let entry):
            if let response = waitForIdempotentReplay(entry: entry) {
                return .success(.replay(response))
            }
            // Peer claimed then vanished — take over under a forced claim.
            do {
                let takeover = try idempotency.forceClaim(
                    key: key,
                    payload: canonical,
                    runId: runId,
                    now: acceptedAt,
                    runExists: { [runStore] id in
                        runStore.loadRaw(runId: id) != nil || runStore.load(runId: id) != nil
                    }
                )
                switch takeover {
                case .claimed:
                    return .success(.proceed)
                case .conflict:
                    return .failure(.init(
                        code: "IDEMPOTENCY_CONFLICT",
                        message: "idempotency key was already used with a different payload"
                    ))
                case .expired:
                    return .failure(.init(
                        code: "IDEMPOTENCY_EXPIRED",
                        message: "idempotency key has expired (replay window \(Int(IdempotencyStore.retention))s); use a new key"
                    ))
                case .replay(let again):
                    if let response = waitForIdempotentReplay(entry: again) {
                        return .success(.replay(response))
                    }
                    return .failure(.init(
                        code: "INTERNAL_ERROR",
                        message: "idempotency replay run never appeared: \(again.runId)"
                    ))
                }
            } catch {
                return .failure(.init(code: "INTERNAL_ERROR", message: "idempotency reclaim failed: \(error)"))
            }
        }
    }

    /// Peer may have claimed and still be persisting the journal — wait briefly.
    private func waitForIdempotentReplay(
        entry: IdempotencyStore.Entry,
        timeout: TimeInterval = 5.0
    ) -> TeamStartResponse? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let run = runStore.loadRaw(runId: entry.runId) ?? runStore.load(runId: entry.runId) {
                return startResponse(for: run, acceptedAt: entry.acceptedAt)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    private func removeRunDirectory(runId: String) {
        let directory = runStore.rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

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
        // RLR-S03a: one in-memory activity clock per run, shared by the persist
        // stamp (transition saves) and the event observer (streaming flush).
        let activityRecorder = RunActivityRecorder()
        let persistDuringRun: @Sendable (TeamRun) -> Void = { incoming in
            cancelledRuns.saveIfActive(runId) {
                // Stamp the latest durable activity onto this transition save so
                // child/exit activity rides the write for free (RLR-L6). Nil
                // before first post-spawn activity — spawn never advances it.
                var toSave = stamped(incoming)
                activityRecorder.stamp(&toSave)
                _ = try? store.save(toSave, models: allModels)
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

        // RLR-S03a: no per-tick heartbeat floor timer. Durable activity truth
        // lives on `run.json` (`lastActivityAt`), advanced ONLY by L6 events
        // observed below — never by a timer (the RLR-L6 inference ban).
        let task = Task {
            async let eventRecorder: Void = Self.recordRemoteEvents(
                coordinator.events, to: remoteEventJournal,
                store: store, recorder: activityRecorder, runId: runId
            )
            _ = await coordinator.run(
                resolved: resolved, prompt: prompt, models: models,
                origin: origin, originAgent: request.originAgent,
                runId: runId, repoRoot: request.repoRoot,
                runDirectory: try? store.runDirectory(forRunId: runId),
                persist: persistDuringRun
            )
            await eventRecorder
            activityRecorder.forget(runId: runId)
            self.finishActiveRun(runId: runId, slot: slot)
        }
        activeRuns[runId] = ActiveRun(slot: slot, task: task)
    }

    private nonisolated static func recordRemoteEvents(
        _ events: AsyncStream<RunEvent>,
        to journal: RemoteRunEventJournal,
        store: RunStore,
        recorder: RunActivityRecorder,
        runId: String
    ) async {
        for await event in events {
            do {
                _ = try journal.append(event)
            } catch {
                StreamDebugLog.log("REMOTE_EVENT_JOURNAL_APPEND_FAILED event=\(event.id) error=\(error)")
            }
            // RLR-S03a: project L6 activity onto the durable journal.
            RunActivityJournalProjection.observe(event, runId: runId, store: store, recorder: recorder)
        }
    }

    // MARK: - status / result / cancel / reconcile

    /// Explicit path: may reconcile (kill + terminal write) under per-run flock.
    public func status(runId: String) -> TeamStatusResponse? {
        _ = runStore.reconcileRun(runId: runId, models: models)
        guard let run = runStore.load(runId: runId) else { return nil }
        var response = AsyncTeamStatusMapper.statusResponse(for: run)
        let pmTurn = PMTurnStatusProjection.load(
            kind: .run,
            subjectId: run.id,
            atPMBoundary: run.status.isTerminal,
            store: pmTurnStore
        )
        response.pmTurn = pmTurn.pmTurn
        response.notes = pmTurn.notes
        response.pmTurnDelivery = pmTurn.pmTurnDelivery
        // RLR-S03a / RLR-L6: activity truth is `run.json.lastActivityAt`, not
        // `heartbeat.json` (retired). `progressStale` is a read-time derivation —
        // absent (nil) before the first post-spawn activity, and only meaningful
        // for a non-terminal run whose owner is still alive.
        response.lastProgressAt = run.lastActivityAt
        response.killOutcome = run.killOutcome?.rawValue
        if let directory = try? runStore.runDirectory(forRunId: runId) {
            let workerOwners = ProcessOwnership.readWorkerOwners(inRunDirectory: directory)
            let anyWorkerAlive = workerOwners.contains { ProcessOwnership.isIdentityAlive($0.identity) }
            let coord = ProcessOwnership.readOwnerIdentity(in: directory)
            let coordAlive = coord.map { ProcessOwnership.isIdentityAlive($0) } ?? false
            let coordPG = coord.map { $0.kind.isProcessGroupKillable } ?? false
            response.contradiction = RunContradictionSurface.contradiction(
                isTerminal: run.status.isTerminal,
                anyWorkerIdentityAlive: anyWorkerAlive,
                coordinatorIdentityAlive: coordAlive,
                coordinatorIsProcessGroupKillable: coordPG
            )?.rawValue
        }
        if !run.status.isTerminal && run.phase != .waitingForVendor {
            let ownerAlive: Bool
            if let directory = try? runStore.runDirectory(forRunId: runId) {
                ownerAlive = !ProcessOwnership.isOwnerIdentityDead(in: directory)
            } else {
                ownerAlive = true
            }
            if ownerAlive {
                response.progressStale = RunActivity.progressStale(
                    lastActivityAt: run.lastActivityAt, now: now()
                )
                let stallSummary: String? = {
                    guard let directory = try? runStore.runDirectory(forRunId: runId) else { return nil }
                    if let persisted = ProcessOwnership.readStallDiagnosis(in: directory)?.summary {
                        return persisted
                    }
                    if let identity = ProcessOwnership.readOwnerIdentity(in: directory),
                       ProcessOwnership.isIdentityAlive(identity) {
                        return ProcessOwnership.diagnoseOwnedTreeStall(identity: identity)?.summary
                    }
                    return nil
                }()
                response.silenceStatus = OwnershipSilencePresentation.silenceStatusLine(
                    identityAlive: true,
                    lastProgressAt: run.lastActivityAt,
                    now: now(),
                    stallSummary: stallSummary
                )
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
                matched.nextAction = AsyncTeamStatusMapper.nextAction(for: response)
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
    /// An exact run id stays an explicit cross-project target; the bare sweep
    /// is scoped to the caller's canonical project root (`scopeRoot`) — pass
    /// nil only for the explicit machine-wide fleet sweep.
    public func reconcile(runId: String?, scopeRoot: String? = nil) -> [TeamRun] {
        // The one path allowed to act on a cancel lie (terminal journal + still
        // identity-alive tree). Read paths — `ps`, `status`, `result` — reconcile
        // through the same store with recovery OFF and never signal.
        if let runId {
            if let detail = runStore.reconcileRunDetailed(
                runId: runId, models: models, recoverTerminalLiveOwnership: true
            ), detail.reaped {
                return [detail.run]
            }
            return []
        }
        return runStore.reconcileAll(
            models: models, scopeRoot: scopeRoot, recoverTerminalLiveOwnership: true)
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

        // Always drop the cooperative task if this process owns it. That is NOT
        // a verified process-tree stop — detached workers / --no-wait trees must
        // still pass KillSettlement (or force terminate on recovery).
        let inProcess = activeRuns.removeValue(forKey: runId)
        inProcess?.task.cancel()
        let directory = try? runStore.runDirectory(forRunId: runId)
        let models = self.models
        let runStore = self.runStore

        // Recovery: journal already says cancelled/killed but ownership is still
        // identity-alive (the cancel lie). Force-kill recorded trees; do not early-
        // return "cancelled" while processes keep spending.
        if loaded.status.isTerminal {
            if let directory, ProcessOwnership.anyRecordedMemberIdentityAlive(in: directory) {
                ProcessOwnership.withRunLock(in: directory) {
                    _ = ProcessOwnership.forceTerminateAllRecorded(in: directory)
                    if var run = runStore.loadRaw(runId: runId) {
                        // Prefer stopped only when the tree is actually dead.
                        if !ProcessOwnership.anyRecordedMemberIdentityAlive(in: directory) {
                            run.killOutcome = .stopped
                        } else {
                            run.killOutcome = .partial
                        }
                        _ = try? runStore.save(run, models: models)
                    }
                }
            }
            let after = runStore.loadRaw(runId: runId) ?? loaded
            return TeamCancelResponse(
                runId: runId,
                status: AsyncTeamStatusMapper.liveStatus(for: after),
                cancelledAt: now())
        }

        cancelledRuns.cancelAndSave(runId) {
            ProcessOwnership.withRunLock(in: directory ?? runStore.rootDirectory) {
                var run = runStore.loadRaw(runId: runId) ?? loaded
                // Never clobber an existing terminal status.
                guard !run.status.isTerminal else { return }

                // RLR-S04b: always settle the recorded process tree when a run
                // directory exists. Task.cancel alone is not a verified stop —
                // that lie produced END=cancelled + ALIVE=yes + WOULD_REAP=no.
                var outcome: KillOutcome
                if let directory {
                    var settlement = KillSettlement.settle(
                        runDirectory: directory, mode: .cancel, run: run)
                    // Operator cancel must stop spend. If TERM-only leave survivors,
                    // escalate to full TERM→SIGKILL on every recorded member and
                    // re-check identity-alive (still never invent pids).
                    if settlement.outcome == .partial {
                        _ = ProcessOwnership.forceTerminateAllRecorded(in: directory)
                        if !ProcessOwnership.anyRecordedMemberIdentityAlive(in: directory) {
                            settlement = KillSettlement.Result(
                                outcome: .stopped,
                                survivors: [],
                                cleanupWarning: false,
                                signalled: true)
                        }
                    }
                    outcome = settlement.outcome
                } else if inProcess != nil {
                    // No durable directory (should be rare) — cooperative only.
                    outcome = .stopped
                } else {
                    outcome = .verificationUnavailable
                }
                run.killOutcome = outcome
                guard outcome == .stopped else {
                    _ = try? runStore.save(run, models: models)
                    return
                }
                run.status = .cancelled
                run.endReason = .cancelled
                for i in run.answers.indices where !run.answers[i].result.status.isTerminal {
                    run.answers[i].result.status = .cancelled
                }
                // RLR-L3: the terminal revision clears the blocker and withdraws any
                // FIFO ticket atomically (mirrors `killRun`), gated on `.stopped`.
                let wasBlocked = run.blocker != nil
                run.blocker = nil
                if wasBlocked {
                    ExecutionLaneFlock.withdrawWaiter(
                        laneKey: ExecutionLane.key(repoRoot: run.repoRoot), claimId: run.id)
                }
                _ = try? runStore.save(run, models: models)
            }
        }
        let after = runStore.loadRaw(runId: runId) ?? loaded
        return TeamCancelResponse(
            runId: runId,
            status: AsyncTeamStatusMapper.liveStatus(for: after),
            cancelledAt: now())
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
        activeRuns.removeValue(forKey: runId)
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
                .waitForTerminal(runId: run.id),
                .init(
                    kind: "result",
                    label: "Fetch result when terminal",
                    command: "alln team result \(run.id) --json",
                    runId: run.id),
            ]
        )
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
        // Only modelId/id/substitutedFromModelId are rewritten here — `worker`
        // is a copy of the already-resolved seat, so `agentId` (the roster row
        // this seat came from) survives untouched (WTA-S01a).
        worker.substitutedFromModelId = worker.modelId
        worker.modelId = modelId
        worker.id = Agent.makeID(modelId: modelId, instanceIndex: worker.instanceIndex)
        pinned.answerWorkers[0] = worker
        TeamSourceFacts.enrich(&pinned, models: readyModels)
        return pinned
    }
}
