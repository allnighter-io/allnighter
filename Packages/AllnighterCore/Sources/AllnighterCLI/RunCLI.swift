import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln run` — the unified run entrypoint (Unified Run Model).
enum RunCLI {
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
            await emitDryRun(
                project: project,
                teamId: opts.value("team"),
                workerId: opts.value("worker"),
                effort: effort,
                lane: lane,
                type: opts.value("type"),
                opts: opts,
                runtime: runtime
            )
            return
        }

        if opts.flag("detach") {
            await runDetached(
                message: message,
                project: project,
                teamId: opts.value("team"),
                workerId: opts.value("worker"),
                effort: effort,
                lane: lane,
                type: opts.value("type"),
                opts: opts,
                runtime: runtime
            )
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
            // RLR-S03b: route the live stream through the durable RemoteRunEventJournal
            // so each line carries its monotonic per-Mac `seq` (survives coordinator
            // restart + reattach), and enforce exactly-one-terminal per attachment.
            let journal = RemoteRunEventJournal()
            let attachment = NDJSONStreamProjector.NDJSONAttachment()
            let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
            let runTask = Task {
                _ = await service.run(request, origin: .cli, originAgent: opts.value("agent"), events: continuation)
            }
            for await event in stream {
                // Allocate the durable seq at append; fall back to the un-stamped event
                // if the journal cannot record it (e.g. missing runId) so the stream
                // never stalls.
                let stamped = (try? journal.append(event)) ?? event
                if let line = attachment.liveLine(for: stamped) { print(line) }
            }
            _ = await runTask.value
            // RLR-L7: an attachment always ends in exactly one terminal — synthesize
            // one if the stream closed without a terminal status event.
            if let closing = attachment.closingLine() { print(closing) }
            return
        }

        let result = await service.run(request, origin: .cli, originAgent: opts.value("agent"))
        switch result {
        case .failure(let error):
            AllnighterCLI.emitFailure(code: error.code, message: error.description)
            exit(1)
        case .success(let run):
            if opts.flag("json") {
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
                print(AllnighterCLI.humanAnswer(for: run, models: runtime.models, manifests: runtime.registry.all)
                      ?? "(run \(run.status.rawValue))")
                FileHandle.standardError.write(Data("\n[\(RunIdentity.cliFooter(run))]\n".utf8))
            }
        }
    }

    /// `alln run --detach` — async start; forks a self-owning runner (former `team start`).
    private static func runDetached(
        message: String,
        project: Project,
        teamId: String?,
        workerId: String?,
        effort: EffortLevel?,
        lane: WorkLane?,
        type: String?,
        opts: Options,
        runtime: ToolRuntime
    ) async {
        let request = AsyncTeamStartRequest(
            question: message,
            lane: lane,
            teamPresetId: teamId,
            effort: effort,
            modelId: workerId,
            type: type,
            context: opts.value("context"),
            threadId: opts.value("thread-id"),
            originAgent: opts.value("agent"),
            originConversationId: opts.value("conversation-id"),
            originMessageId: opts.value("message-id"),
            idempotencyKey: opts.value("idempotency-key"),
            repoRoot: project.normalizedRootPath
        )
        guard let executable = ProcessOwnership.currentExecutablePath() else {
            AllnighterCLI.emitFailure(code: "INTERNAL_ERROR", message: "could not resolve alln executable path")
            exit(1)
        }
        let outcome = await runtime.asyncTeamService().start(
            request,
            origin: .cli,
            readyModels: runtime.readyModels,
            ownership: .detachedRunner(executablePath: executable)
        )
        switch outcome {
        case .success(let response):
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(response))
            } else {
                print(response.runId)
            }
        case .failure(let refusal):
            AllnighterCLI.emitFailure(code: refusal.code, message: refusal.message)
            exit(1)
        }
    }

    /// AE-S04 / SH-S01: project `RunDryRunJSON` from one `ResolvedRunInvocation`.
    /// Never re-resolves team/worker/seats independently of foreground/detach.
    private static func emitDryRun(
        project: Project,
        teamId: String?,
        workerId: String?,
        effort: EffortLevel?,
        lane: WorkLane?,
        type: String?,
        opts: Options,
        runtime: ToolRuntime
    ) async {
        let root = project.normalizedRootPath
        let provisionalMutating = TeamCatalog.get(teamId ?? "")?.mutating
            ?? (teamId == nil ? TeamCatalog.defaultRunTeam()?.mutating : nil)
            ?? false
        var writeLockHeld: Bool?
        if provisionalMutating {
            let key = ExecutionLane.key(repoRoot: root)
            writeLockHeld = await RunWriteLockRegistry.shared.isHeld(key)
        }

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

        let readyIds = Set(runtime.readyModels.map(\.id))
        let input = RunInvocationInput(
            message: opts.positional.first ?? opts.value("message") ?? "",
            projectRoot: root,
            flagMode: .dryRun,
            flags: RunInvocationNormalizedFlags(
                projectId: project.id,
                teamId: teamId,
                workerId: workerId,
                effort: effort,
                lane: lane,
                type: type,
                context: opts.value("context"),
                json: true,
                noCommit: opts.flag("no-commit"),
                acceptSurvivors: opts.flag("accept-survivors"),
                commitMessage: opts.value("commit-message"),
                proofCommand: opts.value("proof"),
                executorTeamId: opts.value("executor"),
                idleTimeoutSeconds: RunCLI.parsePositiveTimeoutSeconds(
                    opts.value("idle-timeout"), flag: "--idle-timeout").value,
                handshakeTimeoutSeconds: RunCLI.parsePositiveTimeoutSeconds(
                    opts.value("handshake-timeout"), flag: "--handshake-timeout").value,
                firstActivityTimeoutSeconds: RunCLI.parsePositiveTimeoutSeconds(
                    opts.value("first-activity-timeout"), flag: "--first-activity-timeout").value,
                wallTimeoutSeconds: RunCLI.parsePositiveTimeoutSeconds(
                    opts.value("wall-timeout"), flag: "--wall-timeout").value,
                idempotencyKey: opts.value("idempotency-key"),
                retryOf: opts.value("retry-of"),
                threadId: opts.value("thread-id"),
                conversationId: opts.value("conversation-id"),
                messageId: opts.value("message-id"),
                agent: opts.value("agent")
            )
        )
        let resolved = RunInvocationResolver.resolve(
            input,
            context: RunInvocationResolveContext(
                models: runtime.models,
                teams: runtime.teams,
                readyModels: runtime.readyModels,
                readyModelIds: readyIds,
                defaultSettings: DefaultModelSettingsPersistence().load(),
                writeLockHeld: writeLockHeld,
                governorAvailable: governorAvailable,
                governorBlockedReason: governorBlockedReason
            )
        )
        var payload = resolved.makeDryRunJSON()
        if !resolved.canStart, resolved.explicitWorkerChosen {
            let reason = resolved.blockedReason ?? ""
            if reason.localizedCaseInsensitiveContains("notReady")
                || reason.localizedCaseInsensitiveContains("disabled")
                || reason.localizedCaseInsensitiveContains("unknown")
                || reason.localizedCaseInsensitiveContains("not a runnable") {
                payload.nextAction = AgentNextAction(
                    kind: "listModels",
                    label: "List models",
                    command: "alln models --json")
            }
        }
        print(AllnighterCLI.jsonString(payload))
        // Dry-run always exits 0 — canStart carries the verdict (AE-S04).
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
        guard parked.status == .queued,
              parked.phase == .waitingForVendor,
              parked.blocker?.resource == .vendorBackoff else {
            AllnighterCLI.fail(
                code: "VENDOR_WAKE_NOT_CLAIMED",
                message: "run \(runId) is not parked waiting for a vendor"
            )
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
                print(AllnighterCLI.humanAnswer(for: run, models: runtime.models, manifests: runtime.registry.all)
                      ?? "(run \(run.status.rawValue))")
                FileHandle.standardError.write(Data("\n[\(RunIdentity.cliFooter(run))]\n".utf8))
            }
        }
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

    static func reproduceCommand(_ run: TeamRun, project: Project) -> String {
        var parts = ["alln run", "--project", project.id]
        if let team = run.presetId { parts.append(contentsOf: ["--team", team]) }
        if let effort = run.effort { parts.append(contentsOf: ["--effort", effort.rawValue]) }
        return parts.joined(separator: " ")
    }
}
