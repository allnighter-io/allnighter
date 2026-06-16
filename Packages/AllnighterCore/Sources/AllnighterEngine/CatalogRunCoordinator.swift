import Foundation
import AllnighterCore

/// Runs a resolved lane-team in the fixed catalog staging order:
/// **answer (blind, parallel) → review (sees answers) → output writer (sees
/// everything, preserves dissent)**. Not a generic DAG (Fanout_Team_Catalog §S05).
/// Reuses `WorkerRunner`; emits `RunEvent`s for the live `--stream` projection.
public actor CatalogRunCoordinator {
    private let workerRunner: WorkerRunner
    private let registry: DriverRegistry
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    private var seq: Int64 = 0
    private let continuation: AsyncStream<RunEvent>.Continuation
    public nonisolated let events: AsyncStream<RunEvent>

    public init(
        workerRunner: WorkerRunner,
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
    /// (question + bounded context). Returns the settled `TeamRun`.
    public func run(
        resolved: ResolvedTeamRun,
        prompt: String,
        models: [Model],
        origin: RunOrigin = .cli,
        originAgent: String? = nil,
        runId: String? = nil
    ) async -> TeamRun {
        let modelByID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let answerAndReview = resolved.answerWorkers + resolved.reviewWorkers

        var run = TeamRun(
            id: runId ?? idFactory(),
            prompt: prompt,
            status: .draft,
            origin: origin,
            originAgent: originAgent,
            presetId: resolved.teamPresetId,
            workers: resolved.allWorkers,
            workerAnswers: answerAndReview.map { WorkerAnswer(workerId: $0.id, modelId: $0.modelId, status: .queued) },
            createdAt: now()
        )
        run = transition(run, to: .fanningOut)

        // Stage 1 — answer workers, blind and parallel.
        let answers = await runWorkers(resolved.answerWorkers, prompt: prompt, modelByID: modelByID, runId: run.id)
        merge(answers, into: &run)

        // Stage 2 — review workers run after answers and may see them.
        if !resolved.reviewWorkers.isEmpty {
            let reviewPrompt = prompt + "\n\n# Worker answers so far\n\n" + answersBlock(answers, workers: resolved.answerWorkers)
            let reviews = await runWorkers(resolved.reviewWorkers, prompt: reviewPrompt, modelByID: modelByID, runId: run.id)
            merge(reviews, into: &run)
        }

        run = transition(run, to: .answersIn)

        // Stage 3 — synthetic plan/output writer runs last and preserves dissent.
        // Runs when a writer resolved and at least one worker produced output.
        if let writer = resolved.planWriter, !run.answeredWorkers.isEmpty {
            run = transition(run, to: .planning)
            let stage = await runWriter(writer, resolved: resolved, run: run, modelByID: modelByID)
            run.stages.append(stage)
            run = transition(run, to: stage.status == .done ? .complete : .partial)
        } else {
            run = transition(run, to: .planning)
            run = transition(run, to: .partial)
        }

        continuation.finish()
        return run
    }

    // MARK: - Stages

    private func runWorkers(_ workers: [Worker], prompt: String, modelByID: [String: Model], runId: String) async -> [WorkerAnswer] {
        for worker in workers {
            emitWorker(workerId: worker.id, modelId: worker.modelId, from: .queued, to: .running, skillId: worker.skillId, runId: runId)
        }
        let runner = workerRunner
        let registry = self.registry
        return await withTaskGroup(of: WorkerAnswer.self) { group in
            for worker in workers {
                let model = modelByID[worker.modelId]
                let manifest = model.flatMap { registry.manifest(for: $0) }
                let workerPrompt = SkillCatalog.assemblePrompt(skillId: worker.skillId, founderPrompt: prompt)
                group.addTask {
                    guard let model else {
                        return WorkerAnswer(workerId: worker.id, modelId: worker.modelId, status: .failed,
                                            errorKind: .missingCLI, errorReason: "no model for worker \(worker.id)")
                    }
                    guard let manifest else {
                        return WorkerAnswer(workerId: worker.id, modelId: worker.modelId, status: .failed,
                                            errorKind: .missingCLI, errorReason: "no driver manifest for \(model.driverId)")
                    }
                    return await runner.run(assignment: worker, model: model, manifest: manifest, prompt: workerPrompt)
                }
            }
            var collected: [WorkerAnswer] = []
            for await answer in group {
                emitWorker(workerId: answer.workerId, modelId: answer.modelId, from: .running, to: answer.status,
                           skillId: nil, durationMs: answer.durationMs, reason: answer.errorReason, runId: runId)
                collected.append(answer)
            }
            return collected
        }
    }

    private func runWriter(_ writer: Worker, resolved: ResolvedTeamRun, run: TeamRun, modelByID: [String: Model]) async -> StageOutput {
        let stageId = idFactory()
        let startedAt = now()
        emitStage(RunEventKind.stageStarted, runId: run.id, stageId: stageId, workerId: writer.id)

        func fail(_ reason: String) -> StageOutput {
            emitStage(RunEventKind.stageFailed, runId: run.id, stageId: stageId, workerId: writer.id)
            return StageOutput(id: stageId, purpose: .plan, producedByWorkerId: writer.id,
                               promptProfileId: writer.skillId, status: .failed,
                               errorReason: reason, startedAt: startedAt, finishedAt: now())
        }

        guard let model = modelByID[writer.modelId], let manifest = registry.manifest(for: model), manifest.kind == .headlessCLI else {
            return fail("plan/output writer model unavailable")
        }
        let writerPrompt = SkillCatalog.assemblePrompt(skillId: writer.skillId, founderPrompt: writerInput(resolved: resolved, run: run))
        let outcome = await workerRunner.invoke(worker: model, manifest: manifest, prompt: writerPrompt)
        guard outcome.status == .done, let markdown = outcome.output, !markdown.isEmpty else {
            return fail(outcome.errorReason ?? "plan writer produced no output")
        }
        emitStage(RunEventKind.stageCompleted, runId: run.id, stageId: stageId, workerId: writer.id)
        return StageOutput(id: stageId, purpose: .plan, producedByWorkerId: writer.id,
                           promptProfileId: writer.skillId, status: .done,
                           payload: .plan(markdown: markdown), startedAt: startedAt, finishedAt: now())
    }

    // MARK: - Prompt assembly

    private func answersBlock(_ answers: [WorkerAnswer], workers: [Worker]) -> String {
        let nameById = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return answers.map { a in
            let w = nameById[a.workerId]
            let label = "\(w?.skillName ?? w?.skillId ?? a.workerId)"
            if a.hasAnswer, let out = a.output {
                return "## \(label)\n\n\(out)"
            }
            return "## \(label)\n\n_(\(a.status.rawValue): \(a.errorReason ?? "no answer"))_"
        }.joined(separator: "\n\n")
    }

    /// The writer sees the prompt, the answers, the reviews, and a dissent
    /// instruction derived from the synthesis policy.
    private func writerInput(resolved: ResolvedTeamRun, run: TeamRun) -> String {
        let answerIds = Set(resolved.answerWorkers.map(\.id))
        let reviewIds = Set(resolved.reviewWorkers.map(\.id))
        let answers = run.workerAnswers.filter { answerIds.contains($0.workerId) }
        let reviews = run.workerAnswers.filter { reviewIds.contains($0.workerId) }
        var parts = [run.prompt, "# Worker answers\n\n" + answersBlock(answers, workers: resolved.answerWorkers)]
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

    private func merge(_ answers: [WorkerAnswer], into run: inout TeamRun) {
        for answer in answers {
            if let i = run.workerAnswers.firstIndex(where: { $0.workerId == answer.workerId }) {
                run.workerAnswers[i] = answer
            }
        }
    }

    private func nextSeq() -> Int64 { seq += 1; return seq }

    private func transition(_ run: TeamRun, to next: RunStatus) -> TeamRun {
        guard run.canTransition(to: next) else { return run }
        var updated = run
        let from = updated.status
        updated.status = next
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

    private func emitStage(_ kind: String, runId: String, stageId: String, workerId: String) {
        continuation.yield(RunEvent(id: idFactory(), seq: nextSeq(), ts: now(), kind: kind, payload: [
            "runId": .string(runId), "purpose": .string("plan"), "stageId": .string(stageId), "workerId": .string(workerId)
        ]))
    }
}

