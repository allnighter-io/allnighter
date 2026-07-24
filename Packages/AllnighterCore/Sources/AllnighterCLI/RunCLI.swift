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

        // These chains have no resident event/reply contract yet. Failing closed
        // is intentional: falling back to a caller-owned vendor spawn would
        // recreate the sandbox bug this broker exists to remove.
        if opts.flag("try-fix") {
            AllnighterCLI.fail(
                code: "RESIDENT_REQUEST_REJECTED",
                message: "--try-fix is awaiting resident follow-up routing; direct foreground execution is disabled"
            )
        }

        let request = ResidentExecutionOperation.ForegroundTeamRunRequest(
            message: message,
            repoRoot: project.normalizedRootPath,
            projectId: project.id,
            presetId: opts.value("team"),
            workerId: opts.value("worker"),
            effort: effort,
            lane: lane,
            type: opts.value("type"),
            context: opts.value("context"),
            originAgent: opts.value("agent"),
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
        await runForegroundThroughResident(request, json: opts.flag("json"), stream: opts.flag("stream"))
    }

    private static func runForegroundThroughResident(
        _ request: ResidentExecutionOperation.ForegroundTeamRunRequest,
        json: Bool,
        stream: Bool = false
    ) async {
        let rendezvous = ResidentExecutionRendezvous()
        let runId: String
        let requestId: String
        do {
            let submitted = try rendezvous.submit(
                operation: .foregroundTeamRun(request),
                idempotencyKey: request.idempotencyKey ?? UUID().uuidString.lowercased()
            )
            requestId = submitted.requestId
            guard let receipt = try await rendezvous.waitForReceipt(requestId: submitted.requestId) else {
                AllnighterCLI.fail(
                    code: "RESIDENT_ACCEPT_TIMEOUT",
                    message: "resident coordinator did not accept the foreground run before timeout"
                )
            }
            if let rejection = receipt.rejection {
                AllnighterCLI.fail(code: rejection.code, message: rejection.message)
            }
            guard case let .teamStart(response) = receipt.result else {
                AllnighterCLI.fail(
                    code: "RESIDENT_REQUEST_REJECTED",
                    message: "resident coordinator accepted an invalid foreground run response"
                )
            }
            runId = response.runId
        } catch ResidentExecutionRendezvous.Error.unavailable {
            AllnighterCLI.fail(
                code: "COORDINATOR_UNAVAILABLE",
                message: "resident coordinator is unavailable; enable it with `alln serve install`"
            )
        } catch {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident run request failed: \(error)")
        }

        var eventCursor = 0
        while true {
            if stream, let events = try? rendezvous.eventsAfter(requestId: requestId, sequence: eventCursor) {
                for event in events {
                    print(AllnighterCLI.jsonLine(event))
                    eventCursor = max(eventCursor, event.sequence)
                }
            }
            let receipt = await AllnighterCLI.residentTeamQuery(.runStatus, runId: runId)
            guard case let .teamStatus(status) = receipt.result else {
                AllnighterCLI.fail(
                    code: "RESIDENT_REQUEST_REJECTED",
                    message: "resident coordinator returned an invalid foreground status response"
                )
            }
            if status.status.isTerminal { break }
            try? await Task.sleep(for: .milliseconds(min(max(status.nextPollAfterMs, 50), 5_000)))
        }

        let receipt = await AllnighterCLI.residentTeamQuery(.runResult, runId: runId)
        guard case let .teamResult(result) = receipt.result else {
            AllnighterCLI.fail(
                code: "RESIDENT_REQUEST_REJECTED",
                message: "resident coordinator did not return a terminal foreground result"
            )
        }
        if stream {
            if let events = try? rendezvous.eventsAfter(requestId: requestId, sequence: eventCursor) {
                for event in events { print(AllnighterCLI.jsonLine(event)) }
            }
            print(AllnighterCLI.jsonLine(result))
        } else if json {
            print(AllnighterCLI.jsonString(result))
        } else {
            print(result.answer?.markdown ?? "(run \(result.teamRun.status.rawValue))")
            FileHandle.standardError.write(Data("\n[run \(runId)]\n".utf8))
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
        let idempotencyKey = opts.value("idempotency-key") ?? UUID().uuidString.lowercased()
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
            idempotencyKey: idempotencyKey,
            repoRoot: project.normalizedRootPath
        )
        let rendezvous = ResidentExecutionRendezvous()
        do {
            let submitted = try rendezvous.submit(
                operation: .teamRun(request),
                idempotencyKey: idempotencyKey
            )
            guard let receipt = try await rendezvous.waitForReceipt(requestId: submitted.requestId) else {
                AllnighterCLI.emitFailure(
                    code: "RESIDENT_ACCEPT_TIMEOUT",
                    message: "resident coordinator did not answer the Team request before timeout; retry only with --idempotency-key \(idempotencyKey)"
                )
                exit(1)
            }
            if let rejection = receipt.rejection {
                AllnighterCLI.emitFailure(code: rejection.code, message: rejection.message)
                exit(1)
            }
            guard case .teamStart(let response) = receipt.result else {
                AllnighterCLI.emitFailure(
                    code: "RESIDENT_REQUEST_REJECTED",
                    message: "resident coordinator accepted an invalid Team response"
                )
                exit(1)
            }
            if opts.flag("json") {
                print(AllnighterCLI.jsonString(response))
            } else {
                print(response.runId)
            }
        } catch ResidentExecutionRendezvous.Error.unavailable {
            AllnighterCLI.emitFailure(
                code: "COORDINATOR_UNAVAILABLE",
                message: "resident coordinator is unavailable; enable it with `alln serve install`"
            )
            exit(1)
        } catch {
            AllnighterCLI.emitFailure(code: "RESIDENT_REQUEST_REJECTED", message: "resident request failed: \(error)")
            exit(1)
        }
    }

    /// Project `RunDryRunJSON` v2 from one `ResolvedRunInvocation`.
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
