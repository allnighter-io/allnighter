import Foundation
import AllnighterCore

/// Owns one council run's panel fan-out: builds per-seat prompts, runs every seat
/// in parallel, updates the run, and emits `RunEvent`s keyed by `seatId`. Stops
/// at `answersIn` (a failed/missing seat never blocks the run); synthesis (the
/// analysis + plan reduces) is driven by `Synthesizer`. The event stream is the
/// single update channel — the same envelope an iOS/tool client consumes.
public actor CouncilRunCoordinator {
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

    /// Fans `prompt` out across `seats` (resolving each seat's worker from
    /// `workers`) and returns the settled run. Honors cancellation: a cancelled
    /// run terminates children and resolves to `.cancelled`.
    public func fanOut(
        prompt: String,
        seats: [PanelSeat],
        workers: [Worker],
        origin: RunOrigin = .gui,
        originAgent: String? = nil,
        presetId: String? = nil,
        runId: String? = nil
    ) async -> CouncilRun {
        let workerByID = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var run = CouncilRun(
            id: runId ?? idFactory(),
            prompt: prompt,
            status: .draft,
            origin: origin,
            originAgent: originAgent,
            presetId: presetId,
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

        let runnerCopy = workerRunner
        let manifestByWorker = Dictionary(
            uniqueKeysWithValues: workers.map { ($0.id, registry.manifest(for: $0)) }
        )

        let results: [MemberResponse] = await withTaskGroup(of: MemberResponse.self) { group in
            for seat in seats {
                let worker = workerByID[seat.workerId]
                let manifest = worker.flatMap { manifestByWorker[$0.id] ?? nil }
                let seatPrompt = StanceLibrary.assemblePrompt(stance: seat.stance, founderPrompt: prompt)
                group.addTask {
                    guard let worker else {
                        return MemberResponse(
                            seatId: seat.id, workerId: seat.workerId, status: .failed,
                            errorKind: .missingCLI, errorReason: "no worker for seat \(seat.id)"
                        )
                    }
                    guard let manifest else {
                        return MemberResponse(
                            seatId: seat.id, workerId: worker.id, status: .failed,
                            errorKind: .missingCLI, errorReason: "no driver manifest for \(worker.driverId)"
                        )
                    }
                    return await runnerCopy.run(seat: seat, worker: worker, manifest: manifest, prompt: seatPrompt)
                }
            }

            var collected: [MemberResponse] = []
            for await response in group { collected.append(response) }
            return collected
        }

        for result in results {
            if let index = run.members.firstIndex(where: { $0.seatId == result.seatId }) {
                let previous = run.members[index].status
                run.members[index] = result
                emitMember(result, runId: run.id, from: previous)
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

    // MARK: - Event helpers

    private func nextSeq() -> Int64 {
        seq += 1
        return seq
    }

    private func transition(_ run: CouncilRun, to next: RunStatus) -> CouncilRun {
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

    private func emitMember(_ member: MemberResponse, runId: String, from: MemberStatus) {
        continuation.yield(RunEvent(
            id: idFactory(),
            seq: nextSeq(),
            ts: now(),
            kind: RunEventKind.memberStatusChanged,
            payload: [
                "runId": .string(runId),
                "seatId": .string(member.seatId),
                "workerId": .string(member.workerId),
                "from": .string(from.rawValue),
                "to": .string(member.status.rawValue)
            ]
        ))
    }
}
