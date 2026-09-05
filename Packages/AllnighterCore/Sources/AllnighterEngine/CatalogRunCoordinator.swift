import Foundation
import AllnighterCore
import AgentOSTeam

/// Runs a resolved lane-team in the fixed catalog staging order:
/// **answer (blind, parallel) → review (sees answers) → output writer (sees
/// everything, preserves dissent)**. Not a generic DAG (Team_Catalog §S05).
/// Reuses the composed `WorkerInvoking` stack (`WorkerInvokerFactory`); emits
/// `RunEvent`s for the live `--stream` projection.
public actor CatalogRunCoordinator {
    private let workerRunner: any WorkerInvoking
    private let registry: DriverRegistry
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    private var seq: Int64 = 0
    private let continuation: AsyncStream<RunEvent>.Continuation
    public nonisolated let events: AsyncStream<RunEvent>

    public init(
        workerRunner: any WorkerInvoking,
        registry: DriverRegistry,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workerRunner = workerRunner
        self.registry = registry
        self.idFactory = idFactory
        self.now = now
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        self.events = stream
        self.continuation = continuation
    }

    /// Run the staged team. `prompt` is the already-assembled founder prompt
    /// (question + bounded context). `workerPrompts` is the ONE additive per-seat
    /// override (`docs/phases/Pilot_Panel.md` decision 10): when a worker id is
    /// present, that seat gets its own founder prompt instead of the shared
    /// `prompt` — answer workers stay blind and parallel either way. Nil/missing
    /// keys keep the shared-prompt path (no behavior change for existing callers).
    /// `workerWorkingDirectories` is the additive per-seat cwd override (PN-S06
    /// clonefile isolation): when a worker id is present, that seat's process
    /// runs with that working directory instead of `repoRoot`. Nil/missing keys
    /// keep the shared-root path.
    /// `persist` is invoked with the run at every status/stage transition —
    /// durable BEFORE workers start, and again as answers/reviews/plan settle
    /// (Journal0 incremental durability). Returns the settled `TeamRun`.
    public func run(
        resolved: ResolvedTeamRun,
        prompt: String,
        models: [Model],
        origin: RunOrigin = .cli,
        originAgent: String? = nil,
        runId: String? = nil,
        repoRoot: String? = nil,
        deliveries: [IncludedAttachmentDelivery] = [],
        workerPrompts: [String: String]? = nil,
        workerWorkingDirectories: [String: String]? = nil,
        /// Run folder for host Design-lane capture (`option_*.html` → `option_*.png`).
        /// Required for `outputKind == .designBoard`; nil skips board write (fail closed).
        runDirectory: URL? = nil,
        persist: (@Sendable (TeamRun) -> Void)? = nil
    ) async -> TeamRun {
        let modelByID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let scoutList = resolved.scoutWorker.map { [$0] } ?? []
        let seeded = scoutList + resolved.answerWorkers + resolved.reviewWorkers
        let team = TeamCatalog.get(resolved.teamPresetId)
        let lane = team?.lane ?? .code

        var run = TeamRun(
            id: runId ?? idFactory(),
            prompt: prompt,
            status: .draft,
            origin: origin,
            originAgent: originAgent,
            presetId: resolved.teamPresetId,
            workers: resolved.allWorkers,
            answers: seeded.map {
                TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? AgentStage.answer.rawValue,
                          result: WorkerRunResult(status: .queued))
            },
            createdAt: now(),
            repoRoot: repoRoot
        )
        // Stamp catalog facts early so Design board mapping + persist see them.
        run.lane = lane
        run.outputKind = resolved.outputKind
        run.teamDisplayName = resolved.teamDisplayName
        // RLR-L3: a one-worker fan-out never carries `fanning_out`. `seeded` is the
        // crew that fans out in parallel (scout + answer + review); the synthetic
        // plan writer runs after and is not a fan-out member. One crew member ⇒
        // `running`/`working`; a genuine multi-worker fan-out keeps `fanning_out`.
        if seeded.count <= 1 {
            run = transition(run, to: .running, phase: .working)
        } else {
            run = transition(run, to: .fanningOut, phase: .working)
        }
        persist?(run) // durable state before any worker executes

        // Stage 0 — the scout (e.g. an X-capable model) distills the raw source FIRST.
        // Its output is injected into every downstream worker's context so the whole
        // crew reasons over the same distilled packet (the crux of triangulation).
        // Per-seat overrides do not apply to scout/review/writer — only answer seats.
        var downstreamPrompt = prompt
        if let scout = resolved.scoutWorker {
            let (scoutAnswers, scoutSnapshots) = await runWorkers(
                [scout], prompt: prompt, effort: resolved.effort, modelByID: modelByID,
                run: &run, repoRoot: repoRoot, deliveries: deliveries, workerPrompts: nil,
                workerWorkingDirectories: workerWorkingDirectories, persist: persist,
                team: team, lane: lane, reseatPool: models, outputKind: resolved.outputKind)
            applySnapshots(scoutSnapshots, to: &run)
            merge(scoutAnswers, into: &run)
            if let out = scoutAnswers.first, out.hasAnswer, let text = out.output, !text.isEmpty {
                let label = scout.skillName ?? scout.skillId ?? "scout"
                downstreamPrompt = prompt + "\n\n# Source (distilled by \(label))\n\n" + text
            }
            persist?(run)
        }

        // ARA-S04: detect repo shape once, append brief so every AI Readiness seat
        // (answer, review, writer) gets shape-specific questions. Detection runs
        // once per run, not per seat — shape is a repo-level fingerprint.
        if resolved.outputKind == .aiReadinessReport, let repoRoot {
            let fp = AIReadinessShape.detect(at: URL(fileURLWithPath: repoRoot))
            downstreamPrompt += "\n\n" + AIReadinessShape.brief(for: fp)
        }

        // Stage 1 — answer workers, blind and parallel, over the distilled source.
        // Each seat gets its own founder prompt when `workerPrompts[worker.id]` is set
        // (Panel); otherwise the shared downstream prompt (existing answer teams).
        let (answers, answerSnapshots) = await runWorkers(
            resolved.answerWorkers, prompt: downstreamPrompt, effort: resolved.effort,
            modelByID: modelByID, run: &run, repoRoot: repoRoot, deliveries: deliveries,
            workerPrompts: workerPrompts, workerWorkingDirectories: workerWorkingDirectories,
            persist: persist, team: team, lane: lane, reseatPool: models,
            outputKind: resolved.outputKind)
        applySnapshots(answerSnapshots, to: &run)
        merge(answers, into: &run)
        persist?(run)

        // Stage 2 — review workers run after answers and may see them.
        if !resolved.reviewWorkers.isEmpty {
            let reviewPrompt = downstreamPrompt + "\n\n# Agent answers so far\n\n" + answersBlock(answers, workers: resolved.answerWorkers)
            let (reviews, reviewSnapshots) = await runWorkers(
                resolved.reviewWorkers, prompt: reviewPrompt, effort: resolved.effort,
                modelByID: modelByID, run: &run, repoRoot: repoRoot, deliveries: deliveries,
                workerPrompts: nil, workerWorkingDirectories: workerWorkingDirectories,
                persist: persist, team: team, lane: lane, reseatPool: models,
                outputKind: resolved.outputKind)
            applySnapshots(reviewSnapshots, to: &run)
            merge(reviews, into: &run)
            persist?(run)
        }

        run = transition(run, to: .answersIn)

        // Design lane (DL-S02) — after answer seats, host WebKit captures each
        // seat's HTML/SVG into board.options[].imagePath. Never imageGen.
        if resolved.outputKind == .designBoard {
            let boardStarted = now()
            let board: BoardPayload
            if let runDirectory {
                try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
                board = await DesignBoardCapture.captureBoard(
                    answerWorkers: resolved.answerWorkers,
                    answers: answers,
                    runDirectory: runDirectory
                )
            } else {
                board = BoardPayload(
                    targetShape: .desktop,
                    options: resolved.answerWorkers.map {
                        DesignOption(
                            agentId: $0.id,
                            modelId: $0.modelId,
                            persona: $0.skillId ?? "design",
                            status: .failed,
                            failureReason: "no run directory for Design board capture"
                        )
                    }
                )
            }
            let boardStage = StageOutput(
                id: idFactory(),
                purpose: .board,
                status: .done,
                payload: .board(board),
                startedAt: boardStarted,
                finishedAt: now()
            )
            run.stages.append(boardStage)
            emitStage(RunEventKind.stageCompleted, runId: run.id, stageId: boardStage.id, workerId: "", purpose: "board")
            persist?(run)
        }

        // Stage 3 — synthetic plan/output writer runs last and preserves dissent.
        // Solo answer teams (`code_doc_review`) skip synthesis — the one worker's
        // markdown is the final output.
        if team?.isSoloAnswerTeam == true,
           let workerId = resolved.answerWorkers.first?.id,
           let answer = run.answers.first(where: { $0.memberId == workerId }),
           answer.hasAnswer,
           let markdown = answer.output,
           !markdown.isEmpty {
            run = transition(run, to: .planning)
            persist?(run)
            let startedAt = now()
            let stageId = idFactory()
            let stage = StageOutput(
                id: stageId, purpose: .plan, status: .done,
                payload: .plan(markdown: markdown), startedAt: startedAt, finishedAt: now())
            run.stages.append(stage)
            run = transition(run, to: .complete)
        } else if let writer = resolved.planWriter, !run.answeredWorkers.isEmpty {
            run = transition(run, to: .planning)
            persist?(run)
            let (stage, writerSnapshot, settledWriter) = await runWriter(
                writer, resolved: resolved, run: run, basePrompt: downstreamPrompt,
                modelByID: modelByID, repoRoot: repoRoot, team: team, reseatPool: models)
            if let writerSnapshot { applySnapshots([settledWriter.id: writerSnapshot], to: &run) }
            if let wi = run.workers.firstIndex(where: { $0.id == settledWriter.id }) {
                run.workers[wi] = settledWriter
            }
            run.stages.append(stage)
            run = transition(run, to: stage.status == StageStatus.done ? .complete : .partial)
        } else {
            run = transition(run, to: .planning)
            run = transition(run, to: .partial)
        }
        // Actor that ends the run stamps endReason (never inferred later).
        if run.status.isTerminal, run.endReason == nil {
            switch run.status {
            case .complete, .partial, .done: run.endReason = .completed
            case .failed: run.endReason = .failed
            case .timedOut: run.endReason = .timedOut
            case .cancelled: run.endReason = .cancelled
            default: run.endReason = .unknown
            }
        }
        persist?(run) // terminal — clears the liveness marker

        continuation.finish()
        return run
    }

    // MARK: - Stages

    private func runWorkers(
        _ workers: [Agent],
        prompt: String,
        effort: EffortLevel,
        modelByID: [String: Model],
        run: inout TeamRun,
        repoRoot: String?,
        deliveries: [IncludedAttachmentDelivery] = [],
        workerPrompts: [String: String]? = nil,
        workerWorkingDirectories: [String: String]? = nil,
        persist: (@Sendable (TeamRun) -> Void)? = nil,
        team: TeamPreset? = nil,
        lane: WorkLane = .code,
        reseatPool: [Model] = [],
        outputKind: TeamOutputKind? = nil
    ) async -> (answers: [TeamAnswer], snapshots: [String: String]) {
        var snapshots: [String: String] = [:]
        let runId = run.id
        for agent in workers {
            if let index = run.answers.firstIndex(where: { $0.memberId == agent.id }) {
                run.answers[index].result.status = .running
                run.answers[index].result.timing.startedAt = now()
            }
            emitWorker(workerId: agent.id, modelId: agent.modelId, from: .queued, to: .running, skillId: agent.skillId, runId: runId)
        }
        persist?(run)
        let runner = workerRunner
        let registry = self.registry
        let pool = reseatPool.isEmpty ? Array(modelByID.values) : reseatPool
        let answers = await withTaskGroup(of: (TeamAnswer, String?).self) { group in
            for agent in workers {
                let model = modelByID[agent.modelId]
                let manifest = model.flatMap { registry.manifest(for: $0) }
                let role = agent.purpose?.rawValue ?? AgentStage.answer.rawValue
                let founderPrompt = workerPrompts?[agent.id] ?? prompt
                let baseWorkerPrompt = SkillCatalog.assemblePrompt(
                    skillId: agent.skillId,
                    founderPrompt: founderPrompt,
                    outputKind: outputKind
                )
                let workerPrompt = deliveries.isEmpty ? baseWorkerPrompt
                    : TeamRunAttachmentMapper.teamRunSeatPrompt(
                        basePrompt: baseWorkerPrompt,
                        deliveries: deliveries,
                        readsImages: model?.canReadImages(manifest: manifest) ?? false)
                snapshots[agent.id] = workerPrompt
                let workingDirectory = workerWorkingDirectories?[agent.id] ?? repoRoot
                group.addTask {
                    guard let model else {
                        return (TeamAnswer(memberId: agent.id, modelId: agent.modelId, role: role,
                                          result: WorkerRunResult(status: .failed, errorKind: .missingCLI,
                                                                  errorReason: "no model for agent \(agent.id)")), nil)
                    }
                    guard let manifest else {
                        return (TeamAnswer(memberId: agent.id, modelId: agent.modelId, role: role,
                                          result: WorkerRunResult(status: .failed, errorKind: .missingCLI,
                                                                  errorReason: "no driver manifest for \(model.driverId)")), nil)
                    }
                    // RLR-S04a: stamp the worker id task-local around the spawn so
                    // the process-group leader records its runtimeOwnership keyed by
                    // this worker id (captured synchronously into the spawn).
                    var result = await ProcessOwnership.$currentWorkerId.withValue(agent.id) {
                        await runner.collect(WorkerInvocation(
                            model: model, manifest: manifest, prompt: workerPrompt, effort: effort,
                            workingDirectory: workingDirectory))
                    }
                    var settledModel = model
                    var substitutedFrom: String? = agent.substitutedFromModelId
                    if let team, agent.seatingReason != TeamExplicitSeats.explicitSeatingReason {
                        let chain = SeatReseat.chain(for: agent, team: team, isLead: false)
                        if SeatReseat.isEligible(
                            result,
                            hasDeclaredFallbacks: SeatReseat.allowsSubstitute(
                                fallbacks: chain.fallbacks, policy: chain.policy)
                        ) {
                            if let alt = SeatReseat.nextModel(
                                failedModelId: settledModel.id,
                                failedDriverId: settledModel.driverId,
                                preferredModelId: chain.preferred,
                                fallbackModelIds: chain.fallbacks,
                                requiredTags: chain.tags,
                                fallback: chain.policy,
                                lane: lane,
                                ready: pool,
                                preferredTags: chain.preferredTags
                            ), let altManifest = registry.manifest(for: alt) {
                                substitutedFrom = substitutedFrom ?? settledModel.id
                                settledModel = alt
                                let altPrompt = deliveries.isEmpty ? baseWorkerPrompt
                                    : TeamRunAttachmentMapper.teamRunSeatPrompt(
                                        basePrompt: baseWorkerPrompt,
                                        deliveries: deliveries,
                                        readsImages: alt.canReadImages(manifest: altManifest))
                                result = await ProcessOwnership.$currentWorkerId.withValue(agent.id) {
                                    await runner.collect(WorkerInvocation(
                                        model: alt, manifest: altManifest, prompt: altPrompt, effort: effort,
                                        workingDirectory: workingDirectory))
                                }
                            }
                        }
                    }
                    return (TeamAnswer(memberId: agent.id, modelId: settledModel.id, role: role, result: result),
                            substitutedFrom)
                }
            }
            var collected: [TeamAnswer] = []
            var abandonedToSandbox = false
            for await (answer, substitutedFrom) in group {
                // Fail fast on the first seat the host's sandbox refuses to start.
                //
                // Measured 2026-07-25: a three-seat team inside Codex knew at 1.2s
                // that two seats could not start, then waited another 63s for the
                // one seat that could — and the whole run was handed to the app and
                // re-run anyway. The caller paid 64s for a result that was discarded.
                // Cancelling here costs ~1s instead, and `ProcessGroupCommandRunner`
                // terminates the in-flight process groups on cancel, so nothing is
                // left running behind us.
                //
                // Gated by the same `CODEX_SANDBOX` guard as every other sandbox
                // decision: outside a restricted host this never fires, and a
                // restricted host with full access never produces the signature.
                if !abandonedToSandbox,
                   answer.result.status == .failed,
                   HostSandboxAdvice.detect(
                       workerFailureText: [answer.result.errorReason].compactMap { $0 },
                       prompt: run.prompt,
                       projectReference: run.repoRoot,
                       teamId: run.presetId,
                       capacityAuthRequired: answer.result.capacityObservation?.kind == .authRequired
                   ) != nil {
                    abandonedToSandbox = true
                    group.cancelAll()
                }
                emitWorker(workerId: answer.memberId, modelId: answer.modelId, from: .running, to: answer.result.status,
                           skillId: nil, durationMs: answer.result.timing.durationMs, reason: answer.result.errorReason, runId: runId)
                if let index = run.answers.firstIndex(where: { $0.memberId == answer.memberId }) {
                    run.answers[index] = answer
                    persist?(run)
                }
                if let wi = run.workers.firstIndex(where: { $0.id == answer.memberId }) {
                    run.workers[wi].modelId = answer.modelId
                    if let substitutedFrom {
                        run.workers[wi].substitutedFromModelId = substitutedFrom
                    }
                }
                collected.append(answer)
            }
            return collected
        }
        return (answers, snapshots)
    }

    private func runWriter(
        _ writer: Agent,
        resolved: ResolvedTeamRun,
        run: TeamRun,
        basePrompt: String,
        modelByID: [String: Model],
        repoRoot: String?,
        team: TeamPreset? = nil,
        reseatPool: [Model] = []
    ) async -> (stage: StageOutput, promptSnapshot: String?, writer: Agent) {
        let stageId = idFactory()
        let startedAt = now()
        emitStage(RunEventKind.stageStarted, runId: run.id, stageId: stageId, workerId: writer.id)
        var writer = writer

        func fail(_ reason: String) -> (StageOutput, String?, Agent) {
            emitStage(RunEventKind.stageFailed, runId: run.id, stageId: stageId, workerId: writer.id)
            return (StageOutput(id: stageId, purpose: .plan, producedByAgentId: writer.id,
                               promptProfileId: writer.skillId, status: .failed,
                               errorReason: reason, startedAt: startedAt, finishedAt: now()), nil, writer)
        }

        guard var model = modelByID[writer.modelId],
              var manifest = registry.manifest(for: model),
              manifest.kind == .headlessCLI else {
            return fail("plan/output writer model unavailable")
        }
        let writerPrompt = SkillCatalog.assemblePrompt(
            skillId: writer.skillId,
            founderPrompt: writerInput(resolved: resolved, run: run, basePrompt: basePrompt))
        var outcome = await ProcessOwnership.$currentWorkerId.withValue(writer.id) {
            await workerRunner.collect(WorkerInvocation(
                model: model, manifest: manifest, prompt: writerPrompt, effort: resolved.effort,
                workingDirectory: repoRoot))
        }
        if let team, writer.seatingReason != TeamExplicitSeats.explicitSeatingReason {
            let chain = SeatReseat.chain(for: writer, team: team, isLead: true)
            if SeatReseat.isEligible(
                outcome,
                hasDeclaredFallbacks: SeatReseat.allowsSubstitute(
                    fallbacks: chain.fallbacks, policy: chain.policy)
            ) {
                let pool = reseatPool.isEmpty ? Array(modelByID.values) : reseatPool
                if let alt = SeatReseat.nextModel(
                    failedModelId: model.id,
                    failedDriverId: model.driverId,
                    preferredModelId: chain.preferred,
                    fallbackModelIds: chain.fallbacks,
                    requiredTags: chain.tags,
                    fallback: chain.policy,
                    lane: team.lane,
                    ready: pool,
                    preferredTags: chain.preferredTags
                ), let altManifest = registry.manifest(for: alt), altManifest.kind == .headlessCLI {
                    writer.substitutedFromModelId = writer.substitutedFromModelId ?? model.id
                    writer.modelId = alt.id
                    model = alt
                    manifest = altManifest
                    outcome = await ProcessOwnership.$currentWorkerId.withValue(writer.id) {
                        await workerRunner.collect(WorkerInvocation(
                            model: alt, manifest: altManifest, prompt: writerPrompt, effort: resolved.effort,
                            workingDirectory: repoRoot))
                    }
                }
            }
        }
        guard outcome.status == .done, let markdown = outcome.output, !markdown.isEmpty else {
            return fail(outcome.errorReason ?? "plan writer produced no output")
        }
        emitStage(RunEventKind.stageCompleted, runId: run.id, stageId: stageId, workerId: writer.id)
        return (StageOutput(id: stageId, purpose: .plan, producedByAgentId: writer.id,
                           promptProfileId: writer.skillId, status: .done,
                           payload: .plan(markdown: markdown), startedAt: startedAt, finishedAt: now()),
                writerPrompt, writer)
    }

    // MARK: - Prompt assembly

    private func answersBlock(_ answers: [TeamAnswer], workers: [Agent]) -> String {
        let nameById = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return answers.map { a in
            let w = nameById[a.memberId]
            let label = "\(w?.skillName ?? w?.skillId ?? a.memberId)"
            if a.hasAnswer, let out = a.output {
                return "## \(label)\n\n\(out)"
            }
            return "## \(label)\n\n_(\(a.result.status.rawValue): \(a.result.errorReason ?? "no answer"))_"
        }.joined(separator: "\n\n")
    }

    /// The writer sees the prompt, the answers, the reviews, and a dissent
    /// instruction derived from the synthesis policy.
    private func writerInput(resolved: ResolvedTeamRun, run: TeamRun, basePrompt: String) -> String {
        let answerIds = Set(resolved.answerWorkers.map(\.id))
        let reviewIds = Set(resolved.reviewWorkers.map(\.id))
        let answers = run.answers.filter { answerIds.contains($0.memberId) }
        let reviews = run.answers.filter { reviewIds.contains($0.memberId) }
        // basePrompt carries the scout-distilled source so the Lead sees it too.
        var parts = [basePrompt, "# Agent answers\n\n" + answersBlock(answers, workers: resolved.answerWorkers)]
        if !reviews.isEmpty {
            parts.append("# Reviews\n\n" + answersBlock(reviews, workers: resolved.reviewWorkers))
        }
        parts.append(dissentInstruction(resolved.dissentPolicy))
        return parts.joined(separator: "\n\n")
    }

    private func dissentInstruction(_ policy: DissentPolicy) -> String {
        switch policy {
        case .preserveDissent:
            return "Preserve genuine dissent. Decide, but do not flatten disagreement; record minority positions."
        case .compareOptions:
            return "Present the distinct options side by side with their tradeoffs, then recommend one."
        case .riskRegister:
            return "Output a prioritized risk register: each item with severity, owner, and any required stop."
        }
    }

    // MARK: - Run plumbing

    private func merge(_ answers: [TeamAnswer], into run: inout TeamRun) {
        for answer in answers {
            if let i = run.answers.firstIndex(where: { $0.memberId == answer.memberId }) {
                run.answers[i] = answer
            }
        }
    }

    private func applySnapshots(_ snapshots: [String: String], to run: inout TeamRun) {
        for i in run.workers.indices {
            if let snap = snapshots[run.workers[i].id] {
                run.workers[i].resolvedWorkerPromptSnapshot = snap
            }
        }
    }

    private func nextSeq() -> Int64 { seq += 1; return seq }

    /// Atomic rule (RLR-L3): status + phase change in the SAME journal revision.
    /// Terminal transitions clear `phase`; a nil `phase` on a non-terminal
    /// transition keeps the prior phase.
    private func transition(_ run: TeamRun, to next: RunStatus, phase: RunPhase? = nil) -> TeamRun {
        guard run.canTransition(to: next) else { return run }
        var updated = run
        let from = updated.status
        updated.status = next
        updated.phase = next.isTerminal ? nil : (phase ?? updated.phase)
        var payload: [String: JSONValue] = [
            "runId": .string(updated.id), "from": .string(from.rawValue),
            "to": .string(next.rawValue), "origin": .string(updated.origin.rawValue)
        ]
        if let presetId = updated.presetId { payload["presetId"] = .string(presetId) }
        continuation.yield(RunEvent(id: idFactory(), seq: nextSeq(), ts: now(),
                                    kind: RunEventKind.runStatusChanged, payload: payload))
        return updated
    }

    private func emitWorker(workerId: String, modelId: String, from: WorkerAnswerStatus, to: WorkerAnswerStatus,
                            skillId: String?, durationMs: Int? = nil, reason: String? = nil, runId: String) {
        var payload: [String: JSONValue] = [
            "runId": .string(runId), "workerId": .string(workerId), "modelId": .string(modelId),
            "from": .string(from.rawValue), "to": .string(to.rawValue)
        ]
        if let skillId { payload["skillId"] = .string(skillId) }
        if let durationMs { payload["durationMs"] = .int(durationMs) }
        if let reason { payload["reason"] = .string(reason) }
        continuation.yield(RunEvent(id: idFactory(), seq: nextSeq(), ts: now(),
                                    kind: RunEventKind.workerStatusChanged, payload: payload))
    }

    private func emitStage(_ kind: String, runId: String, stageId: String, workerId: String, purpose: String = "plan") {
        continuation.yield(RunEvent(id: idFactory(), seq: nextSeq(), ts: now(), kind: kind, payload: [
            "runId": .string(runId), "purpose": .string(purpose), "stageId": .string(stageId), "workerId": .string(workerId)
        ]))
    }
}

