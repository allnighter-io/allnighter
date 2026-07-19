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
        // Fast-path sequential replay (F5b claim below is the cross-process gate).
        if let key = request.idempotencyKey, !key.isEmpty,
           let replay = replayIfPresent(key: key, canonical: canonical) {
            return replay
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
            resolved: resolved, resolvedRequest: resolvedRequest, acceptedAt: acceptedAt
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

        // F5b: claim before staging so concurrent same-key starts share one runner.
        if let key = request.idempotencyKey, !key.isEmpty {
            switch claimIdempotency(key: key, canonical: canonical, runId: runId, at: stagedAt) {
            case .failure(let refusal):
                return .failure(refusal)
            case .success(.replay(let response)):
                return .success(response)
            case .success(.proceed):
                break
            }
        }

        let run = mintRun(
            runId: runId, prompt: prompt, request: request, origin: origin,
            resolved: resolved, resolvedRequest: resolvedRequest, acceptedAt: stagedAt
        )

        // Stage journal + request BEFORE spawn so the runner can claim them.
        // Not yet "accepted" to the caller — only after runner_ready.
        persist(run, endReasonIfTerminal: nil)

        // F2 staging lease: until the runner claims ownership (or this lease
        // expires), reconcile must never reap this run — the ownership handoff
        // is in flight and the staged owner record is only the launcher's.
        let stagedDirectory = runStore.rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        try? ProcessOwnership.writeStageLease(
            ProcessOwnership.StageLease(
                runId: runId, stagedAt: stagedAt,
                expiresAt: stagedAt.addingTimeInterval(ProcessOwnership.stageLeaseSeconds)
            ),
            in: stagedDirectory
        )

        let directory: URL
        do {
            directory = try runStore.runDirectory(forRunId: runId)
        } catch {
            return .failure(.init(code: "INTERNAL_ERROR", message: "run directory unavailable: \(error)"))
        }

        let stdoutPath = directory.appendingPathComponent(ProcessOwnership.runnerStdoutFileName).path
        let stderrPath = directory.appendingPathComponent(ProcessOwnership.runnerStderrFileName).path
        let workingDir = request.repoRoot ?? FileManager.default.currentDirectoryPath

        // F4: immutable context provenance — resolved absolute root + content
        // hash + thread/run id. The runner refuses any packet that is not this
        // run's own request (wrong-document delivery dies at the gate).
        let provenance = RunContextProvenance.make(
            runId: runId,
            question: request.question,
            context: request.context,
            threadId: request.threadId,
            resolvedRepoRoot: RunWriteLock.normalize(workingDir)
        )
        let payload = AsyncTeamRunnerRequest(
            request: request, origin: origin, acceptedAt: stagedAt, provenance: provenance)
        do {
            try CoreJSON.encode(payload).write(
                to: directory.appendingPathComponent(ProcessOwnership.runnerRequestFileName),
                options: .atomic
            )
        } catch {
            removeRunDirectory(runId: runId)
            return .failure(.init(code: "INTERNAL_ERROR", message: "could not stage runner request: \(error)"))
        }

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
                code: "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
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
                code: "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
                message: "idempotency key was already used with a different payload"
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
                        code: "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
                        message: "idempotency key was already used with a different payload"
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

        // F4 context-provenance gate: the staged packet must be THIS run's own
        // context — run-id match, content-hash recompute, then the durable
        // journal cross-check below. A cross-delivered packet (wrong-document
        // delivery) is refused before any claim or execution.
        let provenance = payload.provenance
        let request = payload.request
        func refuseProvenance(_ reason: String) -> Result<Void, AsyncTeamStartRefusal> {
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "CONTEXT_PROVENANCE_MISMATCH", message: reason),
                in: directory
            )
            return .failure(.init(code: "CONTEXT_PROVENANCE_MISMATCH", message: reason))
        }
        guard provenance.runId == runId else {
            return refuseProvenance("staged packet belongs to run \(provenance.runId), not \(runId)")
        }
        guard provenance.authenticates(
            question: request.question, context: request.context, threadId: request.threadId
        ) else {
            return refuseProvenance("staged packet content does not match its stamped hash")
        }

        // Read raw journal (skip projection).
        guard let run = runStore.loadRaw(runId: runId) else {
            // RLR-L1: name the effective support root so a runner reading the
            // wrong/isolated config home can be diagnosed (RCA class 5).
            let notFound = "no journal for \(runId) (support dir: \(AllnighterPaths.support.path))"
            try? ProcessOwnership.writeRunnerReady(
                .refused(runId: runId, code: "RUN_NOT_FOUND", message: notFound),
                in: directory
            )
            return .failure(.init(code: "RUN_NOT_FOUND", message: notFound))
        }
        if run.status.isTerminal {
            try? ProcessOwnership.writeRunnerReady(
                .accepted(runId: runId, at: payload.acceptedAt),
                in: directory
            )
            return .success(())
        }

        // Journal cross-check: an internally-consistent packet that belongs to
        // a DIFFERENT run still fails — the minted journal is the run's truth.
        let runnerCWD = FileManager.default.currentDirectoryPath
        let (deliveredPrompt, _) = assemblePrompt(request)
        guard run.prompt == deliveredPrompt else {
            return refuseProvenance("delivered context does not match the run's minted prompt")
        }
        guard run.threadId == request.threadId else {
            return refuseProvenance("delivered thread id does not match the run's")
        }
        guard RunWriteLock.normalize(request.repoRoot ?? runnerCWD) == provenance.repoRoot,
              RunWriteLock.normalize(run.repoRoot ?? runnerCWD) == provenance.repoRoot else {
            return refuseProvenance("delivered repo root does not match the run's resolved root")
        }

        // Claim identity as detached runner (pgid recorded; may be PG-killed).
        // Ownership handoff complete → drop the F2 staging lease: from here on
        // the written owner identity is the liveness truth.
        if let identity = ProcessOwnership.OwnerIdentity.current(kind: .detachedRunner) {
            try? ProcessOwnership.writeOwnerIdentity(identity, in: directory)
        }
        // RLR-S04a: worker process-group spawns under this run record their
        // `runtimeOwnership` (workers/<id>.owner.json) into THIS run dir. The
        // coordinator (owner.json, written above) stays a separate owner. This
        // runner process serves exactly one run, then exits — no clear needed.
        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: directory)
        ProcessOwnership.clearStageLease(in: directory)
        try? ProcessOwnership.recordProgress(in: directory, phase: "runner_starting", now: now())

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
                runId: runId, repoRoot: request.repoRoot, persist: persistDuringRun
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
        // RLR-S03a / RLR-L6: activity truth is `run.json.lastActivityAt`, not
        // `heartbeat.json` (retired). `progressStale` is a read-time derivation —
        // absent (nil) before the first post-spawn activity, and only meaningful
        // for a non-terminal run whose owner is still alive.
        response.lastProgressAt = run.lastActivityAt
        if !run.status.isTerminal {
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
    /// An exact run id stays an explicit cross-project target; the bare sweep
    /// is scoped to the caller's canonical project root (`scopeRoot`) — pass
    /// nil only for the explicit machine-wide fleet sweep.
    public func reconcile(runId: String?, scopeRoot: String? = nil) -> [TeamRun] {
        if let runId {
            if let detail = runStore.reconcileRunDetailed(runId: runId, models: models), detail.reaped {
                return [detail.run]
            }
            return []
        }
        return runStore.reconcileAll(models: models, scopeRoot: scopeRoot)
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

        // Same-process ownership: we hold the run's task. Cancelling it stops the
        // in-process work (and reaps any spawned worker group via the runner's own
        // cancel handler) — an authoritative stop, no cross-process verify needed.
        let inProcess = activeRuns.removeValue(forKey: runId)
        inProcess?.task.cancel()
        let directory = try? runStore.runDirectory(forRunId: runId)
        let models = self.models
        let runStore = self.runStore

        cancelledRuns.cancelAndSave(runId) {
            ProcessOwnership.withRunLock(in: directory ?? runStore.rootDirectory) {
                var run = runStore.loadRaw(runId: runId) ?? loaded
                // Never clobber an existing terminal status.
                guard !run.status.isTerminal else { return }

                // RLR-S04b: `team cancel` routes through the ONE settlement. The
                // same-process path is authoritative (we own the task → verified
                // stop); a detached run is verified per recorded member (mode
                // `.cancel` = bounded TERM grace then verdict). Terminal only on a
                // verified `.stopped`; partial/refused/verificationUnavailable
                // record `killOutcome` and leave the lifecycle non-terminal.
                let outcome: KillOutcome
                if inProcess != nil {
                    outcome = .stopped
                } else if let directory {
                    outcome = KillSettlement.settle(runDirectory: directory, mode: .cancel, run: run).outcome
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
                for i in run.workerAnswers.indices where !run.workerAnswers[i].result.status.isTerminal {
                    run.workerAnswers[i].result.status = .cancelled
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
