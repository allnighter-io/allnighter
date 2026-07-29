import Foundation
import AllnighterCore
import AgentOSTeam

/// Owns one team run: builds per-worker prompts, runs every worker in
/// parallel, updates the run, and emits `RunEvent`s keyed by worker id.
public actor TeamRunCoordinator {
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

    public func runTeam(
        prompt: String,
        teamWorkers: [Agent],
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
                TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? AgentStage.answer.rawValue,
                          result: WorkerRunResult(status: .queued))
            },
            createdAt: now()
        )

        // RLR-L3: one worker never fans out — mint `running`/`working` instead.
        if teamWorkers.count <= 1 {
            run = transition(run, to: .running, phase: .working)
        } else {
            run = transition(run, to: .fanningOut, phase: .working)
        }

        let skillByWorker = Dictionary(teamWorkers.map { ($0.id, $0.skillId) }, uniquingKeysWith: { a, _ in a })

        for index in run.workerAnswers.indices where run.workerAnswers[index].result.status == .queued {
            run.workerAnswers[index].result.status = .running
            run.workerAnswers[index].result.timing.startedAt = now()
            let id = run.workerAnswers[index].memberId
            emitWorkerAnswer(run.workerAnswers[index], runId: run.id, from: .queued, skillId: skillByWorker[id] ?? nil)
        }

        let runnerCopy = workerRunner
        let manifestByModel = Dictionary(
            uniqueKeysWithValues: models.map { ($0.id, registry.manifest(for: $0)) }
        )

        let results: [TeamAnswer] = await withTaskGroup(of: TeamAnswer.self) { group in
            for assignment in teamWorkers {
                let model = modelByID[assignment.modelId]
                let manifest = model.flatMap { manifestByModel[$0.id] ?? nil }
                let workerPrompt = SkillCatalog.assemblePrompt(
                    skillId: assignment.skillId,
                    founderPrompt: prompt
                )
                let role = assignment.purpose?.rawValue ?? AgentStage.answer.rawValue
                group.addTask {
                    guard let model else {
                        return TeamAnswer(
                            memberId: assignment.id, modelId: assignment.modelId, role: role,
                            result: WorkerRunResult(status: .failed, errorKind: .missingCLI,
                                                    errorReason: "no model for worker \(assignment.id)")
                        )
                    }
                    guard let manifest else {
                        return TeamAnswer(
                            memberId: assignment.id, modelId: assignment.modelId, role: role,
                            result: WorkerRunResult(status: .failed, errorKind: .missingCLI,
                                                    errorReason: "no driver manifest for \(model.driverId)")
                        )
                    }
                    let result = await runnerCopy.collect(
                        WorkerInvocation(model: model, manifest: manifest, prompt: workerPrompt)
                    )
                    return TeamAnswer(memberId: assignment.id, modelId: model.id, role: role, result: result)
                }
            }

            var collected: [TeamAnswer] = []
            for await response in group { collected.append(response) }
            return collected
        }

        for result in results {
            if let index = run.workerAnswers.firstIndex(where: { $0.memberId == result.memberId }) {
                let previous = run.workerAnswers[index].result.status
                run.workerAnswers[index] = result
                emitWorkerAnswer(result, runId: run.id, from: previous, skillId: skillByWorker[result.memberId] ?? nil)
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

    /// Atomic rule (RLR-L3): status + phase in the SAME revision; terminal clears phase.
    private func transition(_ run: TeamRun, to next: RunStatus, phase: RunPhase? = nil) -> TeamRun {
        guard run.canTransition(to: next) else { return run }
        var updated = run
        let from = updated.status
        updated.status = next
        updated.phase = next.isTerminal ? nil : (phase ?? updated.phase)
        var payload: [String: JSONValue] = [
            "runId": .string(updated.id),
            "from": .string(from.rawValue),
            "to": .string(next.rawValue),
            "origin": .string(updated.origin.rawValue),
        ]
        if let presetId = updated.presetId { payload["presetId"] = .string(presetId) }
        continuation.yield(RunEvent(
            id: idFactory(),
            seq: nextSeq(),
            ts: now(),
            kind: RunEventKind.runStatusChanged,
            payload: payload
        ))
        return updated
    }

    private func emitWorkerAnswer(_ answer: TeamAnswer, runId: String, from: WorkerAnswerStatus, skillId: String?) {
        var payload: [String: JSONValue] = [
            "runId": .string(runId),
            "workerId": .string(answer.memberId),
            "modelId": .string(answer.modelId),
            "from": .string(from.rawValue),
            "to": .string(answer.result.status.rawValue),
        ]
        if let skillId { payload["skillId"] = .string(skillId) }
        if let durationMs = answer.result.timing.durationMs { payload["durationMs"] = .int(durationMs) }
        if let reason = answer.result.errorReason { payload["reason"] = .string(reason) }
        continuation.yield(RunEvent(
            id: idFactory(),
            seq: nextSeq(),
            ts: now(),
            kind: RunEventKind.workerStatusChanged,
            payload: payload
        ))
    }
}
