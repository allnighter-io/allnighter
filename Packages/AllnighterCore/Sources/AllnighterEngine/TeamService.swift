import Foundation
import AllnighterCore

/// Reads the team-recursion depth from the environment. Model subprocesses
/// are spawned with `ALLNIGHTER_TEAM_DEPTH` = parent + 1, so any council tool
/// invoked from inside a team sees depth >= 1 and refuses to fan out.
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
/// so a crashed council never leaves a stale lock. `acquire` is non-blocking
/// (`LOCK_NB`): it grabs the first free slot or returns nil when at the cap.
public final class TeamGovernor: @unchecked Sendable {
    public final class Slot {
        let fd: Int32
        init(fd: Int32) { self.fd = fd }
        deinit { flock(fd, LOCK_UN); close(fd) }
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
        for i in 0..<capacity {
            let path = directory.appendingPathComponent("slot_\(i).lock").path
            let fd = open(path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { continue }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return Slot(fd: fd)
            }
            close(fd)
        }
        return nil
    }
}

/// RB6: the single normalized entry for running a team from a tool request
/// (CLI / MCP / HTTP). Reuses the Phase 06 engine; recursion-guarded and governed;
/// origin-tagged; persisted to the shared `Runs/` store. Judgment only — it links
/// no dispatch/executor code and writes only under `AllnighterPaths`.
public actor TeamService {
    private let models: [Model]
    private let registry: DriverRegistry
    private let presets: [TeamPreset]
    private let config: ToolConfig
    private let runStore: RunStore
    private let commandRunner: CommandRunner
    private let governor: TeamGovernor
    private let now: @Sendable () -> Date
    private let environment: [String: String]

    public init(
        models: [Model],
        registry: DriverRegistry,
        presets: [TeamPreset],
        config: ToolConfig = ToolConfig(),
        runStore: RunStore = RunStore(),
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        governor: TeamGovernor? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.models = models
        self.registry = registry
        self.presets = presets
        self.config = config
        self.runStore = runStore
        self.commandRunner = commandRunner
        self.governor = governor ?? TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.environment = environment
        self.now = now
    }

    public func presetSummaries() -> [(id: String, name: String, shape: String)] {
        exposedPresets().map { preset in
            let judgeLabel = resolvePlanWriter(preset: preset)?.displayName
            let shape = WorkOrder.teamSummary(
                workerCount: preset.workerSpecs.expandedWorkers().count,
                judgeLabel: judgeLabel,
                synthesis: preset.synthesis
            )
            return (preset.id, preset.displayName, shape)
        }
    }

    private func exposedPresets() -> [TeamPreset] {
        let allowed = Set(config.exposedPresetIds)
        let exposed = presets.filter { allowed.contains($0.id) }
        return exposed.isEmpty ? presets : exposed
    }

    /// Run a team from a tool request. `origin` tags the run; depth is read from
    /// the environment (recursion guard).
    public func run(_ request: TeamRequest, origin: RunOrigin, originAgent: String? = nil, events: AsyncStream<RunEvent>.Continuation? = nil) async -> TeamToolResult {
        // Live NDJSON streaming: when `events` is provided, forward the
        // coordinator's RunEvents as they happen, then emit plan + terminal
        // events. With `events == nil` (the `--json`/human path) behavior is
        // unchanged.
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
            return .refused(reason: "already inside a team; nested councils are disabled", now: now())
        }

        // Resolve preset.
        guard let preset = exposedPresets().first(where: { $0.id == (request.presetId ?? config.defaultPresetId) })
                ?? exposedPresets().first else {
            finishStream(failed: "no exposed preset available")
            return .refused(reason: "no exposed preset available", now: now())
        }

        // Governor (concurrency cap).
        guard let slot = governor.acquire() else {
            finishStream(failed: "busy: \(config.maxConcurrentTeamRuns) team runs already running")
            return .refused(reason: "busy: \(config.maxConcurrentTeamRuns) councils already running", preset: preset.id, now: now())
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

        let teamWorkers = preset.workerSpecs.expandedWorkers()
        let coordinator = TeamRunCoordinator(workerRunner: WorkerRunner(commandRunner: commandRunner), registry: registry)
        // Forward fan-out events live; the coordinator finishes its stream at the
        // end of fanOut, so awaiting the forwarder flushes them before plan events.
        let forwarder: Task<Void, Never>? = events.map { sink in
            Task { for await event in coordinator.events { sink.yield(event) } }
        }
        var run = await coordinator.fanOut(prompt: prompt, teamWorkers: teamWorkers, models: models, origin: origin, originAgent: originAgent, presetId: preset.id)
        await forwarder?.value

        // Plan writing (analysis + plan), if a plan writer model is available.
        if !run.answeredWorkers.isEmpty,
           let planWriter = resolvePlanWriter(preset: preset), let manifest = registry.manifest(for: planWriter), manifest.kind == .headlessCLI {
            events?.yield(planEvent(kind: RunEventKind.stageStarted, runId: run.id, stageId: nil, workerId: planWriter.id))
            let stages = await PlanWriter(workerRunner: WorkerRunner(commandRunner: commandRunner))
                .synthesize(run: run, judge: planWriter, manifest: manifest, models: models, config: preset.synthesis)
            run.stages.append(contentsOf: stages)
            let planStage = stages.first { $0.purpose == .plan }
            let planDone = planStage?.status == .done
            run.status = planDone ? .complete : .partial
            events?.yield(planEvent(kind: planDone ? RunEventKind.stageCompleted : RunEventKind.stageFailed, runId: run.id, stageId: planStage?.id, workerId: planWriter.id))
        } else {
            run.status = .partial
        }

        try? runStore.save(run, models: models)

        // Terminal: the coordinator's stream ended at `answersIn`; emit the final
        // run-status transition, then finish the live stream.
        if events != nil {
            var payload: [String: JSONValue] = [
                "runId": .string(run.id),
                "from": .string(RunStatus.answersIn.rawValue),
                "to": .string(run.status.rawValue),
            ]
            if let planStageId = run.latestStage(.plan).flatMap({ $0.status == .done ? $0.id : nil }) {
                payload["planStageId"] = .string(planStageId)
            }
            events?.yield(RunEvent(id: UUID().uuidString, seq: 0, ts: now(), kind: RunEventKind.runStatusChanged, payload: payload))
            events?.finish()
        }

        let invocations = run.workerAnswers.count + run.stages.filter { $0.status == .done || $0.status == .failed }.count
        return TeamToolResult(
            runId: run.id, origin: origin, preset: preset.id, status: run.status, createdAt: run.createdAt,
            plan: run.plan, analysis: run.analysis,
            partials: run.failedWorkerAnswers.map { WorkerFailure(workerId: $0.workerId, reason: $0.errorReason ?? $0.status.rawValue) },
            contextTruncated: contextTruncated, invocations: invocations
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

    /// A plan-stage RunEvent for the live stream (the coordinator does not emit
    /// these — the plan stage runs here, after fan-out).
    private func planEvent(kind: String, runId: String, stageId: String?, workerId: String) -> RunEvent {
        var payload: [String: JSONValue] = [
            "runId": .string(runId), "purpose": .string("plan"), "workerId": .string(workerId),
        ]
        if let stageId { payload["stageId"] = .string(stageId) }
        return RunEvent(id: UUID().uuidString, seq: 0, ts: now(), kind: kind, payload: payload)
    }

    private func resolvePlanWriter(preset: TeamPreset) -> Model? {
        let roster = models.filter { preset.workerIds.contains($0.id) }
        if let id = preset.synthesis.planWriterModelId, let m = roster.first(where: { $0.id == id }) { return m }
        return roster.first(where: \.canWritePlan) ?? roster.first
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
