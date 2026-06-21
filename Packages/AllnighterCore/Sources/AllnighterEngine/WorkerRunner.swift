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
    /// Streaming sibling for `invokeStreaming` (03_Mac_Streaming). Defaults to the
    /// `commandRunner` when it also conforms (SubprocessCommandRunner does), so the
    /// app gets streaming for free.
    private let streamingCommandRunner: StreamingCommandRunner?
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
        streamingCommandRunner: StreamingCommandRunner? = nil,
        invocations: [String: ToolInvocation] = [:],
        defaultWorkingDirectory: String? = nil,
        shellPath: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.commandRunner = commandRunner
        self.streamingCommandRunner = streamingCommandRunner ?? (commandRunner as? StreamingCommandRunner)
        self.invocations = invocations
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.now = now
    }

    /// Whether this runner can actually stream (a streaming command runner is wired).
    /// Callers should gate the streaming path on this AND `manifest.canStream`.
    public var supportsStreaming: Bool { streamingCommandRunner != nil }

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
        let (spawnCommand, spawnArgs) = resolveSpawn(manifest: manifest, invoke: invoke, args: args)

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
        return finalize(
            result: result, worker: worker, manifest: manifest, invoke: invoke,
            outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: finishedAt
        )
    }

    /// Maps resolved argv to the actual spawn (command, args), honoring the detected
    /// invocation plan (direct path / shim / login-shell alias). Shared by `invoke`
    /// and `invokeStreaming` so both spawn through health==runs detection.
    func resolveSpawn(manifest: DriverManifest, invoke: DriverManifest.Invoke, args: [String]) -> (command: String, args: [String]) {
        switch invocations[manifest.id] {
        case .direct(let path), .shim(let path):
            return (path, args)
        case .loginShell(let name):
            // Resolve an alias/function via the login shell; argv flows through
            // "$@" — never concatenated into the shell string (no injection).
            return (shellPath, ["-lic", "\(name) \"$@\"", name] + args)
        case nil:
            return (invoke.command, args)
        }
    }

    /// Shared terminal normalization for `invoke` and `invokeStreaming`:
    /// launch/cancel/timeout/exit-code → status, capacity classification, ANSI strip
    /// + empty check. When `overrideFinalText` is non-nil (a streaming parser's
    /// already-reconciled visible answer) it is used as the answer instead of reading
    /// the manifest capture, and driver-specific stream extraction is skipped (the
    /// parser already produced visible text). On cancel/timeout a non-empty partial
    /// is preserved on the outcome.
    func finalize(
        result: CommandResult, worker: Model, manifest: DriverManifest, invoke: DriverManifest.Invoke,
        outputFileURL: URL?, startedAt: Date, finishedAt: Date, overrideFinalText: String? = nil
    ) -> WorkerRunOutcome {
        let durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)
        var outcome = WorkerRunOutcome(
            status: .running, startedAt: startedAt, finishedAt: finishedAt, durationMs: durationMs)

        func preservedPartial() -> String? {
            guard let t = overrideFinalText,
                  !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return t
        }

        if let launchError = result.launchError {
            outcome.status = .failed
            outcome.errorKind = .missingCLI
            outcome.errorReason = launchError
            return outcome
        }
        if result.cancelled {
            outcome.status = .cancelled
            outcome.errorKind = .cancelled
            outcome.output = preservedPartial()
            return outcome
        }
        if result.timedOut {
            outcome.status = .timedOut
            outcome.errorKind = .timedOut
            outcome.errorReason = "no output for \(invoke.timeoutSeconds)s"
            outcome.output = preservedPartial()
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
            outcome.output = preservedPartial()
            return outcome
        }

        let rawOutput: String
        if let overrideFinalText {
            rawOutput = overrideFinalText
        } else if let outputFileURL, let fileText = try? String(contentsOf: outputFileURL, encoding: .utf8) {
            rawOutput = fileText
        } else {
            rawOutput = result.stdout
        }

        let stripped = output(from: rawOutput, manifest: manifest)
        // The streaming parser already produced visible text; only the non-streaming
        // path needs Grok's post-exit NDJSON extraction.
        let cleaned = (overrideFinalText == nil && manifest.id == "grok")
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

    /// Streaming sibling of `invoke`: spawns the worker's CLI with its STREAMING
    /// argv and drives `parser`, yielding `WorkerStreamEvent`s live. Terminal
    /// normalization is shared with `invoke` via `finalize`. Yields a skipped
    /// terminal when the worker is manual-paste or no streaming runner is wired —
    /// callers should check `manifest.canStream` before choosing this path.
    public func invokeStreaming(
        worker: Model,
        manifest: DriverManifest,
        prompt: String,
        parser: WorkerStreamParser,
        effort: EffortLevel = .med,
        workingDirectoryOverride: String? = nil,
        timeoutOverride: Duration? = nil
    ) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard manifest.kind == .headlessCLI, let invoke = manifest.invoke,
                  let streamingRunner = streamingCommandRunner else {
                continuation.yield(.completed(WorkerRunOutcome(status: .skipped)))
                continuation.finish()
                return
            }

            let capturesFile = manifest.output?.capture == .file
            let outputFileURL: URL? = capturesFile
                ? FileManager.default.temporaryDirectory.appendingPathComponent("alln-\(UUID().uuidString).txt")
                : nil

            let workingDir = workingDirectoryOverride ?? defaultWorkingDirectory ?? invoke.workingDir
            let spawnWorkingDir = workingDir ?? AllnighterPaths.ensuredProbeScratchPath()
            let driverWorkingDir = workingDir ?? spawnWorkingDir
            let context = DriverManifest.ResolveContext(
                prompt: prompt, model: worker.resolvedLabel(at: effort),
                workingDir: driverWorkingDir, outputFile: outputFileURL?.path, effort: effort)
            let args = manifest.resolvedStreamingArgs(context)
            let stdin = manifest.stdinPrompt(context)
            let (spawnCommand, spawnArgs) = resolveSpawn(manifest: manifest, invoke: invoke, args: args)

            let startedAt = now()
            continuation.yield(.started(workerId: worker.id, modelId: worker.id, sourceId: manifest.id))
            StreamDebugLog.log("──── RUN START source=\(manifest.id) model=\(worker.id) cmd=\(spawnCommand) args=\(spawnArgs.joined(separator: " "))")

            let consume = Task { [self] in
                defer { if let outputFileURL { try? FileManager.default.removeItem(at: outputFileURL) } }
                do {
                    for try await event in streamingRunner.runStreaming(
                        command: spawnCommand, args: spawnArgs, stdin: stdin,
                        env: invoke.env, workingDirectory: spawnWorkingDir,
                        timeout: timeoutOverride ?? .seconds(invoke.timeoutSeconds)
                    ) {
                        switch event {
                        case .started:
                            break
                        case .stdout(let data):
                            StreamDebugLog.log("STDOUT \(StreamDebugLog.clip(String(decoding: data, as: UTF8.self)))")
                            let parsed = parser.receiveStdout(data)
                            for streamEvent in parsed { StreamDebugLog.log("  → \(Self.describe(streamEvent))"); continuation.yield(streamEvent) }
                        case .stderr(let data):
                            StreamDebugLog.log("STDERR \(StreamDebugLog.clip(String(decoding: data, as: UTF8.self)))")
                            for streamEvent in parser.receiveStderr(data) { continuation.yield(streamEvent) }
                        case .completed(let result):
                            let fileText = outputFileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                            let finalText = parser.finalAnswer(result: result, outputFileText: fileText)
                            let outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText)
                            StreamDebugLog.log("OUTCOME status=\(outcome.status.rawValue) exit=\(result.exitCode.map(String.init) ?? "nil") outputLen=\(outcome.output?.count ?? 0) finalTextLen=\(finalText?.count ?? -1)")
                            continuation.yield(outcome.status == .done ? .completed(outcome) : .failed(outcome))
                        case .failed(let launchError):
                            var outcome = WorkerRunOutcome(status: .failed, startedAt: startedAt, finishedAt: now())
                            outcome.errorKind = .missingCLI
                            outcome.errorReason = launchError
                            StreamDebugLog.log("OUTCOME launch-failed: \(launchError)")
                            continuation.yield(.failed(outcome))
                        case .timedOut(let partialOut, let partialErr):
                            let result = CommandResult(
                                stdout: String(decoding: partialOut, as: UTF8.self),
                                stderr: String(decoding: partialErr, as: UTF8.self), timedOut: true)
                            let finalText = parser.finalAnswer(result: result, outputFileText: nil)
                            let outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText)
                            continuation.yield(.failed(outcome))
                        case .cancelled(let partialOut, let partialErr):
                            let result = CommandResult(
                                stdout: String(decoding: partialOut, as: UTF8.self),
                                stderr: String(decoding: partialErr, as: UTF8.self), cancelled: true)
                            let finalText = parser.finalAnswer(result: result, outputFileText: nil)
                            let outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText)
                            continuation.yield(.failed(outcome))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in consume.cancel() }
        }
    }

    /// Run a worker and return its `WorkerAnswer` (keyed by `workerId`).
    public func run(
        assignment: Worker,
        model: Model,
        manifest: DriverManifest,
        prompt: String,
        effort: EffortLevel = .med
    ) async -> WorkerAnswer {
        let outcome: WorkerRunOutcome
        if manifest.canStream, supportsStreaming, let parser = WorkerStreamParsers.make(for: manifest) {
            var terminal: WorkerRunOutcome?
            do {
                for try await event in invokeStreaming(worker: model, manifest: manifest, prompt: prompt, parser: parser, effort: effort) {
                    switch event {
                    case .completed(let outcome), .failed(let outcome):
                        terminal = outcome
                    case .started, .answerDelta, .reasoningDelta, .rawEvent, .toolActivity:
                        break
                    }
                }
            } catch {
                terminal = WorkerRunOutcome(
                    status: .failed,
                    errorKind: .nonzeroExit,
                    errorReason: "streaming worker threw: \(error.localizedDescription)"
                )
            }
            let streamed = terminal ?? WorkerRunOutcome(
                status: .failed,
                errorKind: .emptyOutput,
                errorReason: "stream ended without a terminal event"
            )
            if streamed.status != .done, (streamed.output ?? "").isEmpty {
                StreamDebugLog.log("FALLBACK source=\(manifest.id): catalog worker stream gave \(streamed.status.rawValue)/empty — retrying invoke")
                outcome = await invoke(worker: model, manifest: manifest, prompt: prompt, effort: effort)
            } else {
                outcome = streamed
            }
        } else {
            outcome = await invoke(worker: model, manifest: manifest, prompt: prompt, effort: effort)
        }
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

    /// One-line description of a stream event for the debug log.
    private static func describe(_ event: WorkerStreamEvent) -> String {
        switch event {
        case .answerDelta(let text, let seq, _): return "answerDelta[\(seq)] \(StreamDebugLog.clip(text, 120))"
        case .reasoningDelta(let text, let seq): return "reasoningDelta[\(seq)] \(StreamDebugLog.clip(text, 120))"
        case .rawEvent: return "rawEvent (audit)"
        case .toolActivity(let label, let kind): return "toolActivity \(kind): \(label)"
        case .started: return "started"
        case .completed: return "completed"
        case .failed: return "failed"
        }
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
