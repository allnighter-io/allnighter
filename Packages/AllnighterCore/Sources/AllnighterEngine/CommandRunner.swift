import Foundation

/// The result of running one external command.
public struct CommandResult: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    /// `nil` when the process never reported an exit status (timeout/cancel/launch failure).
    public var exitCode: Int32?
    public var timedOut: Bool
    public var cancelled: Bool
    /// Set when the command could not be launched at all (e.g. binary not on PATH).
    public var launchError: String?

    public init(
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = nil,
        timedOut: Bool = false,
        cancelled: Bool = false,
        launchError: String? = nil
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.launchError = launchError
    }
}

/// Abstracts spawning an external command so the engine can be tested with a
/// `MockCommandRunner` (no real CLIs, zero cost) and run for real with
/// `SubprocessCommandRunner`.
public protocol CommandRunner: Sendable {
    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult
}
