import Foundation

/// Inspectable spawn facts for a worker CLI attempt — persisted in `workers/<id>.metadata.json`.
public struct WorkerSpawnDiagnostics: Codable, Sendable, Equatable {
    public enum TimeoutKind: String, Codable, Sendable {
        /// Non-streaming `SubprocessCommandRunner.run` — fixed wall clock from spawn.
        case wallClock = "wall_clock"
        /// Streaming path — idle silence between output chunks.
        case idle = "idle"
    }

    public var command: String
    /// Arg count only — the resolved argv may embed the full prompt.
    public var argCount: Int
    public var workingDirectory: String?
    public var timeoutSeconds: Int
    public var timeoutKind: TimeoutKind
    public var stdoutBytes: Int
    public var stderrBytes: Int
    /// Last ≤512 bytes of stderr for triage (ANSI stripped).
    public var stderrTail: String?
    /// How the spawn command was resolved: direct, shim, login_shell, or ambient.
    public var invocationKind: String?

    public init(
        command: String,
        argCount: Int,
        workingDirectory: String?,
        timeoutSeconds: Int,
        timeoutKind: TimeoutKind,
        stdoutBytes: Int,
        stderrBytes: Int,
        stderrTail: String?,
        invocationKind: String?
    ) {
        self.command = command
        self.argCount = argCount
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.timeoutKind = timeoutKind
        self.stdoutBytes = stdoutBytes
        self.stderrBytes = stderrBytes
        self.stderrTail = stderrTail
        self.invocationKind = invocationKind
    }
}
