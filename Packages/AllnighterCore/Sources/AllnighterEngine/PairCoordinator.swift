import Foundation
import AllnighterCore

/// Pair-programming control plane: one slice or an autonomous queue (Pair_Programming_Team).
public struct PairCoordinator: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var packet: WorkSlicePacket
        public var gate: SliceGate.Decision
        public var terminal: SliceTerminalOutcome?
        public var check: CheckResult?
        public var parentRun: TeamRun?
        public var childRun: TeamRun?
    }

    public struct QueueOptions: Sendable, Equatable {
        public var until: Date?
        public var maxRetries: Int?
        public var executorTeamId: String

        public init(until: Date? = nil, maxRetries: Int? = nil, executorTeamId: String) {
            self.until = until
            self.maxRetries = maxRetries
            self.executorTeamId = executorTeamId
        }
    }

    public struct QueueOutcome: Sendable, Equatable {
        public var passed: Int
        public var escalated: Int
        public var stoppedReason: String?
        public var entries: [SliceQueueEntry]
    }

    public static let defaultExecutorTeamId = FollowUpCoordinator.defaultExecutorTeamId

    private let runService: RunService
    private let checkRunner: CheckRunner
    private let serveCoordinator: OpenCodeServeCoordinator
    private let now: @Sendable () -> Date

    public init(
        runService: RunService,
        checkRunner: CheckRunner,
        serveCoordinator: OpenCodeServeCoordinator = OpenCodeServeCoordinator(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runService = runService
        self.checkRunner = checkRunner
        self.serveCoordinator = serveCoordinator
        self.now = now
    }

    public func runSlice(
        packet: WorkSlicePacket,
        repoRoot: String,
        projectId: String?,
        executorTeamId: String,
        origin: RunOrigin,
        nudge: String? = nil
    ) async -> Result<Outcome, RunServiceError> {
        let executorFacts = await runService.tryFixExecutorFacts(teamId: executorTeamId)
        let gate = SliceGate.evaluate(packet: packet, executor: executorFacts)
        guard gate.isAllowed else {
            return .success(Outcome(packet: packet, gate: gate))
        }

        do {
            try await ensureServeIfNeeded(executorTeamId: executorTeamId)
        } catch {
            return .failure(.teamResolution("opencode serve: \(error)", code: "PAIR_SERVE_UNAVAILABLE"))
        }

        let parentId = "slice_\(packet.sliceId)_\(UUID().uuidString.lowercased())"
        var parent = TeamRun(
            id: parentId,
            prompt: "pair slice \(packet.sliceId): \(packet.title)",
            status: .draft,
            origin: origin,
            createdAt: now(),
            repoRoot: repoRoot
        )

        let prompt = SliceAttemptPrompt.assemble(packet: packet, nudge: nudge)
        let childRequest = RunRequest(
            message: prompt,
            repoRoot: repoRoot,
            projectId: projectId,
            presetId: executorTeamId
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
        var passed = 0
        var escalated = 0
        var stoppedReason: String?

        while let idx = queue.entries.firstIndex(where: { $0.status == .pending }) {
            if let until = options.until, now() >= until {
                stoppedReason = "until deadline"
                break
            }

            queue.entries[idx].status = .running
            try? store.save(queue)

            var entry = queue.entries[idx]
            let retryBudget = options.maxRetries ?? entry.packet.maxRetries
            var nudge: String?
            var settled = false

            while !settled {
                let result = await runSlice(
                    packet: entry.packet,
                    repoRoot: repoRoot,
                    projectId: projectId,
                    executorTeamId: options.executorTeamId,
                    origin: origin,
                    nudge: nudge
                )

                switch result {
                case .failure:
                    entry.status = .escalated
                    entry.escalatedReason = "run service error"
                    escalated += 1
                    settled = true
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
                        passed += 1
                        settled = true
                    case .compacting:
                        let grace = UInt64(entry.packet.compactionGraceSeconds) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: grace)
                        nudge = nil
                    case .infraBackoff:
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        nudge = nil
                    case .stalled:
                        if entry.retries < retryBudget {
                            entry.retries += 1
                            nudge = NudgePrompt.assemble(
                                packet: entry.packet,
                                attempt: entry.retries,
                                maxRetries: retryBudget,
                                reason: "stalled — no usable output",
                                stdoutTail: entry.lastStdoutTail
                            )
                        } else {
                            entry.status = .escalated
                            entry.escalatedReason = "stalled after \(retryBudget) nudges"
                            escalated += 1
                            settled = true
                        }
                    case .failed:
                        entry.status = .escalated
                        entry.escalatedReason = "repo check failed or worker error"
                        escalated += 1
                        settled = true
                    }
                }
            }

            queue.entries[idx] = entry
            try? store.save(queue)
        }

        return QueueOutcome(
            passed: passed,
            escalated: escalated,
            stoppedReason: stoppedReason,
            entries: queue.entries
        )
    }

    private func ensureServeIfNeeded(executorTeamId: String) async throws {
        guard let team = TeamCatalog.get(executorTeamId), team.executionSourceId == "opencode" else { return }
        try await serveCoordinator.ensureRunning()
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
