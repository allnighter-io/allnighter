import Foundation
import AllnighterCore

/// The neutral result of invoking one worker's CLI once — shared by workers
/// (wrapped into a `WorkerAnswer`) and reduce stages (wrapped into a
/// `StageOutput`). Pure of orchestration concerns.
///
/// This is AgentOSCLI's `WorkerRunResult` (F2_B.1+.2 cutover): the telemetry fields this
/// type used to carry inline (`startedAt`, `ttftMs`, `rawStdoutChunkCount`, etc.) now live
/// under `.timing` (a `RunTiming`). Kept as a local alias so the ~70 `WorkerRunOutcome`
/// call sites keep resolving by name.
public typealias WorkerRunOutcome = WorkerRunResult

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
        timeoutOverride: Duration? = nil,
        spawnConcurrencyLimit: Int? = nil
    ) async -> WorkerRunOutcome {
        // Manual-paste workers do not run; they await a pasted answer.
        guard manifest.kind == .headlessCLI, let invoke = manifest.invoke else {
            return WorkerRunOutcome(status: .skipped)
        }

        // OpenCode runs over its serve HTTP API (the answer channel), not `opencode run`
        // (a TTY-only client that emits nothing when piped). The session is rooted at the
        // run's working dir so tools edit the right repo, with all tool permissions
        // auto-approved for headless execution. See OpenCode_Smoke_Probe_Blocker.md (OC-B1).
        if manifest.id == "opencode" {
            return await runOpenCode(
                worker: worker, manifest: manifest, invoke: invoke, prompt: prompt, effort: effort,
                workingDirectoryOverride: workingDirectoryOverride, timeoutOverride: timeoutOverride,
                spawnConcurrencyLimit: spawnConcurrencyLimit
            )
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
        let invocationKind = invocationKindLabel(manifest: manifest)
        let timeoutSeconds = invoke.timeoutSeconds
        let spawnDiagBase = (
            command: spawnCommand,
            argCount: spawnArgs.count,
            workingDirectory: spawnWorkingDir,
            timeoutSeconds: timeoutSeconds,
            timeoutKind: WorkerSpawnDiagnostics.TimeoutKind.wallClock,
            invocationKind: invocationKind
        )

        // Per-driver spawn gate: fragile CLIs (agy, cursor) declare maxConcurrentSpawns=1
        // and serialize here; everything else stays ungated. Acquire BEFORE stamping
        // startedAt so a queued seat's duration excludes its wait — the wait is captured
        // separately as gateWaitMs. The run is always timeout-bounded, so the permit is
        // always released and the queue drains.
        let gateLimit = spawnConcurrencyLimit ?? manifest.maxConcurrentSpawns
        let gateRequestedAt = now()
        if let gateLimit, let gateFailure = await acquireDriverSpawnGate(driverId: manifest.id, limit: gateLimit) {
            return gateFailure
        }
        let startedAt = now()
        let gateWaitMs = gateLimit == nil ? nil : max(0, Int(startedAt.timeIntervalSince(gateRequestedAt) * 1000))
        // AGY transcript normalizer: snapshot the brain dir so we can find THIS run's session
        // unambiguous) and split its structured transcript into clean answer + step narration.
        let brainSnapshot = antigravityBrainSnapshot(manifest: manifest)
        let result = await commandRunner.run(
            command: spawnCommand,
            args: spawnArgs,
            stdin: stdin,
            env: invoke.env,
            workingDirectory: spawnWorkingDir,
            timeout: timeoutOverride ?? .seconds(invoke.timeoutSeconds)
        )
        if gateLimit != nil { await DriverConcurrencyGate.shared.release(driverId: manifest.id) }
        let finishedAt = now()
        var outcome = finalize(
            result: result, worker: worker, manifest: manifest, invoke: invoke,
            outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: finishedAt,
            timeoutKind: .wallClock,
            spawnCommand: spawnDiagBase.command,
            spawnArgCount: spawnDiagBase.argCount,
            spawnWorkingDir: spawnDiagBase.workingDirectory,
            invocationKind: spawnDiagBase.invocationKind
        )
        outcome.timing.gateWaitMs = gateWaitMs
        applyAntigravityTranscript(&outcome, snapshot: brainSnapshot)
        return outcome
    }

    /// OpenCode run over the warm serve HTTP API: ensure serve → one session rooted at the
    /// run's working dir, tool permissions auto-approved → one prompt → answer (+ reasoning).
    /// Uses HTTP SSE streaming when `manifest.canStream`; otherwise sync POST /message.
    private func runOpenCode(
        worker: Model,
        manifest: DriverManifest,
        invoke: DriverManifest.Invoke,
        prompt: String,
        effort: EffortLevel,
        workingDirectoryOverride: String?,
        timeoutOverride: Duration?,
        spawnConcurrencyLimit: Int? = nil
    ) async -> WorkerRunOutcome {
        let gateLimit = spawnConcurrencyLimit ?? manifest.maxConcurrentSpawns
        let driverId = manifest.id
        if let gateLimit, let gateFailure = await acquireDriverSpawnGate(driverId: driverId, limit: gateLimit) {
            return gateFailure
        }
        func finish(_ outcome: WorkerRunOutcome) async -> WorkerRunOutcome {
            if gateLimit != nil { await releaseDriverSpawnGate(driverId: driverId) }
            return outcome
        }

        let startedAt = now()
        do {
            try await OpenCodeServeCoordinator().ensureRunning()
        } catch {
            var outcome = WorkerRunOutcome(
                status: .failed, errorKind: .missingCLI,
                errorReason: "opencode serve: \(error)")
            outcome.timing.startedAt = startedAt
            outcome.timing.finishedAt = now()
            return await finish(outcome)
        }
        let directory = workingDirectoryOverride ?? defaultWorkingDirectory
            ?? AllnighterPaths.ensuredProbeScratchPath()
            ?? FileManager.default.temporaryDirectory.path
            ?? NSTemporaryDirectory()
        let timeout = timeoutOverride ?? .seconds(invoke.timeoutSeconds)
        let modelLabel = worker.resolvedLabel(at: effort)

        if manifest.canStream {
            var terminal: WorkerRunOutcome?
            do {
                for try await event in invokeOpenCodeStreaming(
                    prompt: prompt, modelLabel: modelLabel,
                    directory: directory, timeout: timeout
                ) {
                    switch event {
                    case .completed(let o), .failed(let o): terminal = o
                    case .started, .answerDelta, .reasoningDelta, .rawEvent, .toolActivity: break
                    }
                }
            } catch {
                var outcome = WorkerRunOutcome(
                    status: .failed, errorKind: .nonzeroExit,
                    errorReason: "opencode stream: \(error)")
                outcome.timing.startedAt = startedAt
                outcome.timing.finishedAt = now()
                return await finish(outcome)
            }
            if let terminal { return await finish(terminal) }
            var outcome = WorkerRunOutcome(
                status: .failed, errorKind: .emptyOutput,
                errorReason: "opencode stream ended without terminal")
            outcome.timing.startedAt = startedAt
            outcome.timing.finishedAt = now()
            return await finish(outcome)
        }

        do {
            let answer = try await OpenCodeServeClient().run(
                prompt, modelLabel: modelLabel, directory: directory,
                autoApprove: true, timeout: timeout
            )
            let finishedAt = now()
            var outcome = WorkerRunOutcome(status: .done, output: answer.text, reasoning: answer.reasoning)
            outcome.timing.startedAt = startedAt
            outcome.timing.finishedAt = finishedAt
            outcome.timing.durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)
            return await finish(outcome)
        } catch {
            let finishedAt = now()
            let kind: WorkerAnswerErrorKind =
                (error as? OpenCodeServeClient.ClientError) == .emptyAnswer ? .emptyOutput : .nonzeroExit
            var outcome = WorkerRunOutcome(
                status: .failed, errorKind: kind,
                errorReason: "opencode: \(error)")
            outcome.timing.startedAt = startedAt
            outcome.timing.finishedAt = finishedAt
            return await finish(outcome)
        }
    }

    /// OpenCode HTTP SSE streaming over the warm serve API.
    public func invokeOpenCodeStreaming(
        prompt: String,
        modelLabel: String,
        directory: String,
        timeout: Duration,
        client: OpenCodeServeClient = OpenCodeServeClient()
    ) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        client.streamRun(
            prompt, modelLabel: modelLabel, directory: directory,
            autoApprove: true, timeout: timeout
        )
    }

    /// Brain-dir + pre-run entries for the AGY transcript normalizer (nil for non-agy workers).
    private func antigravityBrainSnapshot(manifest: DriverManifest) -> (url: URL, before: Set<String>)? {
        guard manifest.id == "antigravity", let dir = manifest.session?.capture?.dir else { return nil }
        let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        return (url, Self.directoryEntryNames(url))
    }

    /// Replace agy's (possibly narration-polluted) stdout answer with the clean final
    /// `PLANNER_RESPONSE` from the run's transcript, and lift the earlier steps onto
    /// `outcome.reasoning`. No-op (keeps raw stdout) if the session folder or transcript can't
    /// be resolved — never worse than today.
    private func applyAntigravityTranscript(_ outcome: inout WorkerRunOutcome, snapshot: (url: URL, before: Set<String>)?) {
        guard let snap = snapshot, outcome.status == .done,
              let sessionId = WorkerSessionCapture.capturedDirEntry(
                before: snap.before, after: Self.directoryEntryNames(snap.url)),
              let split = AntigravityTranscript.split(
                transcriptAt: AntigravityTranscript.transcriptURL(brainDir: snap.url, sessionId: sessionId)),
              !split.answer.isEmpty
        else { return }
        outcome.output = split.answer
        outcome.reasoning = split.reasoning.isEmpty ? nil : split.reasoning
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
        outputFileURL: URL?, startedAt: Date, finishedAt: Date, overrideFinalText: String? = nil,
        timeoutKind: WorkerSpawnDiagnostics.TimeoutKind = .wallClock,
        spawnCommand: String? = nil,
        spawnArgCount: Int? = nil,
        spawnWorkingDir: String? = nil,
        invocationKind: String? = nil
    ) -> WorkerRunOutcome {
        let durationMs = Int(finishedAt.timeIntervalSince(startedAt) * 1000)
        var outcome = WorkerRunOutcome(status: .running)
        outcome.timing.startedAt = startedAt
        outcome.timing.finishedAt = finishedAt
        outcome.timing.durationMs = durationMs
        if let spawnCommand, let spawnArgCount {
            outcome.spawnDiagnostics = Self.spawnDiagnostics(
                result: result, command: spawnCommand, argCount: spawnArgCount,
                workingDirectory: spawnWorkingDir, timeoutSeconds: invoke.timeoutSeconds,
                timeoutKind: timeoutKind, invocationKind: invocationKind)
        }

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
            switch timeoutKind {
            case .wallClock:
                outcome.errorReason = "wall-clock timeout after \(invoke.timeoutSeconds)s"
            case .idle:
                outcome.errorReason = "no output for \(invoke.timeoutSeconds)s"
            }
            outcome.output = preservedPartial()
            return outcome
        }
        if result.bufferOverflowed {
            outcome.status = .failed
            outcome.errorReason = "worker output exceeded the buffered-bytes cap"
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
        // path needs a vendor-specific post-exit extraction.
        let cleaned: String
        if overrideFinalText == nil && manifest.id == "grok" {
            cleaned = TextUtil.extractGrokStreamingVisibleText(stripped)
        } else if overrideFinalText == nil && manifest.id == "opencode" {
            cleaned = TextUtil.extractOpenCodeVisibleText(stripped)
        } else {
            cleaned = stripped
        }
        if let vendorFailure = vendorStdoutFailure(cleaned, manifest: manifest) {
            outcome.status = .failed
            outcome.errorKind = .timedOut
            outcome.errorReason = vendorFailure
            outcome.output = preservedPartial() ?? (cleaned.isEmpty ? nil : cleaned)
            return outcome
        }
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
        timeoutOverride: Duration? = nil,
        sessionPlan: WorkerSessionPlan? = nil
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
            var context = DriverManifest.ResolveContext(
                prompt: prompt, model: worker.resolvedLabel(at: effort),
                workingDir: driverWorkingDir, outputFile: outputFileURL?.path, effort: effort)
            // Worker_Session_Continuity: a resume turn / mint(set) overrides the argv with the
            // session-aware template; a capture/first turn keeps the base streaming args and
            // captures the new vendor id from output afterward.
            let (sessionArgs, plannedSessionId) = WorkerSessionPlanner.plan(sessionPlan) { id, resuming in
                context.resumeSessionId = id
                return manifest.resolvedSessionArgs(context, resuming: resuming)
            }
            let args = sessionArgs ?? manifest.resolvedStreamingArgs(context)
            // session_dir capture (agy): the CLI mints one conversation folder per turn 1 but
            // never prints its id. Snapshot the brain dir now; the single folder created during
            // this run is the vendor session id we resume next turn. Only on a first/capture turn.
            let dirCapture: (url: URL, before: Set<String>)? = {
                guard plannedSessionId == nil,
                      let session = sessionPlan?.session, session.continuity == .vendorSession,
                      session.acquire == .capture, let rule = session.capture,
                      rule.from == .sessionDir, let dir = rule.dir else { return nil }
                let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
                return (url, Self.directoryEntryNames(url))
            }()
            let stdin = manifest.stdinPrompt(context)
            let (spawnCommand, spawnArgs) = resolveSpawn(manifest: manifest, invoke: invoke, args: args)
            let invocationKind = invocationKindLabel(manifest: manifest)

            let gateRequestedAt = now()
            continuation.yield(.started(workerId: worker.id, modelId: worker.id, sourceId: manifest.id))
            StreamDebugLog.log("──── RUN START source=\(manifest.id) model=\(worker.id) cmd=\(spawnCommand) args=\(spawnArgs.joined(separator: " "))")

            let consume = Task { [self] in
                defer { if let outputFileURL { try? FileManager.default.removeItem(at: outputFileURL) } }
                // Per-driver spawn gate (see invoke()): fragile CLIs serialize here; the
                // streamed run is timeout-bounded so the permit always releases.
                let gateLimit = manifest.maxConcurrentSpawns
                let driverId = manifest.id
                var gateHeld = false
                if let gateLimit {
                    if let gateFailure = await acquireDriverSpawnGate(driverId: driverId, limit: gateLimit) {
                        continuation.yield(.failed(gateFailure))
                        return
                    }
                    gateHeld = true
                }
                // Stamp the work-time baseline AFTER the gate (matches invoke()) so durationMs and
                // ttftMs exclude serialization wait; gateWaitMs captures that wait on its own. Before
                // this, streaming stamped startedAt pre-gate and folded queue wait into durationMs —
                // the attribution split that made a queued seat look like a slow/failed run.
                let startedAt = now()
                let gateWaitMs = gateLimit == nil ? nil : max(0, Int(startedAt.timeIntervalSince(gateRequestedAt) * 1000))
                // TTFT: stamp the first visible streamed delta (answer or reasoning) — the
                // "dead air" the user waits through before anything renders.
                var firstTokenAt: Date?
                var firstStdoutAt: Date?
                var firstStderrAt: Date?
                var firstParsedEventAt: Date?
                var firstAnswerDeltaAt: Date?
                var lastAnswerDeltaAt: Date?
                var rawStdoutChunkCount = 0
                var rawStderrChunkCount = 0
                var parsedStreamEventCount = 0
                var answerDeltaCount = 0
                var reasoningDeltaCount = 0

                func recordParsed(_ streamEvent: WorkerStreamEvent) {
                    if firstParsedEventAt == nil { firstParsedEventAt = now() }
                    parsedStreamEventCount += 1
                    switch streamEvent {
                    case .answerDelta:
                        let t = now()
                        if firstTokenAt == nil { firstTokenAt = t }
                        if firstAnswerDeltaAt == nil { firstAnswerDeltaAt = t }
                        lastAnswerDeltaAt = t
                        answerDeltaCount += 1
                    case .reasoningDelta:
                        if firstTokenAt == nil { firstTokenAt = now() }
                        reasoningDeltaCount += 1
                    default:
                        break
                    }
                }

                func applyStreamMetrics(to outcome: inout WorkerRunOutcome) {
                    outcome.timing.firstTokenAt = firstTokenAt
                    if let firstTokenAt {
                        outcome.timing.ttftMs = Int(firstTokenAt.timeIntervalSince(startedAt) * 1000)
                    }
                    outcome.timing.firstStdoutAt = firstStdoutAt
                    outcome.timing.firstStderrAt = firstStderrAt
                    outcome.timing.firstParsedEventAt = firstParsedEventAt
                    outcome.timing.firstAnswerDeltaAt = firstAnswerDeltaAt
                    outcome.timing.lastAnswerDeltaAt = lastAnswerDeltaAt
                    outcome.timing.rawStdoutChunkCount = rawStdoutChunkCount
                    outcome.timing.rawStderrChunkCount = rawStderrChunkCount
                    outcome.timing.parsedStreamEventCount = parsedStreamEventCount
                    outcome.timing.answerDeltaCount = answerDeltaCount
                    outcome.timing.reasoningDeltaCount = reasoningDeltaCount
                }

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
                            rawStdoutChunkCount += 1
                            if firstStdoutAt == nil { firstStdoutAt = now() }
                            StreamDebugLog.log("STDOUT \(StreamDebugLog.clip(String(decoding: data, as: UTF8.self)))")
                            let parsed = parser.receiveStdout(data)
                            for streamEvent in parsed {
                                recordParsed(streamEvent)
                                StreamDebugLog.log("  → \(Self.describe(streamEvent))"); continuation.yield(streamEvent)
                            }
                        case .stderr(let data):
                            rawStderrChunkCount += 1
                            if firstStderrAt == nil { firstStderrAt = now() }
                            StreamDebugLog.log("STDERR \(StreamDebugLog.clip(String(decoding: data, as: UTF8.self)))")
                            for streamEvent in parser.receiveStderr(data) {
                                recordParsed(streamEvent)
                                continuation.yield(streamEvent)
                            }
                        case .completed(let result):
                            let fileText = outputFileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                            let finalText = parser.finalAnswer(result: result, outputFileText: fileText)
                            var outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText,
                                timeoutKind: .idle,
                                spawnCommand: spawnCommand,
                                spawnArgCount: spawnArgs.count,
                                spawnWorkingDir: spawnWorkingDir,
                                invocationKind: invocationKind)
                            // The vendor session this turn established/resumed — the caller
                            // persists it (on success) so the next turn resumes it.
                            outcome.capturedSessionId = WorkerSessionPlanner.capturedId(
                                sessionPlan, plannedSessionId: plannedSessionId,
                                stdout: result.stdout, outputFileContents: fileText)
                            if outcome.capturedSessionId == nil, let dc = dirCapture,
                               outcome.status == .done {
                                outcome.capturedSessionId = WorkerSessionCapture.capturedDirEntry(
                                    before: dc.before, after: Self.directoryEntryNames(dc.url))
                            }
                            applyStreamMetrics(to: &outcome)
                            outcome.timing.gateWaitMs = gateWaitMs
                            StreamDebugLog.log("OUTCOME status=\(outcome.status.rawValue) exit=\(result.exitCode.map(String.init) ?? "nil") outputLen=\(outcome.output?.count ?? 0) finalTextLen=\(finalText?.count ?? -1) session=\(outcome.capturedSessionId ?? "-")")
                            continuation.yield(outcome.status == .done ? .completed(outcome) : .failed(outcome))
                        case .failed(let launchError):
                            var outcome = WorkerRunOutcome(status: .failed)
                            outcome.timing.startedAt = startedAt
                            outcome.timing.finishedAt = now()
                            outcome.errorKind = .missingCLI
                            outcome.errorReason = launchError
                            applyStreamMetrics(to: &outcome)
                            outcome.timing.gateWaitMs = gateWaitMs
                            StreamDebugLog.log("OUTCOME launch-failed: \(launchError)")
                            continuation.yield(.failed(outcome))
                        case .timedOut(let partialOut, let partialErr):
                            let result = CommandResult(
                                stdout: String(decoding: partialOut, as: UTF8.self),
                                stderr: String(decoding: partialErr, as: UTF8.self), timedOut: true)
                            let finalText = parser.finalAnswer(result: result, outputFileText: nil)
                            var outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText,
                                timeoutKind: .idle,
                                spawnCommand: spawnCommand,
                                spawnArgCount: spawnArgs.count,
                                spawnWorkingDir: spawnWorkingDir,
                                invocationKind: invocationKind)
                            applyStreamMetrics(to: &outcome)
                            outcome.timing.gateWaitMs = gateWaitMs
                            continuation.yield(outcome.status == .done ? .completed(outcome) : .failed(outcome))
                        case .cancelled(let partialOut, let partialErr):
                            let result = CommandResult(
                                stdout: String(decoding: partialOut, as: UTF8.self),
                                stderr: String(decoding: partialErr, as: UTF8.self), cancelled: true)
                            let finalText = parser.finalAnswer(result: result, outputFileText: nil)
                            var outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText,
                                timeoutKind: .idle,
                                spawnCommand: spawnCommand,
                                spawnArgCount: spawnArgs.count,
                                spawnWorkingDir: spawnWorkingDir,
                                invocationKind: invocationKind)
                            applyStreamMetrics(to: &outcome)
                            outcome.timing.gateWaitMs = gateWaitMs
                            continuation.yield(.failed(outcome))
                        case .bufferOverflow(let partialOut, let partialErr):
                            // Fail-closed backstop (SubprocessBudget.maxBufferedBytes): the
                            // process group was killed for exceeding the buffered-bytes cap.
                            // Partial buffers preserved, distinct from `.timedOut` so a
                            // consumer can tell an OOM backstop apart from a hung worker.
                            let result = CommandResult(
                                stdout: String(decoding: partialOut, as: UTF8.self),
                                stderr: String(decoding: partialErr, as: UTF8.self), bufferOverflowed: true)
                            let finalText = parser.finalAnswer(result: result, outputFileText: nil)
                            var outcome = finalize(
                                result: result, worker: worker, manifest: manifest, invoke: invoke,
                                outputFileURL: outputFileURL, startedAt: startedAt, finishedAt: now(),
                                overrideFinalText: finalText,
                                timeoutKind: .idle,
                                spawnCommand: spawnCommand,
                                spawnArgCount: spawnArgs.count,
                                spawnWorkingDir: spawnWorkingDir,
                                invocationKind: invocationKind)
                            applyStreamMetrics(to: &outcome)
                            outcome.timing.gateWaitMs = gateWaitMs
                            continuation.yield(.failed(outcome))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                if gateHeld { await releaseDriverSpawnGate(driverId: driverId) }
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
        effort: EffortLevel = .med,
        workingDirectoryOverride: String? = nil
    ) async -> WorkerAnswer {
        let outcome: WorkerRunOutcome
        if manifest.canStream, supportsStreaming, let parser = StreamParserFactory.make(for: manifest) {
            var terminal: WorkerRunOutcome?
            do {
                for try await event in invokeStreaming(
                    worker: model, manifest: manifest, prompt: prompt, parser: parser, effort: effort,
                    workingDirectoryOverride: workingDirectoryOverride) {
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
                outcome = await invoke(worker: model, manifest: manifest, prompt: prompt, effort: effort,
                                       workingDirectoryOverride: workingDirectoryOverride)
            } else {
                outcome = streamed
            }
        } else {
            outcome = await invoke(worker: model, manifest: manifest, prompt: prompt, effort: effort,
                                   workingDirectoryOverride: workingDirectoryOverride)
        }
        return WorkerAnswer(
            workerId: assignment.id,
            modelId: model.id,
            status: outcome.status,
            output: outcome.output,
            errorKind: outcome.errorKind,
            errorReason: outcome.errorReason,
            startedAt: outcome.timing.startedAt,
            finishedAt: outcome.timing.finishedAt,
            durationMs: outcome.timing.durationMs,
            ttftMs: outcome.timing.ttftMs,
            gateWaitMs: outcome.timing.gateWaitMs,
            exitCode: outcome.exitCode,
            capacityObservation: outcome.capacityObservation,
            spawnDiagnostics: outcome.spawnDiagnostics
        )
    }

    /// One-line description of a stream event for the debug log.
    /// A streamed event the user actually SEES render (drives time-to-first-token).
    static func isVisibleDelta(_ event: WorkerStreamEvent) -> Bool {
        switch event {
        case .answerDelta, .reasoningDelta: return true
        default: return false
        }
    }

    /// The entry names directly under `url` (empty if unreadable). Used by `session_dir` capture
    /// to snapshot the agy brain dir before/after a run.
    static func directoryEntryNames(_ url: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
    }

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

    private func invocationKindLabel(manifest: DriverManifest) -> String {
        switch invocations[manifest.id] {
        case .direct: return "direct"
        case .shim: return "shim"
        case .loginShell: return "login_shell"
        case nil: return "ambient"
        }
    }

    private static func spawnDiagnostics(
        result: CommandResult,
        command: String,
        argCount: Int,
        workingDirectory: String?,
        timeoutSeconds: Int,
        timeoutKind: WorkerSpawnDiagnostics.TimeoutKind,
        invocationKind: String?
    ) -> WorkerSpawnDiagnostics {
        let stderr = TextUtil.stripANSI(result.stderr)
        let tail = String(stderr.suffix(512)).trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkerSpawnDiagnostics(
            command: command,
            argCount: argCount,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds,
            timeoutKind: timeoutKind,
            stdoutBytes: result.stdout.utf8.count,
            stderrBytes: result.stderr.utf8.count,
            stderrTail: tail.isEmpty ? nil : tail,
            invocationKind: invocationKind
        )
    }

    /// Vendor-reported failure embedded in stdout with exit 0 (agy does this).
    private func vendorStdoutFailure(_ text: String, manifest: DriverManifest) -> String? {
        guard manifest.id == "antigravity" else { return nil }
        if text.contains("Error: timed out waiting for response") {
            return "agy vendor timeout (stdout)"
        }
        return nil
    }
}
