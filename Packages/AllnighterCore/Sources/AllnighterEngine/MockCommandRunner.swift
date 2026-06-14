import Foundation

/// A scripted `CommandRunner` for tests and previews — no real CLIs, zero cost,
/// deterministic. Keyed by the command (executable) name.
public struct MockCommandRunner: CommandRunner {
    public struct Script: Sendable {
        public var stdout: String
        public var stderr: String
        public var exitCode: Int32?
        public var delay: Duration
        public var launchError: String?
        public var forcesTimeout: Bool

        public init(
            stdout: String = "",
            stderr: String = "",
            exitCode: Int32? = 0,
            delay: Duration = .zero,
            launchError: String? = nil,
            forcesTimeout: Bool = false
        ) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
            self.delay = delay
            self.launchError = launchError
            self.forcesTimeout = forcesTimeout
        }
    }

    public var scripts: [String: Script]
    public var fallback: Script

    public init(scripts: [String: Script], fallback: Script = Script()) {
        self.scripts = scripts
        self.fallback = fallback
    }

    public func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        let script = scripts[command] ?? fallback

        if let launchError = script.launchError {
            return CommandResult(launchError: launchError)
        }

        // Honor real cancellation so the coordinator's stop works in tests.
        do {
            try await Task.sleep(for: script.delay)
        } catch {
            return CommandResult(cancelled: true)
        }

        // Emulate the timeout outcome directly (the mock has no watchdog).
        if script.forcesTimeout {
            return CommandResult(timedOut: true)
        }

        return CommandResult(
            stdout: script.stdout,
            stderr: script.stderr,
            exitCode: script.exitCode
        )
    }
}
