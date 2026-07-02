import Foundation
import AllnighterCore

/// Adapts a one-shot `CommandRunner` onto the `StreamingCommandRunner` seam
/// `DefaultWorkerRunner` requires: spawns once via `inner.run(...)` and replays the
/// complete result as a single terminal `CommandEvent` (no incremental `.stdout`/
/// `.stderr` chunks). `DefaultWorkerRunner.normalize`'s degraded-stream fallback
/// (replay the full buffer through the parser once when it never saw a chunk) then
/// reproduces the old non-streaming `WorkerRunner.invoke` path exactly.
///
/// This exists so test doubles written against the historical `CommandRunner`
/// protocol (`MockCommandRunner`, in-repo recorders) keep working unmodified after
/// the `WorkerRunner` deletion — no behavior a real spawn needs, purely test-seam glue.
public struct CommandRunnerAsStreaming: StreamingCommandRunner {
    private let inner: any CommandRunner

    public init(_ inner: any CommandRunner) {
        self.inner = inner
    }

    public func runStreaming(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let result = await inner.run(
                    command: command, args: args, stdin: stdin,
                    env: env, workingDirectory: workingDirectory, timeout: timeout
                )
                if let launchError = result.launchError {
                    continuation.yield(.failed(launchError: launchError))
                } else if result.cancelled {
                    continuation.yield(.cancelled(
                        partialStdout: Data(result.stdout.utf8), partialStderr: Data(result.stderr.utf8)))
                } else if result.timedOut {
                    continuation.yield(.timedOut(
                        partialStdout: Data(result.stdout.utf8), partialStderr: Data(result.stderr.utf8)))
                } else if result.bufferOverflowed {
                    continuation.yield(.bufferOverflow(
                        partialStdout: Data(result.stdout.utf8), partialStderr: Data(result.stderr.utf8)))
                } else {
                    continuation.yield(.started(startedAt: Date()))
                    continuation.yield(.completed(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
