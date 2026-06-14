import Foundation
import AllnighterCore

/// Runs one worker's CLI for one prompt and maps the raw command result into a
/// normalized `MemberResponse`. Pure of orchestration concerns — the
/// coordinator runs many of these in parallel.
public struct WorkerRunner: Sendable {
    private let commandRunner: CommandRunner
    private let now: @Sendable () -> Date

    public init(commandRunner: CommandRunner, now: @escaping @Sendable () -> Date = Date.init) {
        self.commandRunner = commandRunner
        self.now = now
    }

    public func run(
        worker: Worker,
        manifest: DriverManifest,
        prompt: String
    ) async -> MemberResponse {
        // Manual-paste workers do not run; they await a pasted answer.
        guard manifest.kind == .headlessCLI, let invoke = manifest.invoke else {
            return MemberResponse(workerId: worker.id, status: .skipped)
        }

        let context = DriverManifest.ResolveContext(
            prompt: prompt,
            model: worker.modelLabel,
            workingDir: invoke.workingDir
        )
        let args = manifest.resolvedArgs(context)
        let stdin = manifest.stdinPrompt(context)

        let startedAt = now()
        let result = await commandRunner.run(
            command: invoke.command,
            args: args,
            stdin: stdin,
            env: invoke.env,
            workingDirectory: invoke.workingDir,
            timeout: .seconds(invoke.timeoutSeconds)
        )
        let finishedAt = now()
        let durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)

        var response = MemberResponse(
            workerId: worker.id,
            status: .running,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationMs: durationMs
        )

        if let launchError = result.launchError {
            response.status = .failed
            response.errorKind = .missingCLI
            response.errorReason = launchError
            return response
        }
        if result.cancelled {
            response.status = .cancelled
            response.errorKind = .cancelled
            return response
        }
        if result.timedOut {
            response.status = .timedOut
            response.errorKind = .timedOut
            response.errorReason = "no output for \(invoke.timeoutSeconds)s"
            return response
        }

        response.exitCode = result.exitCode.map(Int.init)

        if let code = result.exitCode, code != 0 {
            response.status = .failed
            response.errorKind = .nonzeroExit
            response.errorReason = errorReason(from: result, exitCode: code)
            return response
        }

        let cleaned = output(from: result.stdout, manifest: manifest)
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            response.status = .failed
            response.errorKind = .emptyOutput
            response.errorReason = "worker exited 0 but produced no output"
            return response
        }

        response.status = .done
        response.output = cleaned
        return response
    }

    private func output(from stdout: String, manifest: DriverManifest) -> String {
        if manifest.output?.stripAnsi ?? true {
            return TextUtil.stripANSI(stdout)
        }
        return stdout
    }

    private func errorReason(from result: CommandResult, exitCode: Int32) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? "exit code \(exitCode)" : stderr
    }
}
