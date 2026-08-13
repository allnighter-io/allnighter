import Foundation

/// Checkpointed sweep over an ordered target list.
///
/// Resume continues at the first `not-attempted` target. Completed `done` /
/// `failed` rows are never redone. The sweep is `complete` only when every
/// target was attempted. A mid-run kill leaves remaining work `not-attempted`.
public struct SweepEngine: Sendable {
    public var store: any SweepPersisting
    public var now: @Sendable () -> Date

    public init(store: any SweepPersisting, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    public func create(
        order: String,
        targetIds: [String],
        projectRoot: String,
        modelId: String? = nil,
        sweepId: String? = nil
    ) throws -> SweepState {
        let ids = try SweepTargetList.parse(repeated: targetIds)
        let stamp = now()
        var state = SweepState(
            id: sweepId ?? UUID().uuidString,
            order: order,
            projectRoot: projectRoot,
            modelId: modelId,
            targets: ids.map { SweepTargetRecord(id: $0) },
            status: .running,
            createdAt: stamp,
            updatedAt: stamp
        )
        try checkpoint(&state)
        return state
    }

    /// Advance remaining `not-attempted` targets. Same path for start and resume.
    public func advance(id: String, executor: any SweepTargetExecuting) async throws -> SweepState {
        guard var state = try store.load(id: id) else { throw SweepError.notFound(id: id) }
        if state.status == .complete {
            try SweepHonesty.requireComplete(state)
            return state
        }
        state.status = .running
        state.updatedAt = now()
        try checkpoint(&state)

        for index in state.targets.indices {
            guard state.targets[index].outcome == .notAttempted else { continue }
            let targetId = state.targets[index].id
            do {
                let attempt = try await executor.attempt(order: state.order, targetId: targetId)
                apply(attempt, to: &state.targets[index])
                if case .notFinished = attempt {
                    state.status = .interrupted
                    state.updatedAt = now()
                    try checkpoint(&state)
                    return state
                }
                state.updatedAt = now()
                try checkpoint(&state)
            } catch is SweepInterrupt {
                state.status = .interrupted
                state.updatedAt = now()
                try checkpoint(&state)
                return state
            } catch {
                state.targets[index].outcome = .failed
                state.targets[index].reason = error.localizedDescription
                state.updatedAt = now()
                try checkpoint(&state)
            }
        }

        try SweepHonesty.requireComplete(state)
        state.status = .complete
        state.updatedAt = now()
        try checkpoint(&state)
        return state
    }

    /// Owner died mid-sweep: in-flight work stays `not-attempted`. Never complete.
    public func reconcileKill(_ state: SweepState) throws -> SweepState {
        var next = state
        next.status = .interrupted
        next.updatedAt = now()
        for index in next.targets.indices where next.targets[index].outcome != .done && next.targets[index].outcome != .failed {
            next.targets[index].outcome = .notAttempted
        }
        try checkpoint(&next)
        return next
    }

    private func apply(_ attempt: SweepAttempt, to target: inout SweepTargetRecord) {
        switch attempt {
        case .done(let runId):
            target.outcome = .done
            target.runId = runId
            target.reason = nil
        case .failed(let runId, let reason):
            target.outcome = .failed
            target.runId = runId
            target.reason = reason
        case .notFinished(let runId):
            target.outcome = .notAttempted
            target.runId = runId
        }
    }

    private func checkpoint(_ state: inout SweepState) throws {
        if state.status == .complete {
            try SweepHonesty.requireComplete(state)
        }
        let card = SweepArtifact.project(state)
        let json = try SweepArtifact.jsonData(card)
        let markdown = SweepArtifact.markdown(card)
        state.artifactPath = try store.writeArtifact(state, json: json, markdown: markdown)
        try store.save(state)
    }
}
