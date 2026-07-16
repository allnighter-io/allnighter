import Foundation
import AllnighterCore

/// FR13 — run a declared proof command as a bounded `/bin/sh -c` subprocess at the
/// project root. Surfaces exit code + output tail; never blocks or undoes worker git.
public struct RunProofRunner: Sendable {
    public static let defaultTimeoutSeconds = 600
    public static let outputTailCap = 4000

    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    public func run(
        command: String, cwd: String, timeoutSeconds: Int = defaultTimeoutSeconds
    ) async -> RunProofResult {
        let timeout = Duration.seconds(max(1, timeoutSeconds))
        let result = await commandRunner.run(
            command: "/bin/sh",
            args: ["-c", command],
            stdin: nil,
            env: ProcessInfo.processInfo.environment,
            workingDirectory: cwd,
            timeout: timeout
        )
        let combined = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let tail = String(combined.suffix(Self.outputTailCap))
        if result.timedOut {
            return RunProofResult(
                command: command, exitCode: nil, passed: false, timedOut: true, outputTail: tail)
        }
        let code = result.exitCode.map { Int($0) } ?? 1
        return RunProofResult(
            command: command, exitCode: code, passed: code == 0, timedOut: false, outputTail: tail)
    }
}
