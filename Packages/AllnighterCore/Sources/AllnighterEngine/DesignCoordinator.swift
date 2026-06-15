import Foundation
import AllnighterCore

/// Owns one design run's image fan-out (Lane 2). Mirrors `CouncilRunCoordinator`:
/// builds per-seat image requests (one image worker × one design persona), runs
/// every seat in parallel via `DesignImageRunner`, writes each image into the run
/// folder, and emits `RunEvent`s keyed by `seatId` so the board reveals
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

    /// Fans the design request out across `seats`, writing images into `runDir`,
    /// and returns the settled run carrying the `board` stage. A failed seat is a
    /// gray tile, never a blocked board: the run is `complete` if every seat
    /// rendered, `partial` if some failed but ≥1 rendered, `failed` if none did.
    /// `screenshotAbsolutePath` is the on-disk path the engines read; the board
    /// stores the run-relative `request.screenshotPath` for the before/after toggle.
    public func generate(
        request: DesignRequest,
        seats: [PanelSeat],
        workers: [Worker],
        runDir: URL,
        screenshotAbsolutePath: String? = nil,
        runId: String? = nil
    ) async -> CouncilRun {
        let workerByID = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let manifestByWorker = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, registry.manifest(for: $0)) })

        var run = CouncilRun(
            id: runId ?? idFactory(),
            prompt: request.prompt,
            status: .draft,
            origin: .gui,
            presetId: "design_board",
            panel: seats,
            members: seats.map { MemberResponse(seatId: $0.id, workerId: $0.workerId, status: .queued) },
            createdAt: now()
        )

        run = transition(run, to: .fanningOut)
        for index in run.members.indices where run.members[index].status == .queued {
            run.members[index].status = .running
            run.members[index].startedAt = now()
            emitMember(run.members[index], runId: run.id, from: .queued)
        }

        let runner = imageRunner
        let prompt = request.prompt
        let targetShape = request.targetShape

        // Fan out; reflect each option onto its member AS IT COMPLETES so the board
        // tile fills in progressively (the image path rides the event).
        var options: [DesignOption] = []
        await withTaskGroup(of: DesignOption.self) { group in
            for seat in seats {
                let worker = workerByID[seat.workerId]
                let manifest = worker.flatMap { manifestByWorker[$0.id] ?? nil }
                let personaId = seat.stance ?? "minimal"
                let seatRequest = DesignSeatRequest(
                    userPrompt: prompt,
                    personaId: personaId,
                    personaDirection: DesignPersonaLibrary.direction(for: personaId),
                    targetShape: targetShape,
                    screenshotPath: screenshotAbsolutePath
                )
                group.addTask {
                    guard let worker else {
                        return DesignOption(seatId: seat.id, workerId: seat.workerId, persona: personaId,
                                            status: .failed, failureReason: "no worker for seat \(seat.id)")
                    }
                    guard let manifest else {
                        return DesignOption(seatId: seat.id, workerId: worker.id, persona: personaId,
                                            status: .failed, failureReason: "no driver manifest for \(worker.driverId)")
                    }
                    return await runner.run(seat: seat, worker: worker, manifest: manifest, request: seatRequest, runDir: runDir)
                }
            }
            for await option in group {
                options.append(option)
                guard let index = run.members.firstIndex(where: { $0.seatId == option.seatId }) else { continue }
                let previous = run.members[index].status
                run.members[index].status = Self.memberStatus(for: option.status)
                run.members[index].output = option.imagePath
                run.members[index].errorReason = option.failureReason
                run.members[index].finishedAt = now()
                emitMember(run.members[index], runId: run.id, from: previous, imagePath: option.imagePath)
            }
        }

        // Restore panel order for the board (TaskGroup completion order varies).
        let orderBySeat = Dictionary(uniqueKeysWithValues: seats.enumerated().map { ($1.id, $0) })
        let ordered = options.sorted { (orderBySeat[$0.seatId] ?? 0) < (orderBySeat[$1.seatId] ?? 0) }

        run = transition(run, to: .answersIn)
        if Task.isCancelled {
            return transition(run, to: .cancelled)
        }

        // Assemble the board (board assembly is the design run's "synthesis").
        run = transition(run, to: .synthesizing)
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

    static func memberStatus(for status: StageStatus) -> MemberStatus {
        switch status {
        case .done: return .done
        case .timedOut: return .timedOut
        case .failed, .queued, .running, .skipped, .reused: return .failed
        }
    }

    // MARK: - Event helpers (mirror CouncilRunCoordinator)

    private func nextSeq() -> Int64 { seq += 1; return seq }

    private func transition(_ run: CouncilRun, to next: RunStatus) -> CouncilRun {
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

    private func emitMember(_ member: MemberResponse, runId: String, from: MemberStatus, imagePath: String? = nil) {
        var payload: [String: JSONValue] = [
            "runId": .string(runId), "seatId": .string(member.seatId),
            "workerId": .string(member.workerId), "from": .string(from.rawValue),
            "to": .string(member.status.rawValue)
        ]
        if let imagePath { payload["output"] = .string(imagePath) }   // the run-relative image, for progressive board reveal
        continuation.yield(RunEvent(id: idFactory(), seq: nextSeq(), ts: now(),
                                    kind: RunEventKind.memberStatusChanged, payload: payload))
    }
}
