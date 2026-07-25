import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln run` — the unified run entrypoint (Unified Run Model).
enum RunCLI {
    struct StreamOutcome: Equatable {
        var exitCode: Int
        var errorCode: String?
        var message: String?

        static let success = StreamOutcome(exitCode: 0, errorCode: nil, message: nil)
    }

    /// The stream branch's side effects are injected so its terminal behavior is
    /// executable without spawning a source CLI or writing the real journal.
    struct StreamDependencies {
        var run: @Sendable (AsyncStream<RunEvent>.Continuation) async -> Result<TeamRun, RunServiceError>
        var append: (RunEvent) throws -> RunEvent
        var liveLine: (RunEvent) -> String?
        var closingLine: () -> String?
        var writeLine: (String) -> Void
        var emitFailure: (String, String) -> Void
    }

    static func streamOutcome(for error: RunServiceError?) -> StreamOutcome {
        guard let error else { return .success }
        return StreamOutcome(exitCode: 1, errorCode: error.code, message: error.description)
    }

    static func streamJournalFailure(_ error: Error) -> StreamOutcome {
        StreamOutcome(
            exitCode: 1,
            errorCode: "STREAM_JOURNAL_FAILED",
            message: "could not persist a stream event: \(error)"
        )
    }

    /// The common implementation for `alln run --stream`. It returns the exact
    /// exit outcome after emitting any terminal typed error; the command entry
    /// point owns the actual process exit.
    static func runStream(_ dependencies: StreamDependencies) async -> StreamOutcome {
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let run = dependencies.run
        let runTask = Task { await run(continuation) }
        var journalFailure: StreamOutcome?
        for await event in stream {
            let stamped: RunEvent
            do {
                stamped = try dependencies.append(event)
            } catch {
                journalFailure = streamJournalFailure(error)
                continuation.finish()
                break
            }
            if let line = dependencies.liveLine(stamped) { dependencies.writeLine(line) }
        }

        let result = await runTask.value
        let outcome: StreamOutcome
        if let journalFailure {
            outcome = journalFailure
        } else if case let .failure(error) = result {
            outcome = streamOutcome(for: error)
        } else {
            outcome = .success
        }
        if let code = outcome.errorCode {
            dependencies.emitFailure(code, outcome.message ?? "stream run failed")
        } else if let closing = dependencies.closingLine() {
            dependencies.writeLine(closing)
        }
        return outcome
    }

    /// PO-F5 / RLR-L8: parse a positive integer seconds flag (`--idle-timeout`,
    /// `--handshake-timeout`, `--first-activity-timeout`, `--wall-timeout`).
    /// `nil` raw → ok(nil) (use product/manifest default). Non-numeric / non-positive → error.
    static func parsePositiveTimeoutSeconds(_ raw: String?, flag: String) -> (value: Int?, error: String?) {
        guard let raw else { return (nil, nil) }
        guard let value = Int(raw), value > 0 else {
            return (nil, "\(flag) must be a positive integer number of seconds, got '\(raw)'")
        }
        return (value, nil)
    }

    /// PO-F5: parse `--idle-timeout <seconds>` for `RunRequest.workerTimeoutSeconds`.
    static func parseIdleTimeoutSeconds(_ raw: String?) -> (value: Int?, error: String?) {
        parsePositiveTimeoutSeconds(raw, flag: "--idle-timeout")
    }

    static func run(_ args: [String], runtime: ToolRuntime) async {
        if args.first == "resume" {
            await resume(Array(args.dropFirst()), runtime: runtime)
            return
        }
        let opts = Options(args)
        guard let message = opts.positional.first ?? opts.value("message") else {
            FileHandle.standardError.write(Data(
                "usage: alln run \"<message>\" [--project <id|path>] [--dry-run] [...]\n       alln run resume <runId> [--json]\n"
                    .utf8))
            exit(2)
        }

        // Mutual-exclusion / requires / onlyWith live in ContractRegistry and are
        // gated in `AllnighterCLI.main` via `CLIUsage.validateFlagConstraints`.
        let noCommit = opts.flag("no-commit")
        let commitMessage = opts.value("commit-message")

        let store = ProjectStore()
        let project: Project
        if let projectToken = opts.value("project") {
            guard let resolved = AllnighterCLI.resolveProject(projectToken, store: store) else {
                AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
            }
            project = resolved
        } else if let resolved = AllnighterCLI.resolveProjectFromCwd(store: store) {
            project = resolved
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            let gitRoot = GitObserver().repoTopLevel(forPath: cwd) ?? cwd
            AllnighterCLI.fail(
                code: "PROJECT_NOT_FOUND",
                message: "no registered project for \(gitRoot) — run `alln project add \(gitRoot)`"
            )
        }

        let effort = opts.value("effort").flatMap(EffortLevel.init(rawValue:))
        if let raw = opts.value("effort"), effort == nil {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "unknown effort: \(raw)")
        }
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw)")
        }

        // MR-S04: exact-id choke point before dry-run soft path or any RunRecord mint.
        AllnighterCLI.requireExactSelectors(
            workerId: opts.value("worker"),
            teamId: opts.value("team"),
            models: runtime.models,
            teams: runtime.teams
        )

        if opts.flag("dry-run") {
            await emitDryRun(project: project, opts: opts, runtime: runtime)
            return
        }

        let idleParsed = parsePositiveTimeoutSeconds(opts.value("idle-timeout"), flag: "--idle-timeout")
        if let message = idleParsed.error {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: message)
        }
        let handshakeParsed = parsePositiveTimeoutSeconds(
            opts.value("handshake-timeout"), flag: "--handshake-timeout")
        if let message = handshakeParsed.error {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: message)
        }
        let firstActivityParsed = parsePositiveTimeoutSeconds(
            opts.value("first-activity-timeout"), flag: "--first-activity-timeout")
        if let message = firstActivityParsed.error {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: message)
        }
        let wallParsed = parsePositiveTimeoutSeconds(opts.value("wall-timeout"), flag: "--wall-timeout")
        if let message = wallParsed.error {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: message)
        }

        let tryFix = opts.flag("try-fix")
        let request = RunRequest(
            message: message,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            presetId: opts.value("team"),
            workerId: opts.value("worker"),
            effort: effort,
            lane: lane,
            type: opts.value("type"),
            context: opts.value("context"),
            executorTeamId: opts.value("executor"),
            workerTimeoutSeconds: idleParsed.value,
            handshakeTimeoutSeconds: handshakeParsed.value,
            firstActivityTimeoutSeconds: firstActivityParsed.value,
            wallTimeoutSeconds: wallParsed.value,
            commitMessage: commitMessage,
            noCommit: noCommit,
            proofCommand: opts.value("proof"),
            idempotencyKey: opts.value("idempotency-key"),
            retryOf: opts.value("retry-of"),
            acceptSurvivors: opts.flag("accept-survivors")
        )
        let service = RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            invocations: runtime.invocations
        )

        if tryFix {
            await runTryFix(request, service: service, runtime: runtime, project: project, json: opts.flag("json"))
            return
        }

        if opts.flag("stream") {
            let journal = RemoteRunEventJournal()
            let attachment = NDJSONStreamProjector.NDJSONAttachment()
            let originAgent = opts.value("agent")
            // The streamed run is captured so a sandboxed host can hand it off
            // after the fact — the stream branch never reaches the hand-off below.
            let streamed = StreamedRunBox()
            let outcome = await runStream(.init(
                run: { continuation in
                    let result = await service.run(
                        request, origin: .cli, originAgent: originAgent, events: continuation)
                    if case .success(let run) = result { streamed.value = run }
                    return result
                },
                append: { try journal.append($0) },
                liveLine: { attachment.liveLine(for: $0) },
                closingLine: { attachment.closingLine() },
                writeLine: { print($0) },
                emitFailure: { AllnighterCLI.emitFailure(code: $0, message: $1) }
            ))
            // Every seat failed because this terminal is sandboxed: hand the same
            // request to the app and print the answer, instead of leaving the user
            // with an empty stream.
            if let run = streamed.value,
               let handed = await SandboxHandoff.runInApp(failedRun: run, request: request) {
                renderRun(handed, runtime: runtime, project: project, json: opts.flag("json"))
                return
            }
            if outcome.exitCode != 0 {
                exit(Int32(outcome.exitCode))
            }
            return
        }

        var result = await service.run(request, origin: .cli, originAgent: opts.value("agent"))
        // Inside a sandboxed terminal the vendor CLIs cannot sign in, so the run
        // comes back with every seat failed. Hand it to the Allnighter app, which
        // is not sandboxed, and wait for the answer here. Same run id, same
        // journal — the caller never leaves this terminal.
        if case .success(let run) = result,
           let handed = await SandboxHandoff.runInApp(failedRun: run, request: request) {
            result = .success(handed)
        }
        // A run that never STARTED has no worker failure to detect, so the signature
        // path above can never fire for it — and a sandbox is perfectly capable of
        // breaking resolution itself, by denying the readiness probes. Inside a
        // restricted host, let the app try. If it refuses too, S1 returns its real
        // error, so being wrong costs one mailbox round trip rather than a wrong
        // answer.
        if case .failure(let error) = result,
           error.retryOutsideRestrictedHost,
           HostSandboxAdvice.hostIsRestricted(),
           let handed = await SandboxHandoff.runInAppAfterPreflightFailure(request: request) {
            result = .success(handed)
        }
        switch result {
        case .failure(let error):
            AllnighterCLI.emitFailure(code: error.code, message: error.description)
            exit(1)
        case .success(let run):
            renderRun(run, runtime: runtime, project: project, json: opts.flag("json"))
            let code = exitCode(for: run)
            if code != 0 { exit(code) }
        }
    }

    /// One renderer for a finished run, so a locally executed run and one the app
    /// executed on our behalf are reported identically.
    private static func renderRun(
        _ run: TeamRun, runtime: ToolRuntime, project: Project, json: Bool
    ) {
        if json {
            let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?
                .appendingPathComponent("run.json").path ?? ""
            let context = TeamRunJSONMapper.Context(
                promptSource: .init(kind: .positional, path: nil),
                runJournalPath: journalPath,
                reproduceCommand: reproduceCommand(run, project: project)
            )
            let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: context)
            print(AllnighterCLI.jsonString(trj))
        } else {
            // A run that never produced an answer still has something to say — a
            // refused hand-off carries its reason in `warnings`. Printing only
            // "(run failed)" here is how a real, specific error became silence.
            let answer = AllnighterCLI.humanAnswer(for: run, models: runtime.models, manifests: runtime.registry.all)
            if let answer, !answer.isEmpty {
                print(answer)
            } else if !run.warnings.isEmpty {
                print(run.warnings.joined(separator: "\n"))
            } else {
                print("(run \(run.status.rawValue))")
            }
            FileHandle.standardError.write(Data("\n[\(RunIdentity.cliFooter(run))]\n".utf8))
        }
    }

    /// CR-S02 — parse flags + look up runtime facts, then hand the whole resolution to
    /// the single owner (`RunService.dryRun`). The CLI computes NO team/root/write-lock
    /// semantics here; it observes the governor verdict + ready bench (runtime facts) and
    /// renders `RunService`'s `RunDryRunJSON` projection. Dry-run always exits 0 —
    /// `canStart` carries the verdict (AE-S04).
    private static func emitDryRun(
        project: Project,
        opts: Options,
        runtime: ToolRuntime
    ) async {
        var governorAvailable = true
        var governorBlockedReason: String?
        switch runtime.governor.availability() {
        case .available:
            break
        case .busy:
            governorAvailable = false
            governorBlockedReason = "busy: \(runtime.config.maxConcurrentTeamRuns) team runs already running"
        case .unavailable(let reason):
            governorAvailable = false
            governorBlockedReason = reason
        }

        let request = RunRequest(
            message: opts.positional.first ?? opts.value("message") ?? "",
            repoRoot: project.normalizedRootPath,
            threadId: opts.value("thread-id"),
            projectId: project.id,
            presetId: opts.value("team"),
            workerId: opts.value("worker"),
            effort: opts.value("effort").flatMap(EffortLevel.init(rawValue:)),
            lane: opts.value("lane").flatMap(WorkLane.init(rawValue:)),
            type: opts.value("type"),
            context: opts.value("context"),
            executorTeamId: opts.value("executor"),
            workerTimeoutSeconds: parsePositiveTimeoutSeconds(
                opts.value("idle-timeout"), flag: "--idle-timeout").value,
            handshakeTimeoutSeconds: parsePositiveTimeoutSeconds(
                opts.value("handshake-timeout"), flag: "--handshake-timeout").value,
            firstActivityTimeoutSeconds: parsePositiveTimeoutSeconds(
                opts.value("first-activity-timeout"), flag: "--first-activity-timeout").value,
            wallTimeoutSeconds: parsePositiveTimeoutSeconds(
                opts.value("wall-timeout"), flag: "--wall-timeout").value,
            commitMessage: opts.value("commit-message"),
            noCommit: opts.flag("no-commit"),
            proofCommand: opts.value("proof"),
            idempotencyKey: opts.value("idempotency-key"),
            retryOf: opts.value("retry-of"),
            acceptSurvivors: opts.flag("accept-survivors")
        )
        let service = RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            invocations: runtime.invocations
        )
        let payload = await service.dryRun(
            request,
            readyModels: runtime.readyModels,
            agent: opts.value("agent"),
            conversationId: opts.value("conversation-id"),
            messageId: opts.value("message-id"),
            governorAvailable: governorAvailable,
            governorBlockedReason: governorBlockedReason
        )
        print(AllnighterCLI.jsonString(payload))
    }

    /// `alln run resume <runId>` — claim a parked vendor wait and resume the
    /// same run in-process (never a second `alln run` spawn).
    private static func resume(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let runId = opts.positional.first else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "usage: alln run resume <runId> [--json]")
        }
        let store = RunStore()
        guard let parked = store.loadRaw(runId: runId) ?? store.load(runId: runId) else {
            AllnighterCLI.fail(code: "RUN_NOT_FOUND", message: "run not found: \(runId)")
        }
        // A run someone else is executing — a hand-off the app took while this
        // terminal was away — cannot be "resumed" here; it is already running. Wait
        // for it and print it. Without this, a caller killed mid-wait had no way to
        // collect an answer the app had already produced.
        let isVendorPark = parked.status == .queued
            && parked.phase == .waitingForVendor
            && parked.blocker?.resource == .vendorBackoff
        if !isVendorPark {
            if parked.status.isTerminal {
                printRunWithoutProject(
                    parked, runtime: runtime,
                    reproduceCommand: "alln run resume \(runId)", json: opts.flag("json"), store: store)
                let code = exitCode(for: parked)
                if code != 0 { exit(code) }
                return
            }
            guard let finished = await SandboxHandoff.waitForHandoff(
                runId: runId, requestId: nil,
                spool: SandboxHandoffSpool(), runStore: store
            ) else {
                AllnighterCLI.fail(
                    code: "RUN_NOT_TERMINAL",
                    message: "run \(runId) is still not finished — see the note above"
                )
            }
            printRunWithoutProject(
                finished, runtime: runtime,
                reproduceCommand: "alln run resume \(runId)", json: opts.flag("json"), store: store)
            let code = exitCode(for: finished)
            if code != 0 { exit(code) }
            return
        }
        let coordinatorId = "cli:\(ProcessInfo.processInfo.processIdentifier)"
        guard store.claimVendorWake(
            runId: runId,
            coordinatorId: coordinatorId,
            now: Date(),
            force: true
        ) != nil else {
            AllnighterCLI.fail(
                code: "VENDOR_WAKE_NOT_CLAIMED",
                message: "could not claim vendor wake lease for \(runId)"
            )
        }
        let service = RunService(
            models: runtime.models,
            registry: runtime.registry,
            teams: runtime.teams,
            runStore: store,
            invocations: runtime.invocations
        )
        let result = await service.resumeParkedRun(
            runId: runId,
            coordinatorId: coordinatorId,
            selectionOrigin: MorningReceipt.manualResumeOrigin
        )
        switch result {
        case .failure(let error):
            AllnighterCLI.emitFailure(code: error.code, message: error.description)
            exit(1)
        case .success(let run):
            if opts.flag("json") {
                let journalPath = (try? store.runDirectory(forRunId: run.id))?
                    .appendingPathComponent("run.json").path ?? ""
                let context = TeamRunJSONMapper.Context(
                    promptSource: .init(kind: .positional, path: nil),
                    runJournalPath: journalPath,
                    reproduceCommand: "alln run resume \(run.id) --json"
                )
                let trj = TeamRunJSONMapper.map(
                    run, models: runtime.models, manifests: runtime.registry.all, context: context
                )
                print(AllnighterCLI.jsonString(trj))
            } else if run.phase == .waitingForVendor,
                      let blocker = run.blocker,
                      let source = blocker.capacityObservation?.source ?? blocker.quotaScope {
                print(VendorContinuityPresentation.waitStatus(
                    vendorDisplayName: VendorContinuityPresentation.vendorDisplayName(sourceId: source),
                    wakeAfter: blocker.wakeAfter
                ))
                FileHandle.standardError.write(Data("\n[\(RunIdentity.cliFooter(run))]\n".utf8))
            } else {
                printRunWithoutProject(
                    run, runtime: runtime,
                    reproduceCommand: "alln run resume \(run.id)", json: false, store: store)
            }
        }
    }

    /// Process exit for a finished run, on the frozen public lifecycle axis.
    ///
    /// A run that failed, timed out, was cancelled or was interrupted used to exit
    /// **0**, identical to success. An agent host has no other signal — that is how
    /// an interrupted six-seat review looked, from inside Codex, like a command that
    /// simply produced nothing. `partial` stays 0: some seats answered, and their
    /// answers are real.
    static func exitCode(for run: TeamRun) -> Int32 {
        switch run.status.lifecycle {
        case .done: return 0
        case .failed, .timedOut, .cancelled: return 1
        case .queued, .running: return 0   // not terminal; the caller is still waiting
        }
    }

    /// Prints a finished run on the paths that hold no `Project` (resume / attach).
    ///
    /// Shares `renderRun`'s rule that a run with no answer still has something to
    /// say: a refused hand-off carries its reason in `warnings`, and printing only
    /// "(run failed)" is how a specific error became silence.
    static func printRunWithoutProject(
        _ run: TeamRun, runtime: ToolRuntime, reproduceCommand: String, json: Bool,
        store: RunStore = RunStore()
    ) {
        if json {
            let journalPath = (try? store.runDirectory(forRunId: run.id))?
                .appendingPathComponent("run.json").path ?? ""
            let context = TeamRunJSONMapper.Context(
                promptSource: .init(kind: .positional, path: nil),
                runJournalPath: journalPath,
                reproduceCommand: reproduceCommand
            )
            print(AllnighterCLI.jsonString(TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all, context: context)))
            return
        }
        let answer = AllnighterCLI.humanAnswer(
            for: run, models: runtime.models, manifests: runtime.registry.all)
        if let answer, !answer.isEmpty {
            print(answer)
        } else if !run.warnings.isEmpty {
            print(run.warnings.joined(separator: "\n"))
        } else {
            print("(run \(run.status.rawValue))")
        }
        FileHandle.standardError.write(Data("\n[\(RunIdentity.cliFooter(run))]\n".utf8))
    }

    /// `alln run --try-fix`: the elimination-loop chain — a read-only Bug Hunt diagnosis, the
    /// danger-not-doubt gate, and (when allowed) ONE child execution that tries the top
    /// hypothesis. Emits a `TryFixChainJSON` (or a human summary).
    private static func runTryFix(
        _ request: RunRequest, service: RunService, runtime: ToolRuntime, project: Project, json: Bool
    ) async {
        let coordinator = FollowUpCoordinator(runService: service)
        let result = await coordinator.runTryFix(request, origin: .cli)
        guard case .success(let outcome) = result else {
            if case .failure(let error) = result {
                AllnighterCLI.emitFailure(code: error.code, message: error.description)
            }
            exit(1)
        }

        let chain = chainJSON(outcome, runtime: runtime, project: project)
        if json {
            print(AllnighterCLI.jsonString(chain))
        } else {
            print(humanSummary(chain, outcome: outcome))
            FileHandle.standardError.write(Data(
                "\n[diagnosis \(outcome.parentRun.id)\(outcome.childRun.map { " · fix \($0.id)" } ?? "")]\n".utf8))
        }
        // Non-zero exit when the gate refused, so scripts can branch on it.
        if outcome.childRun == nil, case .blocked = outcome.gate { exit(1) }
    }

    private static func chainJSON(
        _ outcome: FollowUpCoordinator.Outcome, runtime: ToolRuntime, project: Project
    ) -> TryFixChainJSON {
        func mapRun(_ run: TeamRun) -> TeamRunJSON {
            TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: AllnighterCLI.defaultRunContext(run))
        }
        let status: TryFixChainJSON.Status =
            outcome.childRun != nil ? .fixAttempted
            : (outcome.packet == nil ? .noPacket : .blocked)
        let next: String
        switch status {
        case .fixAttempted:
            next = "Read the fix attempt. If it's still broken, the report names what this round ruled out — run --try-fix again to narrow."
        case .blocked:
            if case .blocked(_, let reason) = outcome.gate { next = "Gate refused: \(reason). Resolve it, then retry." }
            else { next = "Gate refused. Resolve it, then retry." }
        case .noPacket:
            next = "The diagnosis produced no typed fix packet. Re-run Bug Hunt with a sharper report."
        }
        return TryFixChainJSON(
            contractVersion: ContractRegistry.contractVersion,
            status: status,
            diagnosis: mapRun(outcome.parentRun),
            gate: .from(outcome.gate),
            packet: outcome.packet,
            fixAttempt: outcome.childRun.map(mapRun),
            nextStep: next)
    }

    private static func humanSummary(_ chain: TryFixChainJSON, outcome: FollowUpCoordinator.Outcome) -> String {
        var lines: [String] = []
        lines.append("# Diagnosis (\(outcome.parentRun.status.rawValue))")
        lines.append(outcome.parentRun.plan ?? "(no diagnosis output)")
        switch chain.status {
        case .fixAttempted:
            lines.append("\n# Fix attempt (\(outcome.childRun?.status.rawValue ?? "?"))")
            if case .allowed(let topId) = outcome.gate { lines.append("Tried hypothesis \(topId) within its boundary.") }
            lines.append(outcome.childRun?.plan ?? outcome.childRun?.workerAnswers.first?.output ?? "(no fix output)")
        case .blocked:
            lines.append("\n# No fix attempt — \(chain.gate.code ?? "blocked"): \(chain.gate.reason ?? "")")
        case .noPacket:
            lines.append("\n# No fix attempt — the diagnosis produced no typed fix packet.")
        }
        lines.append("\n→ \(chain.nextStep ?? "")")
        return lines.joined(separator: "\n")
    }

    /// ADP-S01 — a runnable `alln run` replay that round-trips every explicit
    /// selector the original run resolved with, so re-running it lands on the same
    /// seats and write policy: the prompt, `--project`, `--team`, each explicit
    /// `--worker`, `--effort`, `--lane` (only when it was explicit context alongside
    /// a pinned worker), and `--no-commit` when the run was ordered to leave work
    /// uncommitted.
    static func reproduceCommand(_ run: TeamRun, project: Project) -> String {
        var parts = ["alln run"]
        if !run.prompt.isEmpty { parts.append("\"\(run.prompt)\"") }
        parts.append(contentsOf: ["--project", project.id])
        if let team = run.presetId { parts.append(contentsOf: ["--team", team]) }
        for worker in run.explicitWorkerIds ?? [] where !worker.isEmpty {
            parts.append(contentsOf: ["--worker", worker])
        }
        if let effort = run.effort { parts.append(contentsOf: ["--effort", effort.rawValue]) }
        if run.laneContextOnly == true, let lane = run.lane {
            parts.append(contentsOf: ["--lane", lane.rawValue])
        }
        if run.noCommitOrdered == true { parts.append("--no-commit") }
        return parts.joined(separator: " ")
    }
}
