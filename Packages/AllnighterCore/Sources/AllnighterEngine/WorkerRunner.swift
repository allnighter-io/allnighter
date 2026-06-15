import Foundation
import AllnighterCore

/// The neutral result of invoking one worker's CLI once — shared by workers
/// (wrapped into a `WorkerAnswer`) and reduce stages (wrapped into a
/// `StageOutput`). Pure of orchestration concerns.
public struct WorkerRunOutcome: Sendable, Equatable {
    public var status: WorkerAnswerStatus
    public var output: String?
    public var errorKind: WorkerAnswerErrorKind?
    public var errorReason: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMs: Int?
    public var exitCode: Int?

    public var hasOutput: Bool { status == .done && (output?.isEmpty == false) }
}

/// Runs one worker's CLI for one prompt and normalizes the raw command result.
/// The coordinator runs many of these in parallel.
public struct WorkerRunner: Sendable {
    private let commandRunner: CommandRunner
    private let now: @Sendable () -> Date

    public init(commandRunner: CommandRunner, now: @escaping @Sendable () -> Date = Date.init) {
        self.commandRunner = commandRunner
        self.now = now
    }

    /// Invoke a worker's CLI once and return the neutral outcome.
    /// `workingDirectoryOverride`/`timeoutOverride` let dispatch (RB4) run in a
    /// chosen directory with a longer budget than the panel timeout.
    public func invoke(
        worker: Model,
        manifest: DriverManifest,
        prompt: String,
        workingDirectoryOverride: String? = nil,
        timeoutOverride: Duration? = nil
    ) async -> WorkerRunOutcome {
        // Manual-paste workers do not run; they await a pasted answer.
        guard manifest.kind == .headlessCLI, let invoke = manifest.invoke else {
            return WorkerRunOutcome(status: .skipped)
        }

        // File capture: hand the CLI a temp file to write its final answer to,
        // then read that instead of stdout (keeps noisy CLIs like codex clean).
        let capturesFile = manifest.output?.capture == .file
        let outputFileURL: URL? = capturesFile
            ? FileManager.default.temporaryDirectory.appendingPathComponent("alln-\(UUID().uuidString).txt")
            : nil
        defer { if let outputFileURL { try? FileManager.default.removeItem(at: outputFileURL) } }

        let workingDir = workingDirectoryOverride ?? invoke.workingDir
        let context = DriverManifest.ResolveContext(
            prompt: prompt,
            model: worker.modelLabel,
            workingDir: workingDir,
            outputFile: outputFileURL?.path
        )
        let args = manifest.resolvedArgs(context)
        let stdin = manifest.stdinPrompt(context)

        let startedAt = now()
        let result = await commandRunner.run(
            command: invoke.command,
            args: args,
            stdin: stdin,
            env: invoke.env,
            workingDirectory: workingDir,
            timeout: timeoutOverride ?? .seconds(invoke.timeoutSeconds)
        )
        let finishedAt = now()
        let durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)

        var outcome = WorkerRunOutcome(
            status: .running,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationMs: durationMs
        )

        if let launchError = result.launchError {
            outcome.status = .failed
            outcome.errorKind = .missingCLI
            outcome.errorReason = launchError
            return outcome
        }
        if result.cancelled {
            outcome.status = .cancelled
            outcome.errorKind = .cancelled
            return outcome
        }
        if result.timedOut {
            outcome.status = .timedOut
            outcome.errorKind = .timedOut
            outcome.errorReason = "no output for \(invoke.timeoutSeconds)s"
            return outcome
        }

        outcome.exitCode = result.exitCode.map(Int.init)

        if let code = result.exitCode, code != 0 {
            outcome.status = .failed
            outcome.errorKind = .nonzeroExit
            outcome.errorReason = errorReason(from: result, exitCode: code)
            return outcome
        }

        let rawOutput: String
        if let outputFileURL, let fileText = try? String(contentsOf: outputFileURL, encoding: .utf8) {
            rawOutput = fileText
        } else {
            rawOutput = result.stdout
        }

        let cleaned = output(from: rawOutput, manifest: manifest)
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outcome.status = .failed
            outcome.errorKind = .emptyOutput
            outcome.errorReason = "worker exited 0 but produced no output"
            return outcome
        }

        outcome.status = .done
        outcome.output = cleaned
        return outcome
    }

    /// Run a worker and return its `WorkerAnswer` (keyed by `workerId`).
    public func run(
        assignment: Worker,
        model: Model,
        manifest: DriverManifest,
        prompt: String
    ) async -> WorkerAnswer {
        let outcome = await invoke(worker: model, manifest: manifest, prompt: prompt)
        return WorkerAnswer(
            workerId: assignment.id,
            modelId: model.id,
            status: outcome.status,
            output: outcome.output,
            errorKind: outcome.errorKind,
            errorReason: outcome.errorReason,
            startedAt: outcome.startedAt,
            finishedAt: outcome.finishedAt,
            durationMs: outcome.durationMs,
            exitCode: outcome.exitCode
        )
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
