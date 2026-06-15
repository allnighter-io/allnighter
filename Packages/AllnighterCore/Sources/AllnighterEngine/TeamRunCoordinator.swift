import Foundation
import AllnighterCore

/// Owns one team run's fan-out: builds per-worker prompts, runs every worker in
/// parallel, updates the run, and emits `RunEvent`s keyed by worker id.
public actor TeamRunCoordinator {
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

    public func fanOut(
        prompt: String,
        teamWorkers: [Worker],
        models: [Model],
        origin: RunOrigin = .gui,
        originAgent: String? = nil,
        presetId: String? = nil,
        runId: String? = nil
    ) async -> TeamRun {
        let modelByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        var run = TeamRun(
            id: runId ?? idFactory(),
            prompt: prompt,
            status: .draft,
            origin: origin,
            originAgent: originAgent,
            presetId: presetId,
            workers: teamWorkers,
            workerAnswers: teamWorkers.map {
                WorkerAnswer(workerId: $0.id, modelId: $0.modelId, status: .queued)
            },
            createdAt: now()
        )

        run = transition(run, to: .fanningOut)

        for index in run.workerAnswers.indices where run.workerAnswers[index].status == .queued {
            run.workerAnswers[index].status = .running
            run.workerAnswers[index].startedAt = now()
            emitWorkerAnswer(run.workerAnswers[index], runId: run.id, from: .queued)
        }

        let runnerCopy = workerRunner
        let manifestByModel = Dictionary(
            uniqueKeysWithValues: models.map { ($0.id, registry.manifest(for: $0)) }
        )

        let results: [WorkerAnswer] = await withTaskGroup(of: WorkerAnswer.self) { group in
            for assignment in teamWorkers {
                let model = modelByID[assignment.modelId]
                let manifest = model.flatMap { manifestByModel[$0.id] ?? nil }
                let workerPrompt = SkillLibrary.assemblePrompt(
                    skillId: assignment.skillId,
                    founderPrompt: prompt
                )
                group.addTask {
                    guard let model else {
                        return WorkerAnswer(
                            workerId: assignment.id,
                            modelId: assignment.modelId,
                            status: .failed,
                            errorKind: .missingCLI,
                            errorReason: "no model for worker \(assignment.id)"
                        )
                    }
                    guard let manifest else {
                        return WorkerAnswer(
                            workerId: assignment.id,
                            modelId: assignment.modelId,
                            status: .failed,
                            errorKind: .missingCLI,
                            errorReason: "no driver manifest for \(model.driverId)"
                        )
                    }
                    return await runnerCopy.run(
                        assignment: assignment,
                        model: model,
                        manifest: manifest,
                        prompt: workerPrompt
                    )
                }
            }

            var collected: [WorkerAnswer] = []
            for await response in group { collected.append(response) }
            return collected
        }

        for result in results {
            if let index = run.workerAnswers.firstIndex(where: { $0.workerId == result.workerId }) {
                let previous = run.workerAnswers[index].status
                run.workerAnswers[index] = result
                emitWorkerAnswer(result, runId: run.id, from: previous)
            }
        }

        if Task.isCancelled {
            run = transition(run, to: .cancelled)
        } else {
            run = transition(run, to: .answersIn)
        }

        continuation.finish()
        return run
    }

    private func nextSeq() -> Int64 {
        seq += 1
        return seq
    }

    private func transition(_ run: TeamRun, to next: RunStatus) -> TeamRun {
        guard run.canTransition(to: next) else { return run }
        var updated = run
        let from = updated.status
        updated.status = next
        continuation.yield(RunEvent(
            id: idFactory(),
            seq: nextSeq(),
            ts: now(),
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(updated.id),
                "from": .string(from.rawValue),
                "to": .string(next.rawValue)
            ]
        ))
        return updated
    }

    private func emitWorkerAnswer(_ answer: WorkerAnswer, runId: String, from: WorkerAnswerStatus) {
        continuation.yield(RunEvent(
            id: idFactory(),
            seq: nextSeq(),
            ts: now(),
            kind: RunEventKind.memberStatusChanged,
            payload: [
                "runId": .string(runId),
                "workerId": .string(answer.workerId),
                "modelId": .string(answer.modelId),
                "from": .string(from.rawValue),
                "to": .string(answer.status.rawValue)
            ]
        ))
    }
}
