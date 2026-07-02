import Foundation
import AllnighterCore
import AgentOSTeam

/// Owns one design run's parallel image generation (Lane 2). Mirrors `TeamRunCoordinator`:
/// builds per-seat image requests (one image worker × one design persona), runs
/// every seat in parallel via `DesignImageRunner`, writes each image into the run
/// folder, and emits `RunEvent`s keyed by `workerId` so the board reveals
/// progressively. The board (`BoardPayload`) is the first truth surface — no AI
/// verdict precedes it. The unit is a generated image; OCR and HTML rendering are
/// dead. See `docs/mvp/Design1`.
public actor DesignCoordinator {
    private let imageRunner: DesignImageRunner
    private let registry: DriverRegistry
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    private var seq: Int64 = 0
    private let continuation: AsyncStream<RunEvent>.Continuation
    public nonisolated let events: AsyncStream<RunEvent>

    public init(
        imageRunner: DesignImageRunner,
        registry: DriverRegistry,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.imageRunner = imageRunner
        self.registry = registry
        self.idFactory = idFactory
        self.now = now
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        self.events = stream
        self.continuation = continuation
    }

    /// Runs the design request across `teamWorkers`, writing images into `runDir`,
    /// and returns the settled run carrying the `board` stage. A failed seat is a
    /// gray tile, never a blocked board: the run is `complete` if every seat
    /// rendered, `partial` if some failed but ≥1 rendered, `failed` if none did.
    /// `screenshotAbsolutePath` is the on-disk path the engines read; the board
    /// stores the run-relative `request.screenshotPath` for the before/after toggle.
    public func generate(
        request: DesignRequest,
        teamWorkers: [Worker],
        models: [Model],
        runDir: URL,
        screenshotAbsolutePath: String? = nil,
        runId: String? = nil
    ) async -> TeamRun {
        let modelByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let manifestByModel = Dictionary(uniqueKeysWithValues: models.map { ($0.id, registry.manifest(for: $0)) })

        var run = TeamRun(
            id: runId ?? idFactory(),
            prompt: request.prompt,
            status: .draft,
            origin: .gui,
            presetId: "design_board",
            workers: teamWorkers,
            workerAnswers: teamWorkers.map {
                TeamAnswer(memberId: $0.id, modelId: $0.modelId, role: $0.purpose?.rawValue ?? WorkerStage.answer.rawValue,
                          result: WorkerRunResult(status: .queued))
            },
            createdAt: now()
        )

        run = transition(run, to: .fanningOut)
        for index in run.workerAnswers.indices where run.workerAnswers[index].result.status == .queued {
            run.workerAnswers[index].result.status = .running
            run.workerAnswers[index].result.timing.startedAt = now()
            emitWorkerStatus(run.workerAnswers[index], runId: run.id, from: .queued)
        }

        let runner = imageRunner
        let prompt = request.prompt
        let targetShape = request.targetShape

        // Reflect each option onto its answer as it completes so the board
        // tile fills in progressively (the image path rides the event).
        var options: [DesignOption] = []
        await withTaskGroup(of: DesignOption.self) { group in
            for assignment in teamWorkers {
                let model = modelByID[assignment.modelId]
                let manifest = model.flatMap { manifestByModel[$0.id] ?? nil }
                let personaId = assignment.skillId ?? "minimal"
                let seatRequest = DesignSeatRequest(
                    userPrompt: prompt,
                    personaId: personaId,
                    personaDirection: SkillCatalog.designDirection(for: personaId),
                    targetShape: targetShape,
                    screenshotPath: screenshotAbsolutePath
                )
                group.addTask {
                    guard let model else {
                        return DesignOption(
                            workerId: assignment.id, modelId: assignment.modelId, persona: personaId,
                            status: .failed, failureReason: "no model for worker \(assignment.id)"
                        )
                    }
                    guard let manifest else {
                        return DesignOption(
                            workerId: assignment.id, modelId: model.id, persona: personaId,
                            status: .failed, failureReason: "no driver manifest for \(model.driverId)"
                        )
                    }
                    return await runner.run(
                        seat: assignment, worker: model, manifest: manifest,
                        request: seatRequest, runDir: runDir
                    )
                }
            }
            for await option in group {
                options.append(option)
                guard let index = run.workerAnswers.firstIndex(where: { $0.memberId == option.workerId }) else { continue }
                let previous = run.workerAnswers[index].result.status
                run.workerAnswers[index].result.status = Self.memberStatus(for: option.status)
                run.workerAnswers[index].result.output = option.imagePath
                run.workerAnswers[index].result.errorReason = option.failureReason
                run.workerAnswers[index].result.timing.finishedAt = now()
                emitWorkerStatus(run.workerAnswers[index], runId: run.id, from: previous, imagePath: option.imagePath)
            }
        }

        // Restore panel order for the board (TaskGroup completion order varies).
        let orderBySeat = Dictionary(uniqueKeysWithValues: teamWorkers.enumerated().map { ($1.id, $0) })
        let ordered = options.sorted { (orderBySeat[$0.workerId] ?? 0) < (orderBySeat[$1.workerId] ?? 0) }

        run = transition(run, to: .answersIn)
        if Task.isCancelled {
            return transition(run, to: .cancelled)
        }

        // Assemble the board (board assembly is the design run's "synthesis").
        run = transition(run, to: .planning)
        let board = BoardPayload(
            targetShape: request.targetShape,
            screenshotPath: request.screenshotPath,
            options: ordered
        )
        run.stages.append(StageOutput(
            id: idFactory(),
            purpose: .board,
            status: .done,
            payload: .board(board),
            startedAt: run.createdAt,
            finishedAt: now()
        ))

        let renderedCount = ordered.filter(\.hasImage).count
        let terminal: RunStatus = renderedCount == 0 ? .failed : (renderedCount == ordered.count ? .complete : .partial)
        run = transition(run, to: terminal)
        continuation.finish()
        return run
    }

    static func memberStatus(for status: StageStatus) -> WorkerAnswerStatus {
        switch status {
        case .done: return .done
        case .timedOut: return .timedOut
        case .failed, .queued, .running, .skipped, .reused: return .failed
        }
    }

    // MARK: - Event helpers (mirror TeamRunCoordinator)

    private func nextSeq() -> Int64 { seq += 1; return seq }

    private func transition(_ run: TeamRun, to next: RunStatus) -> TeamRun {
        guard run.canTransition(to: next) else { return run }
        var updated = run
        let from = updated.status
        updated.status = next
        continuation.yield(RunEvent(
            id: idFactory(), seq: nextSeq(), ts: now(),
            kind: RunEventKind.runStatusChanged,
            payload: ["runId": .string(updated.id), "from": .string(from.rawValue), "to": .string(next.rawValue)]
        ))
        return updated
    }

    private func emitWorkerStatus(_ answer: TeamAnswer, runId: String, from: WorkerAnswerStatus, imagePath: String? = nil) {
        var payload: [String: JSONValue] = [
            "runId": .string(runId), "workerId": .string(answer.memberId),
            "modelId": .string(answer.modelId), "from": .string(from.rawValue),
            "to": .string(answer.result.status.rawValue)
        ]
        if let imagePath { payload["output"] = .string(imagePath) }   // the run-relative image, for progressive board reveal
        continuation.yield(RunEvent(id: idFactory(), seq: nextSeq(), ts: now(),
                                    kind: RunEventKind.workerStatusChanged, payload: payload))
    }
}
