import Foundation

/// One event in a streaming command run (03_Mac_Streaming §V1 Architecture). A run
/// emits zero or more `stdout`/`stderr` chunks, then EXACTLY ONE terminal event
/// (`completed`, `failed`, `timedOut`, or `cancelled`). Non-zero CLI exits are NOT
/// stream errors — they arrive as a `completed(CommandResult)` whose exit code the
/// existing `WorkerRunOutcome` normalization owns. `failed` is spawn failure before
/// a process exists.
public enum CommandEvent: Sendable, Equatable {
    case started(startedAt: Date)
    /// A raw stdout byte chunk — NOT necessarily a full UTF-8 character or JSON line.
    case stdout(Data)
    /// A raw stderr byte chunk (diagnostic; drivers opt into any visible mapping).
    case stderr(Data)
    /// Normal termination. `result` carries the COMPLETE stdout/stderr buffers, the
    /// same shape today's non-streaming path returns.
    case completed(CommandResult)
    /// The process could not be launched at all (binary not found, spawn failure).
    case failed(launchError: String)
    /// The timeout watchdog killed the process group; partial buffers preserved.
    case timedOut(partialStdout: Data, partialStderr: Data)
    /// The consumer cancelled the stream; the process group was killed and partial
    /// buffers preserved.
    case cancelled(partialStdout: Data, partialStderr: Data)
}

/// Streaming sibling of `CommandRunner`: same launch contract, but output arrives as
/// `CommandEvent`s as the child writes, instead of one `CommandResult` at exit.
/// `SubprocessCommandRunner` implements both; both paths MUST share process-group
/// kill, timeout, env scrubbing, stdin, PATH resolution, and working-directory rules.
public protocol StreamingCommandRunner: Sendable {
    func runStreaming(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error>
}
