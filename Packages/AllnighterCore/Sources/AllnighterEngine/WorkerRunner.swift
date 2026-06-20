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
    /// Sourced capacity/cooldown fact from raw CLI output (nonzero exit only).
    public var capacityObservation: CapacityObservation?

    public var hasOutput: Bool { status == .done && (output?.isEmpty == false) }
}

/// Runs one worker's CLI for one prompt and normalizes the raw command result.
/// The coordinator runs many of these in parallel.
public struct WorkerRunner: Sendable {
    private let commandRunner: CommandRunner
    private let now: @Sendable () -> Date
    /// Per-driver invocation resolved by detection (docs/phases/setup/01 §4.3).
    /// When present, the worker spawns through the SAME plan that passed the
    /// health probe — so health == runs. Empty → bare `invoke.command` (legacy).
    private let invocations: [String: ToolInvocation]
    private let shellPath: String
    /// When set, every invoke without an explicit override runs in this directory
    /// (repo-root runs). Nil keeps legacy neutral-scratch behavior for probes.
    private let defaultWorkingDirectory: String?

    public init(
        commandRunner: CommandRunner,
        invocations: [String: ToolInvocation] = [:],
        defaultWorkingDirectory: String? = nil,
        shellPath: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.commandRunner = commandRunner
        self.invocations = invocations
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.now = now
    }

    /// Invoke a worker's CLI once and return the neutral outcome.
    /// `workingDirectoryOverride`/`timeoutOverride` let repo-scoped runs use a
    /// chosen directory with a longer budget than the panel timeout.
    public func invoke(
        worker: Model,
        manifest: DriverManifest,
        prompt: String,
        effort: EffortLevel = .med,
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

        let workingDir = workingDirectoryOverride ?? defaultWorkingDirectory ?? invoke.workingDir
        // The spawned CLI must NOT inherit the app's process CWD — in dev that is
        // the checkout under ~/Documents, so the worker reading its cwd raises a
        // TCC Documents prompt attributed to the app (code red on first chat send).
        // When no explicit dir is given (chat / team runs), spawn in an
        // Allnighter-owned neutral scratch; explicit repo runs keep theirs.
        // (Launch Authority TCC hotfix neutralized setup/health probe CWDs; this
        // extends the same rule to worker runs.) When a driver needs a workspace
        // argv token and no Project root exists, use the same owned scratch so
        // flags like `--cwd {{workingDir}}` never become `--cwd ""`.
        let spawnWorkingDir = workingDir ?? AllnighterPaths.ensuredProbeScratchPath()
        let driverWorkingDir = workingDir ?? spawnWorkingDir
        let context = DriverManifest.ResolveContext(
            prompt: prompt,
            model: worker.resolvedLabel(at: effort),
            workingDir: driverWorkingDir,
            outputFile: outputFileURL?.path,
            effort: effort
        )
        let args = manifest.resolvedArgs(context)
        let stdin = manifest.stdinPrompt(context)

        // health == runs: spawn through the SAME invocation detection resolved
        // (docs/phases/setup/01 §4.3, §10), not the bare command on the ambient PATH.
        let spawnCommand: String
        let spawnArgs: [String]
        switch invocations[manifest.id] {
        case .direct(let path), .shim(let path):
            spawnCommand = path
            spawnArgs = args
        case .loginShell(let name):
            // Resolve an alias/function via the login shell; argv flows through
            // "$@" — never concatenated into the shell string (no injection).
            spawnCommand = shellPath
            spawnArgs = ["-lic", "\(name) \"$@\"", name] + args
        case nil:
            spawnCommand = invoke.command
            spawnArgs = args
        }

        let startedAt = now()
        let result = await commandRunner.run(
            command: spawnCommand,
            args: spawnArgs,
            stdin: stdin,
            env: invoke.env,
            workingDirectory: spawnWorkingDir,
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
            outcome.capacityObservation = CapacityClassifier.classify(
                CapacityClassifier.Input(
                    workerId: worker.id,
                    sourceId: manifest.id,
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: code,
                    observedAt: finishedAt
                )
            )
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

        let stripped = output(from: rawOutput, manifest: manifest)
        let cleaned = manifest.id == "grok"
            ? TextUtil.extractGrokStreamingVisibleText(stripped)
            : stripped
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
        prompt: String,
        effort: EffortLevel = .med
    ) async -> WorkerAnswer {
        let outcome = await invoke(worker: model, manifest: manifest, prompt: prompt, effort: effort)
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
            exitCode: outcome.exitCode,
            capacityObservation: outcome.capacityObservation
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
