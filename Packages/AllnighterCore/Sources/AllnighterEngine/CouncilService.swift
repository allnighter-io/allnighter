import Foundation
import AllnighterCore

/// Reads the council-recursion depth from the environment. Worker subprocesses
/// are spawned with `ALLNIGHTER_COUNCIL_DEPTH` = parent + 1, so any council tool
/// invoked from inside a council sees depth >= 1 and refuses to fan out.
public enum RecursionGuard {
    public static func currentDepth(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        Int(environment["ALLNIGHTER_COUNCIL_DEPTH"] ?? "0") ?? 0
    }
    public static func atOrOverCeiling(_ ceiling: Int, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        currentDepth(environment: environment) >= ceiling
    }
}

/// Cross-process concurrency cap using `flock(2)` advisory locks on slot files.
/// `flock` is released automatically when the holding process dies/closes the fd,
/// so a crashed council never leaves a stale lock. `acquire` is non-blocking
/// (`LOCK_NB`): it grabs the first free slot or returns nil when at the cap.
public final class CouncilGovernor: @unchecked Sendable {
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

/// RB6: the single normalized entry for running a council from a tool request
/// (CLI / MCP / HTTP). Reuses the Phase 06 engine; recursion-guarded and governed;
/// origin-tagged; persisted to the shared `Runs/` store. Judgment only — it links
/// no dispatch/executor code and writes only under `AllnighterPaths`.
public actor CouncilService {
    private let workers: [Worker]
    private let registry: DriverRegistry
    private let presets: [PanelPreset]
    private let config: ToolConfig
    private let runStore: RunStore
    private let commandRunner: CommandRunner
    private let governor: CouncilGovernor
    private let now: @Sendable () -> Date
    private let environment: [String: String]

    public init(
        workers: [Worker],
        registry: DriverRegistry,
        presets: [PanelPreset],
        config: ToolConfig = ToolConfig(),
        runStore: RunStore = RunStore(),
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        governor: CouncilGovernor? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workers = workers
        self.registry = registry
        self.presets = presets
        self.config = config
        self.runStore = runStore
        self.commandRunner = commandRunner
        self.governor = governor ?? CouncilGovernor(capacity: config.maxConcurrentCouncils)
        self.environment = environment
        self.now = now
    }

    public func presetSummaries() -> [(id: String, name: String, shape: String)] {
        exposedPresets().map { preset in
            let judgeLabel = resolveJudge(preset: preset)?.displayName
            let shape = WorkOrder.panelSummary(
                seatCount: preset.seats.expandedSeats().count,
                judgeLabel: judgeLabel,
                synthesis: preset.synthesis
            )
            return (preset.id, preset.displayName, shape)
        }
    }

    private func exposedPresets() -> [PanelPreset] {
        let allowed = Set(config.exposedPresetIds)
        let exposed = presets.filter { allowed.contains($0.id) }
        return exposed.isEmpty ? presets : exposed
    }

    /// Run a council from a tool request. `origin` tags the run; depth is read from
    /// the environment (recursion guard).
    public func run(_ request: CouncilRequest, origin: RunOrigin, originAgent: String? = nil) async -> CouncilToolResult {
        // Recursion guard (fail closed).
        if RecursionGuard.atOrOverCeiling(config.maxCouncilDepth, environment: environment) {
            return .refused(reason: "already inside a council; nested councils are disabled", now: now())
        }

        // Resolve preset.
        guard let preset = exposedPresets().first(where: { $0.id == (request.presetId ?? config.defaultPresetId) })
                ?? exposedPresets().first else {
            return .refused(reason: "no exposed preset available", now: now())
        }

        // Governor (concurrency cap).
        guard let slot = governor.acquire() else {
            return .refused(reason: "busy: \(config.maxConcurrentCouncils) councils already running", preset: preset.id, now: now())
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

        // Panel fan-out.
        let seats = preset.seats.expandedSeats()
        let coordinator = CouncilRunCoordinator(workerRunner: WorkerRunner(commandRunner: commandRunner), registry: registry)
        var run = await coordinator.fanOut(prompt: prompt, seats: seats, workers: workers, origin: origin, originAgent: originAgent, presetId: preset.id)

        // Synthesis (analysis + plan), if a judge is available.
        if !run.answeredMembers.isEmpty,
           let judge = resolveJudge(preset: preset), let manifest = registry.manifest(for: judge), manifest.kind == .headlessCLI {
            let stages = await Synthesizer(workerRunner: WorkerRunner(commandRunner: commandRunner))
                .synthesize(run: run, judge: judge, manifest: manifest, workers: workers, config: preset.synthesis)
            run.stages.append(contentsOf: stages)
            run.status = stages.contains { $0.purpose == .plan && $0.status == .done } ? .complete : .partial
        } else {
            run.status = .partial
        }

        try? runStore.save(run, workers: workers)

        let invocations = run.members.count + run.stages.filter { $0.status == .done || $0.status == .failed }.count
        return CouncilToolResult(
            runId: run.id, origin: origin, preset: preset.id, status: run.status, createdAt: run.createdAt,
            masterPlan: run.masterPlan, analysis: run.analysis,
            partials: run.failedMembers.map { SeatFailure(seatId: $0.seatId, reason: $0.errorReason ?? $0.status.rawValue) },
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
                let plan = run.masterPlan ?? ""
                return RecallResult(runId: run.id, prompt: run.prompt, createdAt: run.createdAt,
                                    masterPlanExcerpt: String(plan.prefix(400)))
            }
    }

    private func resolveJudge(preset: PanelPreset) -> Worker? {
        let seated = workers.filter { preset.workerIds.contains($0.id) }
        if let id = preset.synthesis.judgeWorkerId, let w = seated.first(where: { $0.id == id }) { return w }
        return seated.first(where: \.canSynthesize) ?? seated.first
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
