import Foundation
import AllnighterCore

/// Result of running the repo-declared check command (advance signal only — not a verifier).
public struct CheckResult: Sendable, Equatable {
    public var exitCode: Int32?
    public var stdoutTail: String
    public var timedOut: Bool
    public var skipped: Bool

    public init(exitCode: Int32? = nil, stdoutTail: String = "", timedOut: Bool = false, skipped: Bool = false) {
        self.exitCode = exitCode
        self.stdoutTail = stdoutTail
        self.timedOut = timedOut
        self.skipped = skipped
    }

    public var passed: Bool { exitCode == 0 && !timedOut && !skipped }
}

/// Runs the order's repo-declared check as a bounded `/bin/sh -c` subprocess.
public struct CheckRunner: Sendable {
    public static let defaultTimeout: Duration = .seconds(300)
    public static let stdoutTailLimit = 4_096

    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    public func run(
        check: WorkSlicePacket.Check,
        repoRoot: String,
        timeout: Duration = defaultTimeout
    ) async -> CheckResult {
        switch check.method {
        case .command:
            guard let command = check.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
                return .init(skipped: true)
            }
            let result = await commandRunner.run(
                command: "/bin/sh",
                args: ["-c", command],
                stdin: nil,
                env: ProcessInfo.processInfo.environment,
                workingDirectory: repoRoot,
                timeout: timeout
            )
            let combined = result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr)
            return .init(
                exitCode: result.exitCode,
                stdoutTail: Self.tail(combined),
                timedOut: result.timedOut
            )
        case .guiFixture, .userObservation:
            return .init(exitCode: 0, skipped: true)
        }
    }

    static func tail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > stdoutTailLimit else { return trimmed }
        return String(trimmed.suffix(stdoutTailLimit))
    }
}
