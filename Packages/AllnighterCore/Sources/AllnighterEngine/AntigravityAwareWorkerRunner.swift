import Foundation
import AllnighterCore

/// Wraps a `WorkerInvoking` to rewrite Antigravity's (`agy`) terminal answer from its
/// on-disk structured transcript — the ONE behavior AgentOS's `DefaultWorkerRunner`
/// does not itself do. `DefaultWorkerRunner` already resolves the `session_dir`
/// capture rule and stamps the new vendor session id onto `result.capturedSessionId`
/// (see `DefaultWorkerRunner.normalize`'s `captureDir`/`dirBefore` handling); this
/// decorator only turns that id into the clean split answer/reasoning
/// `AntigravityTranscript.split` produces — the same normalization
/// `WorkerRunner.applyAntigravityTranscript` does today (see `WorkerRunner.swift`,
/// NOT modified here), just re-homed onto the `WorkerInvoking` seam. Pass-through,
/// unmodified, for every driver but `antigravity`.
public struct AntigravityAwareWorkerRunner: WorkerInvoking {
    private let inner: any WorkerInvoking

    public init(inner: any WorkerInvoking) {
        self.inner = inner
    }

    public func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        guard invocation.manifest.id == "antigravity" else {
            return inner.invoke(invocation)
        }
        let manifest = invocation.manifest
        let inner = self.inner

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in inner.invoke(invocation) {
                        switch event {
                        case .completed(let result):
                            continuation.yield(.completed(Self.rewritten(result, manifest: manifest)))
                        case .failed(let result):
                            continuation.yield(.failed(Self.rewritten(result, manifest: manifest)))
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

    /// Replaces `result.output`/`result.reasoning` with the transcript's clean final
    /// `PLANNER_RESPONSE` split, when the transcript resolves to a non-empty answer.
    /// No-op (keeps whatever `inner` produced) if the session id, brain dir, or
    /// transcript can't be resolved — never worse than the un-rewritten result.
    static func rewritten(_ result: WorkerRunResult, manifest: DriverManifest) -> WorkerRunResult {
        var result = result
        guard result.status == .done,
              let sessionId = result.capturedSessionId,
              let dir = manifest.session?.capture?.dir
        else { return result }
        let brainURL = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        let transcriptURL = AntigravityTranscript.transcriptURL(brainDir: brainURL, sessionId: sessionId)
        guard let split = AntigravityTranscript.split(transcriptAt: transcriptURL), !split.answer.isEmpty
        else { return result }
        result.output = split.answer
        result.reasoning = split.reasoning.isEmpty ? nil : split.reasoning
        return result
    }
}
