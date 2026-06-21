import Foundation
import AllnighterCore

/// Reads the team-recursion depth from the environment. Model subprocesses
/// are spawned with `ALLNIGHTER_TEAM_DEPTH` = parent + 1, so any team tool
/// invoked from inside a team sees depth >= 1 and refuses nested team work.
public enum RecursionGuard {
    public static func currentDepth(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        Int(environment["ALLNIGHTER_TEAM_DEPTH"] ?? "0") ?? 0
    }
    public static func atOrOverCeiling(_ ceiling: Int, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        currentDepth(environment: environment) >= ceiling
    }
}

/// Cross-process concurrency cap using `flock(2)` advisory locks on slot files.
/// `flock` is released automatically when the holding process dies/closes the fd,
/// so a crashed team run never leaves a stale lock. `acquire` is non-blocking
/// (`LOCK_NB`): it grabs the first free slot or returns nil when at the cap.
public final class TeamGovernor: @unchecked Sendable {
    public final class Slot {
        let fd: Int32
        init(fd: Int32) { self.fd = fd }
        deinit { flock(fd, LOCK_UN); close(fd) }
    }
    public enum AcquireResult {
        case acquired(Slot)
        case busy
        case unavailable(String)
    }
    public enum Availability: Equatable {
        case available
        case busy
        case unavailable(String)
    }
    private let directory: URL
    private let capacity: Int

    public init(directory: URL? = nil, capacity: Int = 2) {
        self.directory = directory ?? AllnighterPaths.config.appendingPathComponent("Tool/slots", isDirectory: true)
        self.capacity = max(1, capacity)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Grab a free slot, or nil if all `capacity` slots are held (busy).
    public func acquire() -> Slot? {
        guard case .acquired(let slot) = acquireDetailed() else { return nil }
        return slot
    }

    /// Grab a free slot and distinguish real capacity from a broken slot store.
    public func acquireDetailed() -> AcquireResult {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .unavailable("team governor slot store unavailable: cannot create \(directory.path): \(error.localizedDescription)")
        }

        var unavailableReasons: [String] = []
        var sawLockedSlot = false
        for i in 0..<capacity {
            let path = directory.appendingPathComponent("slot_\(i).lock").path
            let fd = open(path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else {
                unavailableReasons.append("open \(path): \(Self.posixMessage(errno))")
                continue
            }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return .acquired(Slot(fd: fd))
            }
            let lockErrno = errno
            if lockErrno == EWOULDBLOCK || lockErrno == EAGAIN {
                sawLockedSlot = true
            } else {
                unavailableReasons.append("lock \(path): \(Self.posixMessage(lockErrno))")
            }
            close(fd)
        }
        if !unavailableReasons.isEmpty {
            return .unavailable("team governor slot store unavailable: \(unavailableReasons.joined(separator: "; "))")
        }
        return sawLockedSlot ? .busy : .unavailable("team governor slot store unavailable: no usable slot files in \(directory.path)")
    }

    /// Non-mutating availability probe for preflight. It briefly acquires one
    /// slot, then releases it immediately. A later `team_start` may still race
    /// another process, but preflight no longer reports OK when the governor is
    /// already full.
    public func availability() -> Availability {
        switch acquireDetailed() {
        case .acquired(let slot):
            _ = slot
            return .available
        case .busy:
            return .busy
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    private static func posixMessage(_ errnoValue: Int32) -> String {
        String(cString: strerror(errnoValue))
    }
}

/// The single normalized entry for running a lane-scoped team from a tool
/// request (CLI / MCP / HTTP). Resolves request → team → workers, runs the fixed
/// answer→review→output staging, and persists to the shared `Runs/` store.
/// Recursion-guarded and governed; origin-tagged. Judgment only — it links no
/// worker-runner code and writes only under `AllnighterPaths`.
public actor TeamService {
    private let models: [Model]
    private let registry: DriverRegistry
    private let teams: [TeamPreset]
    private let config: ToolConfig
    private let runStore: RunStore
    private let commandRunner: CommandRunner
    private let governor: TeamGovernor
    private let now: @Sendable () -> Date
    private let environment: [String: String]
    /// Per-driver invocations from detection (health == runs). Empty → bare command.
    private let invocations: [String: ToolInvocation]

    public init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset] = TeamCatalog.all,
        config: ToolConfig = ToolConfig(),
        runStore: RunStore = RunStore(),
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        governor: TeamGovernor? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.runStore = runStore
        self.commandRunner = commandRunner
        self.governor = governor ?? TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.environment = environment
        self.invocations = invocations
        self.now = now
    }

    /// Catalog teams in a lane (all teams when `lane` is nil), for `alln teams`.
    public func catalogTeams(lane: WorkLane? = nil) -> [TeamPreset] {
        guard let lane else { return teams }
        return teams.teams(in: lane)
    }

    /// Models the resolver may use — enabled bench models. Readiness is the
    /// caller's responsibility; the run still fails per-worker if a CLI is missing.
    private func readyModels() -> [Model] { models.filter(\.enabled) }

    /// Run a team from a tool request. `origin` tags the run; depth is read
    /// from the environment (recursion guard). Staging is fixed answer→review→output.
    public func run(_ request: TeamRequest, origin: RunOrigin, originAgent: String? = nil, events: AsyncStream<RunEvent>.Continuation? = nil) async -> TeamToolResult {
        func finishStream(failed reason: String? = nil) {
            if let reason {
                events?.yield(RunEvent(id: UUID().uuidString, seq: 0, ts: now(), kind: RunEventKind.runStatusChanged,
                                       payload: ["to": .string("failed"), "reason": .string(reason)]))
            }
            events?.finish()
        }

        // Recursion guard (fail closed).
        if RecursionGuard.atOrOverCeiling(config.maxTeamRunDepth, environment: environment) {
            finishStream(failed: "already inside a team; nested teams are disabled")
            return .refused(reason: "already inside a team; nested teams are disabled", code: "NESTED_TEAM_BLOCKED", now: now())
        }

        // Resolve request -> concrete team (lane/team/type/effort); reject conflicts.
        let resolvedRequest: TeamRequestResolver.Resolved
        switch TeamRequestResolver.resolve(teams: teams, lane: request.lane, teamId: request.teamPresetId, type: request.type, effort: request.effort) {
        case .failure(let failure):
            finishStream(failed: failure.description)
            return .refused(reason: failure.description, code: failure.code, now: now())
        case .success(let r):
            resolvedRequest = r
        }

        // Resolve team -> concrete workers against the ready bench.
        let resolved = TeamResolver.resolve(
            team: resolvedRequest.team, requestLane: resolvedRequest.lane,
            requestEffort: resolvedRequest.effort, readyModels: readyModels()
        )
        guard resolved.isRunnable else {
            let reason = resolved.blockReason ?? "team \(resolvedRequest.team.id) cannot run at \(resolvedRequest.effort.rawValue) effort"
            let code = reason.contains("plan/output writer") ? "PLAN_WRITER_FAILED" : "DEFAULT_TEAM_INVALID"
            finishStream(failed: reason)
            return .refused(reason: reason, code: code, preset: resolvedRequest.team.id, now: now())
        }

        let sourceGate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: readyModels())
        if let blocker = sourceGate.sourceGateBlocker {
            finishStream(failed: blocker.message)
            return .refused(reason: blocker.message, code: blocker.code, preset: resolvedRequest.team.id, now: now())
        }

        // Governor (concurrency cap).
        let slot: TeamGovernor.Slot
        switch governor.acquireDetailed() {
        case .acquired(let acquired):
            slot = acquired
        case .busy:
            let reason = "busy: \(config.maxConcurrentTeamRuns) team runs already running"
            finishStream(failed: reason)
            return .refused(reason: reason, code: "TEAM_GOVERNOR_BUSY", preset: resolvedRequest.team.id, now: now())
        case .unavailable(let reason):
            finishStream(failed: reason)
            return .refused(reason: reason, code: "TEAM_GOVERNOR_UNAVAILABLE", preset: resolvedRequest.team.id, now: now())
        }
        defer { _ = slot } // released on scope exit (deinit unlocks).

        // Assemble the prompt (question + bounded context).
        var contextTruncated = false
        var prompt = request.question
        if let context = request.context, !context.isEmpty {
            let (clipped, truncated) = clip(context, limit: config.contextByteLimit)
            contextTruncated = truncated
            prompt += "\n\n# Context\n\(clipped)"
        }

        // Fixed answer -> review -> output staging. The persist closure stamps the
        // catalog facts and writes the journal incrementally (durable before the
        // first worker runs, then on each transition — Journal0).
        let store = runStore
        let allModels = models
        let lane = resolvedRequest.lane, type = resolvedRequest.type, effort = resolvedRequest.effort
        let teamName = resolved.teamDisplayName, outputKind = resolved.outputKind, warnings = resolved.warnings
        let mutating = resolved.mutating
        @Sendable func stamped(_ run: TeamRun) -> TeamRun {
            var r = run
            r.lane = lane; r.type = type; r.effort = effort
            r.teamDisplayName = teamName; r.outputKind = outputKind; r.warnings = warnings
            r.mutating = mutating
            r.executionSourceId = resolved.executionSourceId
            return r
        }
        let persist: @Sendable (TeamRun) -> Void = { try? store.save(stamped($0), models: allModels) }

        let coordinator = CatalogRunCoordinator(
            workerRunner: WorkerRunner(commandRunner: commandRunner, invocations: invocations), registry: registry
        )
        let forwarder: Task<Void, Never>? = events.map { sink in
            Task { for await event in coordinator.events { sink.yield(event) } }
        }
        // Coordinator persists each transition (incl. terminal) via `persist`.
        var run = await coordinator.run(resolved: resolved, prompt: prompt, models: models, origin: origin, originAgent: originAgent, persist: persist)
        await forwarder?.value
        events?.finish()

        // Stamp the returned run too (disk already has it via the terminal persist).
        run = stamped(run)

        let invocations = run.workerAnswers.count + run.stages.filter { $0.status == .done || $0.status == .failed }.count
        return TeamToolResult(
            runId: run.id, origin: origin, preset: resolvedRequest.team.id, status: run.status, createdAt: run.createdAt,
            plan: run.plan, analysis: run.analysis,
            partials: run.failedWorkerAnswers.map { WorkerFailure(workerId: $0.workerId, reason: $0.errorReason ?? $0.status.rawValue) },
            contextTruncated: contextTruncated, invocations: invocations, warnings: resolved.warnings
        )
    }

    /// Read-only, zero-cost recall over local history.
    public func recall(query: String, limit: Int = 5) -> [RecallResult] {
        let q = query.lowercased()
        return runStore.list()
            .filter { $0.status == .complete && $0.prompt.lowercased().contains(q) }
            .prefix(limit)
            .map { run in
                let plan = run.plan ?? ""
                return RecallResult(runId: run.id, prompt: run.prompt, createdAt: run.createdAt,
                                    planExcerpt: String(plan.prefix(400)))
            }
    }

    private func clip(_ text: String, limit: Int) -> (String, Bool) {
        let bytes = Array(text.utf8)
        guard bytes.count > limit else { return (text, false) }
        let half = limit / 2
        let head = String(decoding: bytes.prefix(half), as: UTF8.self)
        let tail = String(decoding: bytes.suffix(half), as: UTF8.self)
        return (head + "\n[… truncated \(bytes.count - limit) bytes …]\n" + tail, true)
    }
}
