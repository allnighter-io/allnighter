import Foundation

/// On `opencode session error: Model not found: …`, reclaim a leftover
/// `opencode serve` once and retry the inner invoke. A genuinely absent model
/// fails on the second attempt. Never stops `alln serve`.
public struct OpenCodeStaleModelServeRefreshingWorkerRunner: WorkerInvoking {
    private let inner: any WorkerInvoking
    private let table: OpenCodeLeftoverServeReclaim.Table
    private let reclaim: @Sendable (OpenCodeLeftoverServeReclaim.Table) -> OpenCodeLeftoverServeReclaim.Outcome

    public init(
        inner: any WorkerInvoking,
        table: OpenCodeLeftoverServeReclaim.Table,
        reclaim: @escaping @Sendable (OpenCodeLeftoverServeReclaim.Table) -> OpenCodeLeftoverServeReclaim.Outcome
            = { OpenCodeLeftoverServeReclaim.reclaim(table: $0) }
    ) {
        self.inner = inner
        self.table = table
        self.reclaim = reclaim
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        guard invocation.manifest.id == "opencode" else {
            return inner.invoke(invocation)
        }
        let inner = self.inner
        let table = self.table
        let reclaim = self.reclaim
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let first = try await Self.collectEvents(inner.invoke(invocation))
                    if let failed = Self.terminalFailed(first),
                       OpenCodeLeftoverServeReclaim.isStaleModelNotFoundReason(failed.errorReason) {
                        let outcome = reclaim(table)
                        if case .reclaimed = outcome {
                            let retry = try await Self.collectEvents(inner.invoke(invocation))
                            for event in retry {
                                continuation.yield(event)
                            }
                            continuation.finish()
                            return
                        }
                    }
                    for event in first {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func collectEvents(
        _ stream: AsyncThrowingStream<WorkerStreamEvent, Error>
    ) async throws -> [WorkerStreamEvent] {
        var events: [WorkerStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private static func terminalFailed(_ events: [WorkerStreamEvent]) -> WorkerRunResult? {
        for event in events.reversed() {
            if case .failed(let result) = event { return result }
            if case .completed = event { return nil }
        }
        return nil
    }
}
