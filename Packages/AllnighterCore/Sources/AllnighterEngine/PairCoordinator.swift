import Foundation
import AllnighterCore

/// Pair-programming control plane: one slice or an autonomous queue (Pair_Programming_Team).
public struct PairCoordinator: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var packet: WorkSlicePacket
        public var gate: SliceGate.Decision
        public var terminal: SliceTerminalOutcome?
        public var check: CheckResult?
        public var seats: Seats
        public var parentRun: TeamRun?
        public var childRun: TeamRun?
    }

    public struct QueueOptions: Sendable {
        public var until: Date?
        /// Stall nudges before treating a stall as a failed executor attempt (legacy; defaults to packet maxRetries).
        public var maxRetries: Int?
        /// GLM executor attempts on one packet before planner (Composer) takeover. Default 3.
        public var executorAttemptsBeforePlanner: Int
        /// Max consecutive `.compacting` terminals before escalating (does not consume executor budget).
        public var maxCompactionRetries: Int
        /// Max consecutive `.infraBackoff` terminals before escalating (does not consume executor budget).
        public var maxInfraBackoffRetries: Int
        /// Sleep between infraBackoff retries. Default 5s.
        public var infraBackoffGraceSeconds: Int
        public var executorTeamId: String
        public var seats: Seats
        /// Optional heartbeat callback (human or NDJSON) during unattended queue runs.
        public var onProgress: PairQueueProgressHandler?
        /// When set, progress + run tails are appended for `--verbose`.
        public var verboseLogURL: URL?

        public init(
            until: Date? = nil,
            maxRetries: Int? = nil,
            executorAttemptsBeforePlanner: Int = 3,
            maxCompactionRetries: Int = 10,
            maxInfraBackoffRetries: Int = 10,
            infraBackoffGraceSeconds: Int = 5,
            executorTeamId: String,
            seats: Seats = .testDefaults,
            onProgress: PairQueueProgressHandler? = nil,
            verboseLogURL: URL? = nil
        ) {
            self.until = until
            self.maxRetries = maxRetries
            self.executorAttemptsBeforePlanner = max(1, executorAttemptsBeforePlanner)
            self.maxCompactionRetries = max(1, maxCompactionRetries)
            self.maxInfraBackoffRetries = max(1, maxInfraBackoffRetries)
            self.infraBackoffGraceSeconds = max(0, infraBackoffGraceSeconds)
            self.executorTeamId = executorTeamId
            self.seats = seats
            self.onProgress = onProgress
            self.verboseLogURL = verboseLogURL
        }
    }

    public struct QueueOutcome: Sendable, Equatable {
        public var passed: Int
        public var plannerResolved: Int
        public var escalated: Int
        public var stoppedReason: String?
        public var entries: [SliceQueueEntry]
    }

    public static let defaultExecutorTeamId = "default_chat"

    /// Planner + executor seats for pair testing (Composer plans, Gemini hammers).
    public struct Seats: Sendable, Equatable {
        public var plannerWorkerId: String
        public var executorWorkerId: String

        public static let testDefaults = Seats(
            plannerWorkerId: "model_cursor_composer_25",
            executorWorkerId: "model_gemini"
        )

        public init(plannerWorkerId: String, executorWorkerId: String) {
            self.plannerWorkerId = plannerWorkerId
            self.executorWorkerId = executorWorkerId
        }
    }

    private let runService: RunService
    private let checkRunner: CheckRunner
    private let serveCoordinator: OpenCodeServeCoordinator
    private let runStore: RunStore
    private let now: @Sendable () -> Date

    public init(
        runService: RunService,
        checkRunner: CheckRunner,
        serveCoordinator: OpenCodeServeCoordinator = OpenCodeServeCoordinator(),
        runStore: RunStore = RunStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runService = runService
        self.checkRunner = checkRunner
        self.serveCoordinator = serveCoordinator
        self.runStore = runStore
        self.now = now
    }

    public func runSlice(
        packet: WorkSlicePacket,
        repoRoot: String,
        projectId: String?,
        executorTeamId: String,
        origin: RunOrigin,
        seats: Seats = .testDefaults,
        nudge: String? = nil
    ) async -> Result<Outcome, RunServiceError> {
        let executorFacts = await runService.tryFixExecutorFacts(teamId: executorTeamId)
        let gate = SliceGate.evaluate(packet: packet, executor: executorFacts)
        guard gate.isAllowed else {
            return .success(Outcome(packet: packet, gate: gate, seats: seats))
        }

        do {
            try await ensureServeIfNeeded(executorTeamId: executorTeamId)
        } catch {
            return .failure(.teamResolution("opencode serve: \(error)", code: "PAIR_SERVE_UNAVAILABLE"))
        }

        let parentId = "slice_\(packet.sliceId)_\(UUID().uuidString.lowercased())"
        var parent = TeamRun(
            id: parentId,
            prompt: """
            pair slice \(packet.sliceId): \(packet.title)
            planner=\(seats.plannerWorkerId) executor=\(seats.executorWorkerId)
            """,
            status: .draft,
            origin: origin,
            createdAt: now(),
            repoRoot: repoRoot
        )

        let prompt = Self.assemblePrompt(packet: packet, nudge: nudge)
        let spawnLimit = Self.reviewSpawnConcurrencyLimit()
        let childRequest = RunRequest(
            message: prompt,
            repoRoot: repoRoot,
            projectId: projectId,
            presetId: executorTeamId,
            workerId: seats.executorWorkerId,
            advisoryReview: packet.isAdvisoryReview,
            spawnConcurrencyLimit: packet.isAdvisoryReview ? spawnLimit : nil
        )

        let childResult = await runService.run(childRequest, origin: origin)
        guard case .success(var child) = childResult else {
            if case .failure(let error) = childResult { return .failure(error) }
            return .failure(.noWorker("slice run failed"))
        }

        let workerOutcome = Self.workerOutcome(from: child.workerAnswers.first)
        let check = await checkRunner.run(check: packet.check, repoRoot: repoRoot)
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: workerOutcome, check: check, packet: packet, now: now())
        )

        parent.status = .complete
        child.parentRunId = parent.id
        child.links = child.runLinks + [RunLink(kind: .sliceOf, runId: parent.id)]
        parent.links = parent.runLinks + [RunLink(kind: .sliceAttemptFor, runId: child.id)]
        _ = await runService.save(parent)
        _ = await runService.save(child)

        return .success(
            Outcome(
                packet: packet,
                gate: gate,
                terminal: terminal,
                check: check,
                seats: seats,
                parentRun: parent,
                childRun: child
            )
        )
    }

    public func runQueue(
        queue: inout SliceQueue,
        store: SliceQueueStore,
        repoRoot: String,
        projectId: String?,
        options: QueueOptions,
        origin: RunOrigin
    ) async -> QueueOutcome {
        reconcileStaleRunning(&queue, store: store)
        var passed = 0
        var plannerResolved = 0
        var escalated = 0
        var stoppedReason: String?

        let attemptBudget = options.executorAttemptsBeforePlanner

        while let idx = queue.entries.firstIndex(where: { $0.status == .pending }) {
            if let until = options.until, now() >= until {
                stoppedReason = "until deadline"
                break
            }

            queue.entries[idx].status = .running
            try? store.save(queue)

            let sliceId = queue.entries[idx].packet.sliceId
            let sliceStartedAt = now()
            reportProgress(options, .sliceRunning(sliceId: sliceId))
            appendVerbose(options, "slice \(sliceId) running")

            var entry = queue.entries[idx]
            var nudge: String?
            var settled = false
            var executorAttempt = 0
            var compactionRetries = 0
            var infraBackoffRetries = 0

            while !settled {
                executorAttempt += 1
                let result = await runSlice(
                    packet: entry.packet,
                    repoRoot: repoRoot,
                    projectId: projectId,
                    executorTeamId: options.executorTeamId,
                    origin: origin,
                    seats: options.seats,
                    nudge: nudge
                )

                switch result {
                case .failure:
                    entry.retries = executorAttempt
                    if executorAttempt < attemptBudget {
                        nudge = NudgePrompt.failureRetry(
                            packet: entry.packet,
                            attempt: executorAttempt,
                            maxAttempts: attemptBudget,
                            reason: "run service error",
                            checkStdoutTail: entry.lastStdoutTail,
                            stdoutTail: entry.lastStdoutTail
                        )
                    } else {
                        let takeover = await runPlannerTakeover(
                            packet: entry.packet,
                            repoRoot: repoRoot,
                            projectId: projectId,
                            executorTeamId: options.executorTeamId,
                            seats: options.seats,
                            context: .init(
                                executorAttempts: executorAttempt,
                                lastTerminal: SliceTerminalOutcome.failed.rawValue,
                                checkExitCode: entry.checkExitCode,
                                checkStdoutTail: entry.lastStdoutTail
                            ),
                            origin: origin
                        )
                        applyPlannerTakeover(takeover, to: &entry)
                        if entry.status == .passed {
                            if entry.resolvedBy == "planner" { plannerResolved += 1 } else { passed += 1 }
                        } else {
                            escalated += 1
                        }
                        settled = true
                    }
                case .success(let outcome):
                    if !outcome.gate.isAllowed {
                        entry.status = .escalated
                        if case .blocked(_, let reason) = outcome.gate {
                            entry.escalatedReason = reason
                        }
                        escalated += 1
                        settled = true
                        break
                    }

                    guard let terminal = outcome.terminal else {
                        entry.status = .escalated
                        entry.escalatedReason = "no terminal outcome"
                        escalated += 1
                        settled = true
                        break
                    }

                    entry.parentRunId = outcome.parentRun?.id
                    entry.childRunId = outcome.childRun?.id
                    entry.checkExitCode = outcome.check?.exitCode
                    entry.lastStdoutTail = outcome.check?.stdoutTail

                    switch terminal {
                    case .passed:
                        entry.status = .passed
                        entry.resolvedBy = "executor"
                        passed += 1
                        settled = true
                    case .compacting:
                        compactionRetries += 1
                        if compactionRetries > options.maxCompactionRetries {
                            entry.status = .escalated
                            entry.escalatedReason = "compaction budget exhausted"
                            escalated += 1
                            settled = true
                            break
                        }
                        executorAttempt -= 1
                        let grace = UInt64(entry.packet.compactionGraceSeconds) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: grace)
                        nudge = nil
                    case .infraBackoff:
                        infraBackoffRetries += 1
                        if infraBackoffRetries > options.maxInfraBackoffRetries {
                            entry.status = .escalated
                            entry.escalatedReason = "infra backoff budget exhausted"
                            escalated += 1
                            settled = true
                            break
                        }
                        executorAttempt -= 1
                        let backoff = UInt64(options.infraBackoffGraceSeconds) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: backoff)
                        nudge = nil
                    case .stalled, .failed:
                        entry.retries = executorAttempt
                        if executorAttempt < attemptBudget {
                            nudge = NudgePrompt.failureRetry(
                                packet: entry.packet,
                                attempt: executorAttempt,
                                maxAttempts: attemptBudget,
                                reason: Self.failureReason(terminal: terminal, check: outcome.check),
                                checkStdoutTail: outcome.check?.stdoutTail,
                                stdoutTail: outcome.check?.stdoutTail
                            )
                        } else {
                            let takeover = await runPlannerTakeover(
                                packet: entry.packet,
                                repoRoot: repoRoot,
                                projectId: projectId,
                                executorTeamId: options.executorTeamId,
                                seats: options.seats,
                                context: .init(
                                    executorAttempts: executorAttempt,
                                    lastTerminal: terminal.rawValue,
                                    checkExitCode: outcome.check?.exitCode,
                                    checkStdoutTail: outcome.check?.stdoutTail,
                                    lastWorkerOutput: outcome.childRun?.workerAnswers.first?.output
                                ),
                                origin: origin
                            )
                            applyPlannerTakeover(takeover, to: &entry)
                            if entry.status == .passed {
                                if entry.resolvedBy == "planner" { plannerResolved += 1 } else { passed += 1 }
                            } else {
                                escalated += 1
                            }
                            settled = true
                        }
                    }
                }
            }

            queue.entries[idx] = entry
            try? store.save(queue)

            let elapsed = max(0, Int(now().timeIntervalSince(sliceStartedAt)))
            reportProgress(options, .sliceFinished(
                sliceId: sliceId, status: entry.status.rawValue, elapsedSeconds: elapsed))
            appendVerbose(options, "slice \(sliceId) \(entry.status.rawValue) (\(elapsed)s)")
            if let childRunId = entry.childRunId {
                appendVerbose(options, tailRunEvents(childRunId: childRunId))
            }
        }

        return QueueOutcome(
            passed: passed,
            plannerResolved: plannerResolved,
            escalated: escalated,
            stoppedReason: stoppedReason,
            entries: queue.entries
        )
    }

    public struct PlannerTakeoverOutcome: Sendable, Equatable {
        public var check: CheckResult?
        public var plannerRun: TeamRun?
        public var passed: Bool
        public var errorReason: String?
    }

    public func runPlannerTakeover(
        packet: WorkSlicePacket,
        repoRoot: String,
        projectId: String?,
        executorTeamId: String,
        seats: Seats,
        context: PlannerTakeoverPrompt.Context,
        origin: RunOrigin
    ) async -> PlannerTakeoverOutcome {
        do {
            try await ensureServeIfNeeded(executorTeamId: executorTeamId)
        } catch {
            return .init(check: nil, plannerRun: nil, passed: false, errorReason: "opencode serve: \(error)")
        }

        let prompt = PlannerTakeoverPrompt.assemble(packet: packet, context: context)
        let request = RunRequest(
            message: prompt,
            repoRoot: repoRoot,
            projectId: projectId,
            presetId: executorTeamId,
            workerId: seats.plannerWorkerId
        )
        let runResult = await runService.run(request, origin: origin)
        guard case .success(let plannerRun) = runResult else {
            let message: String
            if case .failure(let error) = runResult { message = error.description }
            else { message = "planner run failed" }
            return .init(check: nil, plannerRun: nil, passed: false, errorReason: message)
        }

        let check = await checkRunner.run(check: packet.check, repoRoot: repoRoot)
        let passed = !check.timedOut && (check.skipped || check.exitCode == 0)
        return .init(check: check, plannerRun: plannerRun, passed: passed, errorReason: passed ? nil : "planner takeover check failed")
    }

    private static func failureReason(terminal: SliceTerminalOutcome, check: CheckResult?) -> String {
        switch terminal {
        case .failed:
            if let code = check?.exitCode, code != 0 {
                return "repo check failed (exit \(code))"
            }
            if check?.timedOut == true {
                return "repo check timed out"
            }
            return "worker error or empty result"
        case .stalled:
            return "stalled — no usable output"
        default:
            return terminal.rawValue
        }
    }

    private func applyPlannerTakeover(_ takeover: PlannerTakeoverOutcome, to entry: inout SliceQueueEntry) {
        entry.plannerRunId = takeover.plannerRun?.id
        entry.checkExitCode = takeover.check?.exitCode
        entry.lastStdoutTail = takeover.check?.stdoutTail
        if takeover.passed {
            entry.status = .passed
            entry.resolvedBy = "planner"
            entry.escalatedReason = nil
        } else {
            entry.status = .escalated
            entry.escalatedReason = takeover.errorReason ?? "planner takeover failed"
        }
    }

    private func ensureServeIfNeeded(executorTeamId: String) async throws {
        guard let team = TeamCatalog.get(executorTeamId), team.executionSourceId == "opencode" else { return }
        try await serveCoordinator.ensureRunning()
    }

    /// Reset queue entries stuck `running` when their child run is dead or finished.
    func reconcileStaleRunning(_ queue: inout SliceQueue, store: SliceQueueStore) {
        var changed = false
        for idx in queue.entries.indices where queue.entries[idx].status == .running {
            let entry = queue.entries[idx]
            var live = false
            if let childId = entry.childRunId, let run = runStore.load(runId: childId), !run.status.isTerminal {
                let directory = runStore.rootDirectory.appendingPathComponent("run_\(childId)", isDirectory: true)
                if let pid = ownerPID(directory), RunStore.processAlive(pid) {
                    live = true
                }
            }
            if live { continue }
            queue.entries[idx].status = .pending
            queue.entries[idx].childRunId = nil
            changed = true
        }
        if changed { try? store.save(queue) }
    }

    /// Queue status for `pair status` / MCP `pair_status`.
    public func queueStatus(queue: SliceQueue, queuePath: String) -> PairStatusJSON {
        let entries = queue.entries.map { entry -> PairStatusJSON.Entry in
            let guidance: String
            var elapsed: Int?
            if entry.status == .running {
                if let childId = entry.childRunId, let run = runStore.load(runId: childId) {
                    let started = run.workerAnswers.first?.startedAt ?? run.createdAt
                    elapsed = max(0, Int(now().timeIntervalSince(started)))
                    let stall = entry.packet.stallTimeoutSeconds
                    if let elapsed, elapsed < stall {
                        guidance = "slice in progress — check queue.json (child run \(childId), \(elapsed)s elapsed)"
                    } else {
                        guidance = "slice may be stalled — elapsed \(elapsed ?? 0)s exceeds stall timeout \(stall)s; check queue.json and child run \(childId)"
                    }
                } else {
                    guidance = "slice marked running but no live child run — re-run `pair run` to reconcile"
                }
            } else if entry.status == .pending {
                guidance = "waiting in queue"
            } else if entry.status == .passed {
                guidance = entry.resolvedBy == "planner" ? "passed via planner takeover" : "passed by executor"
            } else if entry.status == .escalated {
                guidance = entry.escalatedReason ?? "escalated — manual review needed"
            } else {
                guidance = entry.status.rawValue
            }
            return PairStatusJSON.Entry(
                sliceId: entry.packet.sliceId,
                status: entry.status.rawValue,
                childRunId: entry.childRunId,
                elapsedSeconds: elapsed,
                guidance: guidance
            )
        }
        return PairStatusJSON(
            contractVersion: ContractRegistry.contractVersion,
            queuePath: queuePath,
            entries: entries
        )
    }

    private func reportProgress(_ options: QueueOptions, _ event: PairQueueProgressEvent) {
        options.onProgress?(event)
    }

    private func appendVerbose(_ options: QueueOptions, _ line: String) {
        guard let url = options.verboseLogURL else { return }
        let stamp = ISO8601DateFormatter().string(from: now())
        let row = "[\(stamp)] \(line)\n"
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(row.utf8))
            try? handle.close()
        } else {
            try? Data(row.utf8).write(to: url, options: .atomic)
        }
    }

    private func tailRunEvents(childRunId: String, maxLines: Int = 20) -> String {
        let eventsURL = runStore.rootDirectory
            .appendingPathComponent("run_\(childRunId)", isDirectory: true)
            .appendingPathComponent("events.jsonl")
        guard let text = try? String(contentsOf: eventsURL, encoding: .utf8) else {
            return "(no events.jsonl for \(childRunId))"
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxLines)
        return "events tail \(childRunId):\n" + lines.joined(separator: "\n")
    }

    private func ownerPID(_ directory: URL) -> Int32? {
        guard let raw = try? String(contentsOf: directory.appendingPathComponent("owner.pid"), encoding: .utf8) else {
            return nil
        }
        return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func assemblePrompt(packet: WorkSlicePacket, nudge: String?) -> String {
        switch packet.mode {
        case .implement:
            return SliceAttemptPrompt.assemble(packet: packet, nudge: nudge)
        case .review:
            return ReviewAttemptPrompt.assemble(packet: packet, nudge: nudge)
        case .reviewVerify:
            return ReviewVerifyPrompt.assemble(packet: packet, nudge: nudge)
        }
    }

    /// `ALLNIGHTER_REVIEW_SPAWN_LIMIT` — parallel CR fan-out (Featherless ≤4). Only when >1.
    static func reviewSpawnConcurrencyLimit() -> Int? {
        guard let raw = ProcessInfo.processInfo.environment["ALLNIGHTER_REVIEW_SPAWN_LIMIT"],
              let value = Int(raw), value > 1 else { return nil }
        return min(value, CodeReviewParallelSafety.defaultMaxConcurrent)
    }

    private static func workerOutcome(from answer: WorkerAnswer?) -> WorkerRunOutcome {
        guard let answer else {
            return WorkerRunOutcome(status: .failed, errorReason: "no worker answer")
        }
        var outcome = WorkerRunOutcome(status: answer.status, output: answer.output)
        outcome.errorKind = answer.errorKind
        outcome.errorReason = answer.errorReason
        outcome.startedAt = answer.startedAt
        outcome.finishedAt = answer.finishedAt
        outcome.durationMs = answer.durationMs
        outcome.exitCode = answer.exitCode
        return outcome
    }
}
