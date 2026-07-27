import Foundation
import AllnighterCore

/// Outermost worker decorator: when a turn times out, replace the bare
/// `worker timed out` reason with a named stall cause written by
/// `ProcessGroupCommandRunner` before the kill (auth prompt / frozen child).
struct StallDiagnosisEnrichingWorkerRunner: WorkerInvoking {
    let inner: any WorkerInvoking

    func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in inner.invoke(invocation) {
                        switch event {
                        case .failed(var outcome) where outcome.status == .timedOut:
                            if let headline = ProcessOwnership.currentStallTimeoutHeadline() {
                                outcome.errorReason = headline
                            }
                            continuation.yield(.failed(outcome))
                        case .completed(var outcome) where outcome.status == .timedOut:
                            if let headline = ProcessOwnership.currentStallTimeoutHeadline() {
                                outcome.errorReason = headline
                            }
                            continuation.yield(.completed(outcome))
                        default:
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
