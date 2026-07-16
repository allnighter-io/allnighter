import Foundation
import AgentOSTeam

/// Projects the internal `TeamRun` persistence model into the public
/// `TeamRunJSON` contract (docs/phases/CLI_Implementation_Contract.md
/// §TeamRunJSON). The internal model may evolve; this mapper is the single seam
/// that keeps the public contract stable. `alln team --json`, `alln show --json`,
/// and the GUI/MCP/iOS presenters all read the mapper's output — never the raw
/// internal model.
public enum TeamRunJSONMapper {
    /// CLI-supplied context the internal `TeamRun` does not carry.
    public struct Context: Sendable {
        public var promptSource: TeamRunJSON.PromptSource
        public var lane: String?
        public var type: String?
        public var effort: String?
        public var runJournalPath: String
        public var reproduceCommand: String?
        public var includeWorkerPromptSnapshots: Bool
        /// Run folder for resolving design image absolute paths.
        public var runDirectory: URL?
        public init(
            promptSource: TeamRunJSON.PromptSource = .init(kind: .positional),
            lane: String? = nil, type: String? = nil, effort: String? = nil,
            runJournalPath: String, reproduceCommand: String? = nil,
            includeWorkerPromptSnapshots: Bool = false,
            runDirectory: URL? = nil
        ) {
            self.promptSource = promptSource; self.lane = lane; self.type = type
            self.effort = effort; self.runJournalPath = runJournalPath
            self.reproduceCommand = reproduceCommand
            self.includeWorkerPromptSnapshots = includeWorkerPromptSnapshots
            self.runDirectory = runDirectory
        }
    }

    public static func map(_ run: TeamRun, models: [Model], manifests: [DriverManifest], context: Context) -> TeamRunJSON {
        let modelById = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func sourceName(_ driverId: String) -> String? { manifests.first { $0.id == driverId }?.displayName }
        func modelName(_ id: String) -> String { modelById[id]?.displayName ?? id }
        func sourceId(_ modelId: String) -> String { modelById[modelId]?.driverId ?? "" }

        let planStage = run.latestStage(.plan)

        let workers = run.workers.map { w in
            TeamRunJSON.WorkerInfo(
                id: w.id, skillId: w.skillId, skillName: w.skillName ?? w.label ?? w.skillId,
                resolvedWorkerPromptSnapshot: context.includeWorkerPromptSnapshots ? w.resolvedWorkerPromptSnapshot : nil,
                modelId: w.modelId, modelName: modelName(w.modelId), sourceId: sourceId(w.modelId),
                purpose: workerPurpose(w.purpose), instanceIndex: w.instanceIndex
            )
        }

        let answers = run.workerAnswers.map { a in
            let outputAbsolute: String? = {
                guard let output = a.output, let dir = context.runDirectory,
                      RunImagePathResolver.isImagePath(output) else { return nil }
                return RunImagePathResolver.absolutePath(runDirectory: dir, relativePath: output)
            }()
            return TeamRunJSON.AnswerInfo(
                workerId: a.memberId, modelId: a.modelId, status: mapWorker(a.result.status),
                durationMs: a.result.timing.durationMs, markdown: a.output,
                outputAbsolutePath: outputAbsolute,
                error: errorEnvelope(for: a, runId: run.id)
            )
        }

        let designBoard = mapDesignBoard(run, runDirectory: context.runDirectory)

        let stages = run.stages.compactMap { mapStage($0) }

        // Emit a plan only when one was actually produced (stage done → `run.plan`
        // is the markdown). A failed/absent plan is null here and remains visible
        // as a stage in `stages`.
        let plan: TeamRunJSON.Plan? = {
            guard let stage = planStage, let markdown = run.plan else { return nil }
            return TeamRunJSON.Plan(
                status: .done, writerWorkerId: stage.producedByWorkerId,
                stageId: stage.id, markdown: markdown
            )
        }()

        let ran = run.workerAnswers.filter { $0.result.status != .skipped }.count
        let planDone = planStage?.status == .done
        let usage = TeamRunJSON.Usage(cliCalls: ran + (planDone ? 1 : 0))

        let started = run.workerAnswers.compactMap(\.result.timing.startedAt).min()
        let completed = run.status.isTerminal ? run.workerAnswers.compactMap(\.result.timing.finishedAt).max() : nil

        // Prefer the run's own catalog facts (self-describing); fall back to
        // caller-supplied context for legacy runs that did not record them.
        let workerModelId = RunIdentity.primaryWorkerModelId(run)
        let info = TeamRunJSON.RunInfo(
            id: run.id, status: mapRun(run.status), origin: mapOrigin(run.origin),
            originAgent: run.originAgent,
            lane: run.lane?.rawValue ?? context.lane,
            type: run.type ?? context.type,
            effort: run.effort?.rawValue ?? context.effort,
            prompt: run.prompt, promptSource: context.promptSource,
            createdAt: isoString(run.createdAt), startedAt: iso(started), completedAt: iso(completed),
            threadId: run.threadId, teamPresetId: run.presetId,
            teamDisplayName: run.teamDisplayName, outputKind: run.outputKind?.rawValue,
            workerId: workerModelId,
            writePolicy: RunIdentity.writePolicyLabel(mutating: run.mutating),
            identitySummary: RunIdentity.summary(
                workerId: workerModelId, lane: run.lane, mutating: run.mutating,
                laneContextOnly: run.laneContextOnly == true),
            planWriterWorkerId: plan?.writerWorkerId, reproduceCommand: context.reproduceCommand
        )

        let modelInfos = models.map {
            TeamRunJSON.ModelInfo(id: $0.id, displayName: $0.displayName, sourceId: $0.driverId, sourceName: sourceName($0.driverId), status: .ready)
        }

        return TeamRunJSON(
            contractVersion: ContractRegistry.contractVersion,
            teamRun: info, models: modelInfos, workers: workers, workerAnswers: answers,
            designBoard: designBoard,
            repoDelta: run.mutating ? run.repoDelta : nil,
            outcome: run.status.isTerminal ? mapOutcome(run) : nil,
            stages: stages, plan: plan, usage: usage,
            warnings: run.warnings.map { TeamRunJSON.Warning(message: $0) }, errors: [],
            nextActions: [
                .init(kind: .showRun, command: "alln show \(run.id)", label: "Show run"),
                .init(kind: .export, command: "alln export \(run.id) --format md", label: "Export markdown"),
            ],
            audit: .init(traceId: "trace_\(run.id)", runJournalPath: context.runJournalPath)
        )
    }

    /// Worker terminal states → mechanical outcome status (never a correctness verdict).
    static func mapOutcomeStatus(_ run: TeamRun) -> TeamRunJSON.Outcome.Status {
        let answers = run.workerAnswers.filter { $0.result.status != .skipped }
        guard !answers.isEmpty else { return .failed }
        let doneCount = answers.filter { $0.result.status == .done }.count
        if doneCount == answers.count { return .completed }
        if doneCount > 0 { return .partial }
        if answers.contains(where: { $0.result.status == .timedOut }) { return .timedOut }
        return .failed
    }

    static func mapOutcome(_ run: TeamRun) -> TeamRunJSON.Outcome {
        let commitMatched = run.requestedCommitMessage.flatMap {
            CommitMessageFidelity.matched(requested: $0, delta: run.repoDelta)
        }
        let proof: TeamRunJSON.Outcome.Proof? = run.proofResult.map {
            TeamRunJSON.Outcome.Proof(
                command: $0.command, exitCode: $0.exitCode, passed: $0.passed, outputTail: $0.outputTail)
        }
        return TeamRunJSON.Outcome(
            status: mapOutcomeStatus(run),
            committed: run.repoDelta?.changed == true,
            headline: RunIdentity.outcomeHeadline(run),
            commitMessageMatched: commitMatched,
            proof: proof)
    }

    // MARK: - Enum mappings

    /// Internal run lifecycle → the closed public set. `partial` is a finished run
    /// with some failed workers (shown in workerAnswers), so it maps to `done`.
    static func mapRun(_ s: RunStatus) -> TeamRunJSON.Status {
        switch s {
        case .draft: return .queued
        case .fanningOut, .answersIn, .planning, .reviewing, .finalizing: return .running
        case .complete, .partial: return .done
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .interrupted: return .interrupted
        }
    }

    static func mapWorker(_ s: WorkerAnswerStatus) -> TeamRunJSON.Status {
        switch s {
        case .queued: return .queued
        case .running: return .running
        case .done: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .skipped: return .skipped
        }
    }

    static func mapStage(status s: StageStatus) -> TeamRunJSON.Status {
        switch s {
        case .queued: return .queued
        case .running: return .running
        case .done, .reused: return .done
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .skipped: return .skipped
        }
    }

    /// Worker stage → public worker purpose. Legacy runs (nil) are answer workers.
    static func workerPurpose(_ stage: WorkerStage?) -> TeamRunJSON.WorkerPurpose {
        switch stage {
        case .review: return .review
        case .plan: return .plan
        case .scout, .answer, nil: return .answer // scout projects as an answer worker
        }
    }

    static func mapOrigin(_ o: RunOrigin) -> TeamRunJSON.Origin {
        switch o {
        case .cli: return .cli
        case .gui: return .gui
        case .mcp: return .mcp
        case .http: return .localApi
        case .ios: return .ios
        }
    }

    /// Only `analysis`/`plan`/`review` are part of the public M1 stage set; RB
    /// stages (finalSpec/board) are filtered out.
    static func mapStage(_ stage: StageOutput) -> TeamRunJSON.StageInfo? {
        let purpose: TeamRunJSON.StagePurpose
        switch stage.purpose {
        case .analysis: purpose = .analysis
        case .plan: purpose = .plan
        case .review: purpose = .review
        default: return nil
        }
        return TeamRunJSON.StageInfo(
            id: stage.id, purpose: purpose, status: mapStage(status: stage.status),
            producedByWorkerId: stage.producedByWorkerId, promptProfileId: stage.promptProfileId
        )
    }

    private static func errorEnvelope(for a: TeamAnswer, runId: String) -> ErrorEnvelope? {
        guard a.result.status == .failed || a.result.status == .timedOut else { return nil }
        return ErrorEnvelope(
            code: a.result.status == .timedOut ? "TEAM_RUN_TIMEOUT" : "WORKER_FAILED",
            message: a.result.errorReason ?? "worker did not produce an answer",
            requiresManual: false, retryable: true, runId: runId, workerId: a.memberId
        )
    }

    private static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        return isoString(date)
    }
    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func mapDesignBoard(_ run: TeamRun, runDirectory: URL?) -> TeamRunJSON.DesignBoard? {
        let isDesign = run.lane == .design || run.outputKind == .designBoard
        guard isDesign, let board = run.latestStage(.board)?.payload?.board else { return nil }
        let screenshotAbsolute = board.screenshotPath.flatMap { rel in
            runDirectory.flatMap { RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }
        }
        let options = board.options.map { opt in
            TeamRunJSON.DesignBoardOption(
                workerId: opt.workerId,
                modelId: opt.modelId,
                persona: opt.persona,
                imagePath: opt.imagePath,
                absolutePath: opt.imagePath.flatMap { rel in
                    runDirectory.flatMap { RunImagePathResolver.absolutePath(runDirectory: $0, relativePath: rel) }
                },
                status: mapStage(status: opt.status),
                failureReason: opt.failureReason,
                sessionId: opt.sessionId
            )
        }
        let chosen = board.chosen.map { c in
            TeamRunJSON.DesignBoardChosen(
                workerId: c.workerId,
                persona: c.persona,
                chosenAt: c.chosenAt.map(isoString)
            )
        }
        return TeamRunJSON.DesignBoard(
            targetShape: board.targetShape.rawValue,
            screenshotPath: board.screenshotPath,
            screenshotAbsolutePath: screenshotAbsolute,
            options: options,
            chosen: chosen
        )
    }

}
