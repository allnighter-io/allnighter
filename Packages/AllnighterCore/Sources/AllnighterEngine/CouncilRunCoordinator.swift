import Foundation
import AllnighterCore

/// Owns one council run's fan-out lifecycle: builds member prompts, runs every
/// enabled worker in parallel, updates the run, and emits `RunEvent`s. Phase 02
/// stops at `answersIn` (a failed/missing worker never blocks the run);
/// synthesis is added in Phase 04. The event stream is the single update
/// channel — the same envelope an iOS client will later consume over WebSocket.
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

    /// Fans `prompt` out to the enabled workers and returns the settled run.
    /// Honors task cancellation: a cancelled run terminates child processes and
    /// resolves to `.cancelled`.
    public func fanOut(prompt: String, workers: [Worker], runId: String? = nil) async -> CouncilRun {
        let enabled = workers.filter(\.enabled)

        var run = CouncilRun(
            id: runId ?? idFactory(),
            prompt: prompt,
            status: .draft,
            panel: enabled.map(\.id),
            members: enabled.map { MemberResponse(workerId: $0.id, status: .queued) },
            createdAt: now()
        )

        run = transition(run, to: .fanningOut)

        // Mark everyone running (manual-paste workers will resolve to skipped).
        for index in run.members.indices where run.members[index].status == .queued {
            run.members[index].status = .running
            run.members[index].startedAt = now()
            emitMember(run.members[index], runId: run.id, from: .queued)
        }

        let runnerCopy = workerRunner
        let manifestByWorker = Dictionary(
            uniqueKeysWithValues: enabled.map { ($0.id, registry.manifest(for: $0)) }
        )

        let results: [MemberResponse] = await withTaskGroup(of: MemberResponse.self) { group in
            for worker in enabled {
                let manifest = manifestByWorker[worker.id] ?? nil
                group.addTask {
                    guard let manifest else {
                        return MemberResponse(
                            workerId: worker.id,
                            status: .failed,
                            errorKind: .missingCLI,
                            errorReason: "no driver manifest for \(worker.driverId)"
                        )
                    }
                    return await runnerCopy.run(worker: worker, manifest: manifest, prompt: prompt)
                }
            }

            var collected: [MemberResponse] = []
            for await response in group {
                collected.append(response)
            }
            return collected
        }

        // Apply results back in panel order.
        for result in results {
            if let index = run.members.firstIndex(where: { $0.workerId == result.workerId }) {
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
                "workerId": .string(member.workerId),
                "from": .string(from.rawValue),
                "to": .string(member.status.rawValue)
            ]
        ))
    }
}
