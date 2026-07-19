import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln` — Team-as-Tool (RB6). The universal shell surface any terminal
/// agent can call. Judgment only: links the team engine, never
/// worker-runner code. Local Fusion at zero marginal cost.
@main
struct AllnighterCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--version" {
            runVersion([])
            return
        }
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }

        // Global `--help` funnel — every subcommand prints usage and exits 0.
        if CLIUsage.helpRequested(args), let text = CLIUsage.helpText(rootCommand: command, args: args) {
            print(text)
            return
        }

        let runtime = ToolRuntime()
        switch command {
        case "teams" where args.first == "show": runTeamsShow(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "definition": runTeamsDefinition(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "duplicate": runTeamsDuplicate(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "edit": runTeamsEdit(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "set-default": runTeamsSetDefault(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "delete": runTeamsDelete(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "restore": runTeamsRestore(Array(args.dropFirst()), runtime)
        case "teams": runTeamCatalog(args, runtime)
        case "skills" where args.first == "show": runSkillShow(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "duplicate": runSkillsDuplicate(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "new": runSkillsNew(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "edit": runSkillsEdit(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "delete": runSkillsDelete(Array(args.dropFirst()), runtime)
        case "skills": runSkillCatalog(args, runtime)
        case "thread" where args.first == "send": await ThreadSendCLI.runSend(Array(args.dropFirst()), runtime: runtime)
        case "thread" where args.first == "get": ThreadCLI.runGet(Array(args.dropFirst()))
        case "thread" where args.first == "status": ThreadCLI.runStatus(Array(args.dropFirst()))
        case "thread" where args.first == "attachment": ThreadCLI.runAttachmentGet(Array(args.dropFirst()))
        case "thread" where args.first == "rename": await ThreadRenameCLI.runRename(Array(args.dropFirst()), runtime: runtime)
        case "run": await RunCLI.run(args, runtime: runtime)
        case "team" where args.first == "show": runTeamShow(Array(args.dropFirst()), runtime)
        case "team" where args.first == "hello": print(teamHelloJSONString(Array(args.dropFirst()), runtime))
        case "team" where args.first == "preflight": runTeamPreflight(Array(args.dropFirst()), runtime)
        case "team" where args.first == "start": await runTeamStart(Array(args.dropFirst()), runtime)
        case "team" where args.first == "__runner": await runTeamRunner(Array(args.dropFirst()), runtime)
        case "team" where args.first == "status": await runTeamStatus(Array(args.dropFirst()), runtime)
        case "team" where args.first == "result": await runTeamResult(Array(args.dropFirst()), runtime)
        case "team" where args.first == "cancel": await runTeamCancel(Array(args.dropFirst()), runtime)
        case "team" where args.first == "reconcile": await runTeamReconcile(Array(args.dropFirst()), runtime)
        case "team": await runTeam(args, runtime)
        case "models": await ModelsCLI.run(args, runtime: runtime)
        case "defaults": await DefaultsCLI.run(args, runtime: runtime)
        case "boost-window": await BoostWindowCLI.run(args, runtime: runtime)
        case "help": await HelpCLI.run(args, runtime: runtime)
        case "history": await runHistory(args, runtime)
        case "docs": runDocs(args)
        case "show": runShow(args, runtime)
        case "floor" where args.first == "show": runFloorShow(Array(args.dropFirst()), runtime)
        case "spec": runSpec(args, runtime)
        case "export": runExport(args, runtime)
        case "doctor" where args.first == "explain": runDoctorExplain(Array(args.dropFirst()))
        case "doctor": await runDoctor(args, runtime)
        case "detect": await runDetect(runtime)
        case "dev": runDev(args)
        case "serve": await runServe(args)
        case "pair": await PairCLI.run(args, runtime: runtime)
        case "panel": await PanelCLI.run(args, runtime: runtime)
        case "pending": await PendingCLI.run(args.first, Array(args.dropFirst()), runtime: runtime)
        case "stalled": StalledCLI.run(args.first, Array(args.dropFirst()))
        case "project": await ProjectCLI.run(args.first, Array(args.dropFirst()), runtime: runtime)
        case "bootstrap": runBootstrap(args)
        case "install-cli": runInstallCLI(args)
        case "version": runVersion(args)
        case "ps": runOwnershipPs(args)
        case "kill": runOwnershipKill(args)
        case "gc": runOwnershipGC(args)
        case "--help", "-h": printHelp()   // "help" is handled above via HelpCLI
        default:
            FileHandle.standardError.write(Data("unknown command: \(command)\n".utf8)); printHelp(); exit(2)
        }
    }

    // MARK: - Subcommands

    static func runTeam(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let question = opts.positional.first ?? opts.value("question") else {
            FileHandle.standardError.write(Data("usage: alln team \"<question>\" [--lane code|design|copy|signal] [--team id] [--effort low|med|high] [--type t] [--json | --stream]\n".utf8)); exit(2)
        }
        // --json and --stream are mutually exclusive (checked before spending quota).
        if opts.flag("json") && opts.flag("stream") {
            emitFailure(code: "CLI_USAGE_ERROR", message: "--json and --stream are mutually exclusive")
            exit(2)
        }
        let teamId = opts.value("team")
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use code|design|copy|signal)")
        }
        let effort = opts.value("effort").flatMap(EffortLevel.init(rawValue:))
        if let raw = opts.value("effort"), effort == nil {
            fail(code: "CLI_USAGE_ERROR", message: "unknown effort: \(raw) (use low|med|high)")
        }
        let request = TeamRequest(
            question: question, lane: lane, teamPresetId: teamId, effort: effort,
            type: opts.value("type"), context: opts.value("context")
        )

        if opts.flag("stream") {
            // Live NDJSON: emit events as the run progresses, not after it settles.
            let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
            let runTask = Task { await runtime.service().run(request, origin: .cli, originAgent: opts.value("agent"), events: continuation) }
            let mapper = NDJSONStreamProjector.LiveMapper()
            for await event in stream {
                if let line = mapper.line(for: event) { print(line) }
            }
            _ = await runTask.value   // run is persisted by the time the stream ends
            return
        }

        let result = await runtime.service().run(request, origin: .cli, originAgent: opts.value("agent"))

        if opts.flag("json") {
            // A refused request (conflict / unknown team / blocked / busy) never
            // persists a run — emit the machine failure envelope with its code.
            guard !result.runId.isEmpty else {
                emitFailure(code: result.errorCode ?? "DEFAULT_TEAM_INVALID", message: result.note.isEmpty ? "team run did not start" : result.note)
                exit(1)
            }
            guard let run = loadRun(result.runId) else {
                emitRunNotFound(result.runId, "team run did not persist")
                exit(1)
            }
            let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?
                .appendingPathComponent("run.json").path ?? ""
            let context = TeamRunJSONMapper.Context(
                promptSource: .init(kind: opts.value("file") != nil ? .file : .positional, path: opts.value("file")),
                runJournalPath: journalPath, reproduceCommand: reproduceCommand(run)
            )
            let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: context)
            print(jsonString(trj))
            return
        }

        if result.status == .failed && result.runId.isEmpty {
            FileHandle.standardError.write(Data((result.note + "\n").utf8)); exit(1)
        } else {
            print(result.plan ?? "(no plan — status \(result.status.rawValue))")
            for w in result.warnings { FileHandle.standardError.write(Data("⚠︎ \(w)\n".utf8)) }
            FileHandle.standardError.write(Data("\n[team \(result.preset): \(result.invocations) invocations; run \(result.runId)]\n".utf8))
        }
    }

    /// The `alln team …` command that replays this run's intent (lane/team/effort).
    /// The worker snapshot in the run is the historical truth; replay may resolve a
    /// different concrete model set if the bench changed.
    static func reproduceCommand(_ run: TeamRun) -> String {
        var parts = ["alln team"]
        if let lane = run.lane { parts.append("--lane \(lane.rawValue)") }
        if let team = run.presetId { parts.append("--team \(team)") }
        if let effort = run.effort { parts.append("--effort \(effort.rawValue)") }
        return parts.joined(separator: " ")
    }

    /// Loads a persisted run for projection to `TeamRunJSON`, applying orphan
    /// recovery (a crashed non-terminal run reads back as `interrupted`).
    static func loadRun(_ runId: String) -> TeamRun? {
        RunStore().load(runId: runId)
    }

    /// Emits the shared machine failure envelope (one JSON object on stdout). The
    /// recovery fields (`ruleId`/`agentAction`/`requiresManual`/`retryable`) are
    /// taken from the error catalog so the emitted envelope and `error_explain`
    /// always agree (M-C).
    static func emitFailure(code: String, message: String, supportDir: String? = nil) {
        struct Failure: Encodable { let schemaVersion = 1; let success = false; let error: ErrorEnvelope }
        let spec = ContractRegistry.milestone1.errorSpec(for: code)
        let env = ErrorEnvelope(
            code: code,
            ruleId: spec?.ruleId,
            message: message,
            agentAction: spec?.agentAction,
            requiresManual: spec?.requiresManual ?? false,
            retryable: spec?.retryable ?? false,
            supportDir: supportDir
        )
        print(jsonString(Failure(error: env)))
    }

    /// Emits the failure envelope and exits with the catalog-derived process exit
    /// code (usage → 2, operational → 1). The single funnel for terminal CLI
    /// failures so the error code and its exit class can never drift apart (M-C).
    static func fail(code: String, message: String, supportDir: String? = nil) -> Never {
        emitFailure(code: code, message: message, supportDir: supportDir)
        exit(ContractRegistry.milestone1.processExitCode(forErrorCode: code))
    }

    /// Effective `ALLNIGHTER_SUPPORT_DIR` (RLR-L1) — surfaced in not-found / kill
    /// errors so a caller on the wrong or isolated config home can see the exact
    /// support root that was searched (RCA class 5).
    static func effectiveSupportDir() -> String { AllnighterPaths.support.path }

    /// S01c (RLR-L8): distinguishes "no run.json for this id at all"
    /// (`RUN_NOT_FOUND` territory) from "a run.json exists but failed to
    /// decode" (`JOURNAL_CORRUPT`) — checked before every not-found fallback
    /// so an unmappable/legacy journal is never silently reported as if the
    /// run never existed, and never has a status invented for it. `store`
    /// defaults to the production `RunStore()`; status/result/cancel sites
    /// pass the same `RunStore` the async team service already resolved so
    /// isolated test stores are respected too.
    static func journalCorruptDetail(_ runId: String, in store: RunStore = RunStore()) -> String? {
        guard case .failure(.corrupt(_, let detail)) = store.loadRawResult(runId: runId) else { return nil }
        return detail
    }

    /// A `RUN_NOT_FOUND` failure that names the effective support root in both the
    /// human message and the machine `supportDir` field (RLR-L1), then exits.
    /// Upgrades to `JOURNAL_CORRUPT` when `runId` names an existing-but-corrupt
    /// journal (S01c) — pass `nil` when there is no single candidate id (e.g. a
    /// `latest` reference that matched nothing).
    static func failRunNotFound(_ runId: String?, _ message: String, in store: RunStore = RunStore()) -> Never {
        let dir = effectiveSupportDir()
        if let runId, let detail = journalCorruptDetail(runId, in: store) {
            fail(
                code: "JOURNAL_CORRUPT",
                message: "run journal for \(runId) exists but could not be decoded: \(detail) (support dir: \(dir))",
                supportDir: dir
            )
        }
        fail(code: "RUN_NOT_FOUND", message: "\(message) (support dir: \(dir))", supportDir: dir)
    }

    /// Non-exiting variant for JSON emit paths that own their own `exit`. Same
    /// `JOURNAL_CORRUPT` upgrade as `failRunNotFound` (S01c).
    static func emitRunNotFound(_ runId: String?, _ message: String, in store: RunStore = RunStore()) {
        let dir = effectiveSupportDir()
        if let runId, let detail = journalCorruptDetail(runId, in: store) {
            emitFailure(
                code: "JOURNAL_CORRUPT",
                message: "run journal for \(runId) exists but could not be decoded: \(detail) (support dir: \(dir))",
                supportDir: dir
            )
            return
        }
        emitFailure(code: "RUN_NOT_FOUND", message: "\(message) (support dir: \(dir))", supportDir: dir)
    }

    static func emitCatalogError(_ error: CatalogError, skillContext: Bool = false) -> Never {
        let (code, message) = catalogErrorEnvelope(error, skillContext: skillContext)
        fail(code: code, message: message)
    }

    static func catalogErrorEnvelope(_ error: CatalogError, skillContext: Bool = false) -> (code: String, message: String) {
        switch error {
        case .teamNotFound: return ("TEAM_NOT_FOUND", "team not found")
        case .skillNotFound: return ("SKILL_NOT_FOUND", "skill not found")
        case .modelNotFound: return ("MODEL_NOT_FOUND", "model not found")
        case .builtInImmutable:
            return (skillContext ? "SKILL_BUILTIN_IMMUTABLE" : "TEAM_BUILTIN_IMMUTABLE", "built-in catalog entry cannot be changed")
        case .idCollision:
            return (skillContext ? "SKILL_ID_COLLISION" : "TEAM_ID_COLLISION", "catalog id already exists")
        case .idInvalid: return ("CATALOG_ID_INVALID", "catalog id is invalid")
        case .teamInvalid(let detail): return ("TEAM_INVALID", detail)
        case .skillInvalid(let detail): return ("SKILL_INVALID", detail)
        case .skillLaneMismatch(let skillId, let teamId):
            return ("SKILL_LANE_MISMATCH", "skill \(skillId) is not in the same lane as team \(teamId)")
        case .skillInUse(let ids):
            return ("SKILL_IN_USE", "skill is referenced by team(s): \(ids.joined(separator: ", "))")
        case .teamDefaultInvalid(let detail): return ("TEAM_DEFAULT_INVALID", detail)
        case .restoreUnsupported: return ("TEAM_RESTORE_UNSUPPORTED", "this team has no shipped version to restore")
        }
    }

    static func modelCatalogErrorEnvelope(_ error: ModelCatalogError) -> (code: String, message: String) {
        switch error {
        case .notFound(let id): return ("MODEL_NOT_FOUND", "unknown model: \(id)")
        case .builtInImmutable: return ("MODEL_BUILTIN_IMMUTABLE", "built-in model cannot be changed")
        case .idCollision: return ("MODEL_ID_COLLISION", "model id already exists")
        case .idInvalid: return ("MODEL_INVALID", "model id is invalid")
        case .driverMissing(let driver): return ("MODEL_DRIVER_MISSING", "unknown driver: \(driver)")
        case .invalid(let detail): return ("MODEL_INVALID", detail)
        }
    }

    static func runHistory(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let query = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln history \"<query>\"\n".utf8)); exit(2)
        }
        let hits = await runtime.service().recall(query: query)
        if opts.flag("json") {
            print(jsonString(HistoryJSON(contractVersion: ContractRegistry.contractVersion, query: query, results: hits)))
        } else if hits.isEmpty {
            print("(no prior team runs match)")
        } else {
            for h in hits { print("\(h.createdAt) · \(h.runId)\n  \(h.prompt)\n  \(h.planExcerpt.replacingOccurrences(of: "\n", with: " ").prefix(160))\n") }
        }
    }

    static let binaryVersion = "0.1.0"

    /// `alln doctor [--json] [--full]` — the product recovery surface. Default is
    /// quota-free (resolve + version + local checks; auth/smoke/readiness reported
    /// `notChecked`). `--full` runs smoke probes (spends quota) to confirm
    /// auth/readiness. Emits `DoctorResult` (docs/phases/CLI_Implementation_Contract.md
    /// §Doctor Contract).
    static func runDoctor(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        let full = opts.flag("full")
        let pilot = opts.flag("pilot")
        let sourceId = opts.value("agent")
        if let sourceId, runtime.registry.manifest(id: sourceId) == nil {
            fail(code: "SOURCE_NOT_FOUND", message: "no source manifest '\(sourceId)'")
        }
        let result = await doctorResult(
            runtime,
            full: full,
            sourceId: sourceId,
            pilot: pilot,
            projectToken: opts.value("project")
        )
        if opts.flag("json") {
            print(jsonString(result))   // exactly one JSON object, no prose
        } else {
            printDoctorHuman(result, full: full)
        }
    }

    /// `alln serve [--health --json]` — resident coordinator skeleton. `--health`
    /// is read-only and never starts the coordinator.
    static func runServe(_ args: [String]) async {
        let opts = Options(args)
        if opts.flag("health") {
            let probe = ResidentCoordinatorProbe()
            let health = probe.health(binaryVersion: binaryVersion)
            if opts.flag("json") {
                print(jsonString(health))
            } else {
                print("coordinator \(health.state.rawValue)")
                if let pid = health.pid { print("pid \(pid)") }
                if let port = health.loopback.port { print("loopback \(health.loopback.host):\(port)") }
                print("obligations \(health.activeObligationCount)")
            }
            return
        }
        if !opts.positional.isEmpty || !opts.values.isEmpty {
            FileHandle.standardError.write(Data("usage: alln serve [--health --json]\n".utf8)); exit(2)
        }
        FileHandle.standardError.write(Data("alln serve — resident coordinator (Ctrl+C to stop)\n".utf8))
        do {
            let runtime = ToolRuntime()
            let wake = ResidentCoordinator.WakeDependencies(
                models: runtime.models,
                registry: runtime.registry,
                invocations: runtime.invocations
            )
            var remoteDependencies: ResidentCoordinator.RemoteDependencies?
            if let environment = RemoteSupabaseEnvironment.load(), environment.hasMacAgentCredentials {
                do {
                    let runStore = RunStore()
                    let threadStore = ThreadStore()
                    let journal = RemoteRunEventJournal(rootDirectory: runStore.rootDirectory)
                    let asyncTeam = AsyncTeamService(
                        models: runtime.models,
                        registry: runtime.registry,
                        teams: runtime.teams,
                        config: runtime.config,
                        runStore: runStore,
                        governor: runtime.governor,
                        remoteEventJournal: journal,
                        invocations: runtime.invocations
                    )
                    let baseExecutor = AsyncTeamRemoteCommandExecutor(
                        service: asyncTeam,
                        readyModels: { runtime.models }
                    )
                    let executor = RemoteIOSThreadMirrorExecutor(
                        underlying: baseExecutor,
                        threadStore: threadStore,
                        runStore: runStore
                    )
                    let inputs = RemoteMacAgentServeAssembly.Inputs(
                        environment: environment,
                        executor: executor,
                        readyModels: { runtime.models },
                        runStore: runStore,
                        threadStore: threadStore,
                        journal: journal
                    )
                    remoteDependencies = try RemoteMacAgentServeAssembly.remoteDependencies(inputs: inputs)
                    FileHandle.standardError.write(Data("remote agent: cloud relay enabled\n".utf8))
                } catch {
                    FileHandle.standardError.write(
                        Data("remote agent disabled: \(error)\n".utf8)
                    )
                }
            }
            try await ResidentCoordinator(
                binaryVersion: binaryVersion,
                wakeDependencies: wake,
                remoteDependencies: remoteDependencies
            ).runUntilSignal()
        } catch {
            FileHandle.standardError.write(Data("coordinator failed: \(error)\n".utf8)); exit(1)
        }
    }

    /// Builds a `DoctorResult` for `alln doctor`.
    static func doctorResult(
        _ runtime: ToolRuntime,
        full: Bool,
        sourceId: String? = nil,
        pilot: Bool = false,
        projectToken: String? = nil
    ) async -> DoctorResult {
        // PO-F10: opportunistic stale-lane GC (dead-holder + unheld flock).
        _ = ExecutionLaneFlock.garbageCollectStaleLanes()
        _ = ProcessOwnershipGarbageCollector().collect()

        let manifests = sourceId.map { id in runtime.registry.all.filter { $0.id == id } } ?? runtime.registry.all
        let modelLabels = ModelCatalog.probeModelLabels(registry: runtime.registry)
        let labels = sourceId.map { id in modelLabels.filter { $0.key == id } } ?? modelLabels
        let records = await doctorProbeRecords(manifests: manifests, labels: labels, full: full)
        let pilotContext = pilot ? doctorPilotContext(
            runtime: runtime, projectToken: projectToken, records: records, full: full
        ) : nil
        let inputs = DoctorReport.Inputs(
            binaryVersion: binaryVersion,
            contractVersion: ContractRegistry.contractVersion,
            docsVersionMatchesBinary: true,
            configDirWritable: ensureWritable(AllnighterPaths.config),
            runsDirWritable: ensureWritable(AllnighterPaths.runs),
            pendingDirWritable: ensureWritable(AllnighterPaths.pending),
            coordinator: ResidentCoordinatorProbe().doctorCoordinator(),
            full: full,
            cursorCLIConfigURL: CursorShellAllowlist.defaultConfigURL,
            cursorProjectOverrideURL: CursorShellAllowlist.projectOverrideURL(
                near: URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath,
                    isDirectory: true
                )
            ),
            runningBinaryPath: InstallCLI.resolvedRunningBinary(
                argv0: CommandLine.arguments.first,
                pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
            ),
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
            pilot: pilotContext
        )
        var result = DoctorReport.build(
            models: runtime.models,
            manifests: manifests,
            records: records,
            inputs: inputs
        )
        if let sourceId {
            let prefix = "source.\(sourceId)."
            let global = Set(["binaryVersion", "docsVersion", "configDir", "runsDir", "sources", "pilot"])
            result.checks = result.checks.filter { global.contains($0.name) || $0.name.hasPrefix(prefix) }
            result.models = result.models.filter { $0.sourceId == sourceId }
        }
        return result
    }

    /// Quota-free default uses cached detection records; `--full` runs live smoke probes.
    static func doctorProbeRecords(
        manifests: [DriverManifest],
        labels: [String: String],
        full: Bool,
        setupStore: SetupStore = SetupStore(),
        commandRunner: CommandRunner? = nil
    ) async -> [ToolProbeRecord] {
        // Doctor is a recovery surface: its children must honor the detector's
        // per-command deadlines even when a vendor CLI ignores SIGTERM.
        let runner = commandRunner ?? ProcessGroupCommandRunner(
            environmentPolicy: AllnighterSpawnEnvironmentPolicy(),
            spawnKind: .doctorProbe
        )
        if full {
            return await CLIDetector(
                commandRunner: runner,
                detectTimeout: .seconds(8),
                smokeTimeout: .seconds(60),
                interactive: true
            ).probeAll(manifests, models: labels, now: Date(), smoke: true)
        }
        let headlessIds = Set(manifests.filter { $0.kind == .headlessCLI }.map(\.id))
        let cached = setupStore.load().records.filter { headlessIds.contains($0.driverId) }
        if cached.count == headlessIds.count, !cached.isEmpty {
            return cached.sorted { $0.driverId < $1.driverId }
        }
        return await CLIDetector(
            commandRunner: runner,
            resolver: ShellResolver(commandRunner: runner, timeout: .seconds(2), interactive: false),
            detectTimeout: .seconds(2),
            smokeTimeout: .seconds(2),
            interactive: false
        ).probeAll(manifests, models: labels, now: Date(), smoke: false)
    }

    private static func doctorPilotContext(
        runtime: ToolRuntime,
        projectToken: String?,
        records: [ToolProbeRecord],
        full: Bool
    ) -> DoctorReport.PilotContext {
        let token = projectToken ?? "."
        let project = ProjectStore().resolveFresh(token)
        let devWorkerId = project.flatMap { PilotDevSeatStore().load(projectId: $0.id)?.devWorkerId }
        let model = devWorkerId.flatMap { id in runtime.models.first { $0.id == id } }
        let record = model.flatMap { m in records.first { $0.driverId == m.driverId } }
        let driverInstalled: Bool = {
            guard let record else { return false }
            if case .notInstalled = record.status { return false }
            return true
        }()
        return .init(
            projectLabel: project.map { "\($0.displayName) (\($0.id))" },
            devWorkerId: devWorkerId,
            devWorkerLabel: model.map { "\($0.id) (\($0.displayName))" },
            driverInstalled: driverInstalled,
            driverReady: full ? (record?.status.isReady ?? false) : nil
        )
    }

    private static func ensureWritable(_ url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    private static func printDoctorHuman(_ r: DoctorResult, full: Bool) {
        print("alln doctor — \(r.status.rawValue)\(full ? " (full)" : "")")
        if let counsel = r.counsel { print(counsel) }
        for c in r.checks {
            let mark: String
            switch c.status {
            case .ok: mark = "✓"
            case .degraded: mark = "!"
            case .critical: mark = "✗"
            case .notChecked: mark = "·"
            }
            print("  \(mark) \(c.name)\t\(c.detail)")
            if let fix = c.fixCommand { print("    → \(fix)") }
        }
        if !full {
            print("\nAuth/readiness not probed (quota-free). Run `alln doctor --full` to confirm — spends quota.")
        }
        for action in r.nextActions { print("→ \(action.command)") }
    }

    /// First-run CLI detection, headless — proves the detector on a real machine
    /// before any Setup UI (docs/phases/setup/01 §11, Phase 1). Runs real smoke
    /// probes. Note: the CLI uses `DefaultConfig` (no `setup` blocks yet), so bins
    /// fall back to `invoke.command` and loginFlow guidance comes from the app's
    /// bundle registry, not here.
    static func runDetect(_ runtime: ToolRuntime) async {
        let models = ModelCatalog.probeModelLabels(registry: runtime.registry)
        let records = await CLIDetector(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()), interactive: true)
            .probeAll(runtime.registry.all, models: models, now: Date())

        // Persist detection + assemble/persist the Bench/default team (the truth
        // layer for first-run; docs/phases/setup/01 §8–§9). Runs cache the resolved
        // invocation so health == runs.
        let store = SetupStore()
        let assembled = TeamAssembler.assemble(
            models: runtime.models,
            readyDriverIds: TeamAssembler.readyDriverIds(from: records),
            now: Date()
        )
        try? store.save(.init(records: records, setupCompletedAt: store.load().setupCompletedAt, assembledTeam: assembled))

        for r in records.sorted(by: { $0.driverId < $1.driverId }) {
            let path = r.invocation?.resolvedPath ?? "—"
            switch r.status {
            case .ready(let v):
                print("\(r.driverId)\tREADY\t\(v)\t\(path)")
            case .installedNotProbed(let v):
                print("\(r.driverId)\tINSTALLED (not probed)\t\(v)\t\(path)")
            case .installedNotSignedIn(let f):
                print("\(r.driverId)\tNEEDS SIGN-IN\t\(r.version ?? "")\n  → \(f.instructions)")
            case .probeFailed(let reason):
                print("\(r.driverId)\tPROBE FAILED\t\(r.version ?? "")\n  → \(reason)")
            case .shimmedNeedsConfirm(let res):
                print("\(r.driverId)\tNEEDS PATH\t\(res.rawCommandV)")
            case .notInstalled:
                print("\(r.driverId)\tNOT INSTALLED\t(no binary on PATH or known paths)")
            }
        }
        print("\nAssembled team: \(assembled.benchModelIds.count) ready model(s); plan writer: \(assembled.planWriterModelId ?? "—") · saved")
    }

    /// `alln dev export-contracts [--check]` — regenerate or verify the
    /// checked-in generated artifacts from the contract registry
    /// (docs/phases/CLI_Implementation_Contract.md §Generated Artifacts). The
    /// generated dir is resolved relative to the current directory, so run this
    /// from the repo root.
    static func runDev(_ args: [String]) {
        var rest = args
        let sub = rest.first
        if !rest.isEmpty { rest.removeFirst() }
        switch sub {
        case "export-contracts": runExportContracts(Options(rest))
        default:
            FileHandle.standardError.write(Data("usage: alln dev export-contracts [--check]\n".utf8)); exit(2)
        }
    }

    static func runExportContracts(_ opts: Options) {
        let cwd = FileManager.default.currentDirectoryPath
        if opts.flag("check") {
            do {
                switch try ContractExport.check(from: cwd) {
                case .upToDate(let count):
                    print("contracts up to date (\(count) artifacts)")
                case .drifted(let files):
                    FileHandle.standardError.write(Data("CONTRACT_DRIFT: \(files.joined(separator: ", "))\nRun `alln dev export-contracts`, then rebuild.\n".utf8))
                    exit(ContractRegistry.milestone1.processExitCode(forErrorCode: "CONTRACT_DRIFT"))
                }
            } catch let notFound as ContractExport.NotFoundError {
                failContractsNotFound(notFound)
            } catch {
                FileHandle.standardError.write(Data("export failed: \(error)\n".utf8)); exit(1)
            }
        } else {
            do {
                let result = try ContractExport.write(from: cwd)
                print("wrote \(result.count) artifacts to \(result.path)")
            } catch let notFound as ContractExport.NotFoundError {
                failContractsNotFound(notFound)
            } catch {
                FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1)
            }
        }
    }

    /// Emits `CONTRACT_ARTIFACTS_NOT_FOUND` — distinct from `CONTRACT_DRIFT` — for
    /// an unresolved repo root or a missing generated dir/artifact (PO-F6).
    static func failContractsNotFound(_ error: ContractExport.NotFoundError) -> Never {
        let message: String
        switch error {
        case .repoRootNotFound(let cwd):
            message = "could not find the repo root ascending from \(cwd) (looked for docs/generated/alln or .git); re-run from inside the repo."
        case .generatedDirMissing(let path):
            message = "\(path) does not exist yet; this is not content drift — run `alln dev export-contracts` to create it."
        case .artifactsMissing(let path, let filenames):
            message = "missing artifact file(s) under \(path): \(filenames.joined(separator: ", ")); this is not content drift — run `alln dev export-contracts` to (re)create them."
        }
        fail(code: "CONTRACT_ARTIFACTS_NOT_FOUND", message: message)
    }

    // MARK: - team show / docs / show / export / doctor explain

    /// `alln team show [--lane code|design|copy|signal] [--json]` — the default team for
    /// each lane (or one lane). Does NOT run.
    static func runTeamShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        if opts.flag("json") { print(teamShowJSONString(runtime, lane: opts.value("lane").flatMap(WorkLane.init(rawValue:)))); return }
        let lanes = opts.value("lane").flatMap(WorkLane.init(rawValue:)).map { [$0] } ?? WorkLane.allCases
        for lane in lanes {
            guard let team = runtime.teams.defaultTeam(for: lane) else { continue }
            print("\(lane.rawValue) → \(team.displayName) (\(team.id)) · default effort \(team.defaultEffort.displayLabel) · \(team.outputKind.rawValue)")
            print("  \(team.workerSpecs.count) workers · lead \(team.lead.skillId)")
        }
    }

    /// The default-team-per-lane snapshot JSON for `alln team show --json`.
    static func teamShowJSONString(_ runtime: ToolRuntime, lane: WorkLane? = nil) -> String {
        let lanes = lane.map { [$0] } ?? WorkLane.allCases
        struct TeamView: Encodable {
            let id, displayName, lane, outputKind, defaultEffort: String
            let mutating, isDefaultForLane: Bool
            let workerCount: Int
        }
        struct Snapshot: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let defaults: [TeamView]
        }
        let defaults = lanes.compactMap { lane -> TeamView? in
            guard let t = runtime.teams.defaultTeam(for: lane) else { return nil }
            return TeamView(id: t.id, displayName: t.displayName, lane: t.lane.rawValue,
                            outputKind: t.outputKind.rawValue, defaultEffort: t.defaultEffort.rawValue,
                            mutating: t.mutating,
                            isDefaultForLane: true,
                            workerCount: t.workerSpecs.count)
        }
        return jsonString(Snapshot(contractVersion: ContractRegistry.contractVersion, defaults: defaults))
    }

    /// `alln teams [--lane code|design|copy|signal] [--json]` — the lane-scoped team
    /// catalog summary (no full prompt templates).
    static func runTeamCatalog(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use code|design|copy|signal)")
        }
        let includeInactive = opts.flag("all")
        if opts.flag("json") {
            print(teamsCatalogJSONString(runtime, lane: lane, includeInactive: includeInactive))
        } else {
            let teams = lane.map { runtime.teams.teams(in: $0) } ?? runtime.teams
            let visible = teams.filter { includeInactive || TeamVisibility.isEnabled($0.id) }
            if visible.isEmpty {
                let payload = TeamCatalogJSON.project(teams, lane: lane,
                                                      contractVersion: ContractRegistry.contractVersion,
                                                      includeInactive: includeInactive)
                if let counsel = payload.counsel { print(counsel) }
                for action in payload.nextActions { print("→ \(action.command)") }
            } else {
                for t in visible {
                    let off = TeamVisibility.isEnabled(t.id) ? "" : "\t(inactive)"
                    print("\(t.id)\t\(t.displayName)\t\(t.lane.rawValue)/\(t.outputKind.rawValue)\tdefault \(t.defaultEffort.rawValue)\t\(t.workerSpecs.count) workers\(t.isDefaultForLane ? "\t(default)" : "")\(off)")
                }
            }
        }
    }

    /// The lane-scoped catalog summary JSON for `alln teams --json`. Inactive
    /// (switched-OFF) teams are dropped unless `includeInactive` is true.
    static func teamsCatalogJSONString(_ runtime: ToolRuntime, lane: WorkLane?, includeInactive: Bool = false) -> String {
        let teams = lane.map { runtime.teams.teams(in: $0) } ?? runtime.teams
        return jsonString(TeamCatalogJSON.project(teams, lane: lane,
                                                  contractVersion: ContractRegistry.contractVersion,
                                                  includeInactive: includeInactive))
    }

    /// `alln skills [--lane code|design|copy|signal] [--json]` — lane-scoped skill catalog (no templates).
    static func runSkillCatalog(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            fail(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use code|design|copy|signal)")
        }
        if opts.flag("json") {
            print(skillsCatalogJSONString(lane: lane))
        } else {
            let skills = lane.map { SkillCatalog.list(lane: $0) } ?? WorkLane.allCases.flatMap { SkillCatalog.list(lane: $0) }
            for s in skills {
                print("\(s.id)\t\(s.displayName)\t\(s.lane.rawValue)\t\(s.purpose.rawValue)\(s.builtIn ? "\t(built-in)" : "")")
            }
        }
    }

    /// `alln skills show <skill-id> [--json]` — one skill including template.
    static func runSkillShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills show <skill-id> [--json]")
        }
        guard let skill = SkillCatalog.get(id) else {
            fail(code: "SKILL_NOT_FOUND", message: "unknown skill: \(id)")
        }
        if opts.flag("json") {
            print(skillShowJSONString(skill))
        } else {
            print("\(skill.id)\t\(skill.displayName)\t\(skill.lane.rawValue)\t\(skill.purpose.rawValue)")
            print(skill.template)
        }
    }

    static func skillsCatalogJSONString(lane: WorkLane?) -> String {
        let skills = lane.map { SkillCatalog.list(lane: $0) }
            ?? WorkLane.allCases.flatMap { SkillCatalog.list(lane: $0) }
        return jsonString(SkillCatalogJSON.project(skills, lane: lane, contractVersion: ContractRegistry.contractVersion))
    }

    static func skillShowJSONString(_ skill: Skill) -> String {
        struct Detail: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let id, displayName, lane, purpose: String
            let builtIn: Bool
            let template: String
            let createdAt, updatedAt: String?
        }
        let iso = ISO8601DateFormatter()
        return jsonString(Detail(
            contractVersion: ContractRegistry.contractVersion,
            id: skill.id, displayName: skill.displayName, lane: skill.lane.rawValue,
            purpose: skill.purpose.rawValue, builtIn: skill.builtIn, template: skill.template,
            createdAt: skill.createdAt.map { iso.string(from: $0) },
            updatedAt: skill.updatedAt.map { iso.string(from: $0) }
        ))
    }

    // MARK: - Catalog mutation (teams)

    /// `alln teams definition <team-id> [--json]` — full TeamPreset for edit/save round-trip.
    static func runTeamsDefinition(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams definition <team-id> [--json]")
        }
        guard let team = TeamCatalog.get(id) else {
            fail(code: "TEAM_NOT_FOUND", message: "unknown team: \(id)")
        }
        if opts.flag("json") { print(teamDefinitionJSONString(team)) }
        else { print(teamDefinitionJSONString(team)) }
    }

    /// `alln teams show <team-id> [--json]` — one team including worker rows.
    static func runTeamsShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams show <team-id> [--json]")
        }
        guard let team = TeamCatalog.get(id) else {
            fail(code: "TEAM_NOT_FOUND", message: "unknown team: \(id)")
        }
        if opts.flag("json") { print(teamShowJSONString(team)) }
        else {
            print("\(team.id)\t\(team.displayName)\t\(team.lane.rawValue)/\(team.outputKind.rawValue)")
            for row in team.workerSpecs {
                print("  \(row.id)\t\(row.skillId)\t\(row.purpose.rawValue)")
            }
        }
    }

    /// Full `TeamPreset` JSON round-trippable through `teams_save` / `teams edit`.
    static func teamDefinitionJSONString(_ team: TeamPreset) -> String {
        jsonString(team)
    }

    static func teamShowJSONString(_ team: TeamPreset) -> String {
        struct WorkerRow: Encodable {
            let id, skillId, purpose: String
            let count: Int
            let required: Bool
        }
        struct Detail: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let id, displayName, lane, outputKind, defaultEffort: String
            let builtIn, isDefaultForLane: Bool
            let description: String
            let workerSpecs: [WorkerRow]
            // Edit-in-place metadata: where this effective team came from and whether a
            // Restore (revert-to-shipped) is available.
            let origin: String
            let seedId: String?
            let restoreAvailable: Bool
            let isDefaultForRun: Bool
        }
        let rows = team.workerSpecs.map {
            WorkerRow(id: $0.id, skillId: $0.skillId, purpose: $0.purpose.rawValue,
                      count: $0.count, required: $0.required)
        }
        return jsonString(Detail(
            contractVersion: ContractRegistry.contractVersion,
            id: team.id, displayName: team.displayName, lane: team.lane.rawValue,
            outputKind: team.outputKind.rawValue, defaultEffort: team.defaultEffort.rawValue,
            builtIn: team.builtIn, isDefaultForLane: team.isDefaultForLane,
            description: team.description, workerSpecs: rows,
            origin: teamOrigin(team.id), seedId: BuiltInTeams.team(team.id) != nil ? team.id : nil,
            restoreAvailable: TeamCatalog.hasOverride(team.id),
            isDefaultForRun: team.id == "default_chat"
        ))
    }

    /// Where the effective team came from: an unedited shipped team (`seed`), the user's
    /// edited version of a shipped team (`override`), or a brand-new team (`custom`).
    static func teamOrigin(_ id: TeamID) -> String {
        if BuiltInTeams.team(id) != nil { return TeamCatalog.hasOverride(id) ? "override" : "seed" }
        return "custom"
    }

    /// `alln teams restore <team-id> [--json]` — revert a team to its shipped version by
    /// removing the user's edits. Idempotent.
    static func runTeamsRestore(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams restore <team-id> [--json]")
        }
        do {
            let result = try TeamCatalog.restore(id)
            if opts.flag("json") {
                print(teamRestoreJSONString(id: id, restored: result.removedOverride))
            } else {
                print(result.removedOverride ? "restored \(id) to shipped version" : "\(id) already at shipped version")
            }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// Restore-acknowledgement JSON for `alln teams restore`.
    static func teamRestoreJSONString(id: TeamID, restored: Bool) -> String {
        struct RestoreAck: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let id: String
            let restored: Bool
            let origin: String
        }
        return jsonString(RestoreAck(
            contractVersion: ContractRegistry.contractVersion,
            id: id, restored: restored, origin: teamOrigin(id)))
    }

    /// `alln teams duplicate <team-id> [--name <displayName>] [--json]`
    static func runTeamsDuplicate(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams duplicate <team-id> [--name <name>] [--json]")
        }
        do {
            let team = try TeamCatalog.duplicateBuiltIn(id, name: opts.value("name"))
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("duplicated \(id) → \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams edit <team-id> [--file <path>] [--json]` — full replacement save.
    static func runTeamsEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams edit <team-id> [--file <path>] [--json]")
        }
        guard TeamCatalog.get(id) != nil else {
            fail(code: "TEAM_NOT_FOUND", message: "unknown team: \(id)")
        }
        do {
            let team = try loadTeamDefinition(from: opts.value("file"), expectedId: id)
            try TeamCatalog.saveCustom(team)
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("saved \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams set-default <team-id> [--json]`
    static func runTeamsSetDefault(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams set-default <team-id> [--json]")
        }
        do {
            let team = try TeamCatalog.setDefault(id)
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("default for \(team.lane.rawValue) → \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln teams delete <team-id> [--json]`
    static func runTeamsDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln teams delete <team-id> [--json]")
        }
        do {
            try TeamCatalog.deleteCustom(id)
            if opts.flag("json") { print(jsonString(DeleteAck(deleted: id))) }
            else { print("deleted \(id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    static func loadTeamDefinition(from path: String?, expectedId: TeamID) throws -> TeamPreset {
        guard let path else {
            throw CatalogError.teamInvalid("--file is required for teams edit (full replacement)")
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        if let envelope = try? CoreJSON.decode(CatalogEnvelope<TeamPreset>.self, from: data) {
            guard envelope.definition.id == expectedId else {
                throw CatalogError.teamInvalid("file team id \(envelope.definition.id) does not match \(expectedId)")
            }
            return envelope.definition
        }
        let team = try CoreJSON.decode(TeamPreset.self, from: data)
        guard team.id == expectedId else {
            throw CatalogError.teamInvalid("file team id \(team.id) does not match \(expectedId)")
        }
        return team
    }

    // MARK: - Catalog mutation (skills)

    /// `alln skills duplicate <skill-id> [--name <displayName>] [--json]`
    static func runSkillsDuplicate(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills duplicate <skill-id> [--name <name>] [--json]")
        }
        do {
            let skill = try SkillCatalog.duplicateBuiltIn(id, name: opts.value("name"))
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("duplicated \(id) → \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills new --lane <lane> --name <name> --purpose <purpose> [--template-file <path>] [--json]`
    static func runSkillsNew(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let laneRaw = opts.value("lane"), let lane = WorkLane(rawValue: laneRaw) else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills new --lane code|design|copy|signal --name <name> --purpose answer|review|planWriter [--template-file <path>] [--json]")
        }
        guard let name = opts.value("name"), !name.isEmpty else {
            fail(code: "CLI_USAGE_ERROR", message: "--name is required")
        }
        guard let purposeRaw = opts.value("purpose"), let purpose = SkillPurpose(rawValue: purposeRaw) else {
            fail(code: "CLI_USAGE_ERROR", message: "--purpose must be answer, review, or planWriter")
        }
        let template: String
        do { template = try loadTemplateText(opts.value("template-file")) }
        catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
        do {
            let skill = try SkillCatalog.createCustom(lane: lane, name: name, purpose: purpose, template: template)
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("created \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills edit <skill-id> [--name <displayName>] [--template-file <path>] [--json]`
    static func runSkillsEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills edit <skill-id> [--name <name>] [--template-file <path>] [--json]")
        }
        guard var skill = SkillCatalog.get(id) else {
            fail(code: "SKILL_NOT_FOUND", message: "unknown skill: \(id)")
        }
        if let name = opts.value("name") { skill.displayName = name }
        do {
            if let path = opts.value("template-file") { skill.template = try loadTemplateText(path) }
            try SkillCatalog.saveCustom(skill)
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("saved \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    /// `alln skills delete <skill-id> [--json]`
    static func runSkillsDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            fail(code: "CLI_USAGE_ERROR", message: "usage: alln skills delete <skill-id> [--json]")
        }
        do {
            try SkillCatalog.deleteCustom(id)
            if opts.flag("json") { print(jsonString(DeleteAck(deleted: id))) }
            else { print("deleted \(id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { fail(code: "INTERNAL_ERROR", message: "\(error)") }
    }

    static func loadTemplateText(_ path: String?) throws -> String {
        guard let path else { return "You are a helpful specialist for this lane." }
        return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    struct DeleteAck: Encodable {
        let schemaVersion = 1
        let deleted: String
    }

    /// The agent bootstrap snapshot JSON for `alln team hello`. Cheap, non-mutating,
    /// quota-free (cached readiness). With `--for "<intent>"`, returns the intent
    /// router payload (`Agent_Intent_Router.md`) instead of the static readiness report.
    static func teamHelloJSONString(_ args: [String], _ runtime: ToolRuntime) -> String {
        let opts = Options(args)
        let verdict = AgentReadiness.evaluate(teams: runtime.teams, readyModels: runtime.readyModels)
        if let intent = opts.value("for") {
            return AgentHello.intentRouteJSONString(
                intent: intent,
                verdict: verdict,
                readyModels: runtime.readyModels,
                teams: runtime.teams
            )
        }
        return AgentHello.jsonString(
            verdict: verdict,
            binaryVersion: binaryVersion
        )
    }

    /// `alln team preflight [--lane l] [--team id] [--effort e] [--type t]` — resolve
    /// against the ready bench without running. Always prints JSON.
    static func runTeamPreflight(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        var dict: [String: Any] = [:]
        for k in ["lane", "team", "effort", "type"] { if let v = opts.value(k) { dict[k] = v } }
        print(jsonString(preflight(runtime, args: dict)))
    }

    /// Run preflight from CLI args (lane/team/type/effort) against the ready bench.
    static func preflight(_ runtime: ToolRuntime, args: [String: Any]) -> TeamPreflight.Result {
        var result = TeamPreflight.preflight(
            teams: runtime.teams,
            lane: (args["lane"] as? String).flatMap(WorkLane.init(rawValue:)),
            teamId: args["team"] as? String,
            type: args["type"] as? String,
            effort: (args["effort"] as? String).flatMap(EffortLevel.init(rawValue:)),
            readyModels: runtime.readyModels)
        if result.canStart {
            switch runtime.governor.availability() {
            case .available:
                break
            case .busy:
                let reason = "busy: \(runtime.config.maxConcurrentTeamRuns) team runs already running"
                result.canStart = false
                result.blockedReason = reason
                result.warnings.append("Team governor is at capacity.")
                result.nextAction = AgentNextAction(kind: "retryLater", tool: "team_start")
            case .unavailable(let reason):
                result.canStart = false
                result.blockedReason = reason
                result.warnings.append("Team governor slot store is unavailable.")
                result.nextAction = AgentNextAction(kind: "runDoctor", tool: "doctor")
            }
        }
        return result
    }

    static func parseAsyncTeamStart(_ args: [String], _ opts: Options) -> AsyncTeamStartRequest? {
        guard let question = opts.positional.first ?? opts.value("question") else { return nil }
        return AsyncTeamStartRequest(
            question: question,
            lane: opts.value("lane").flatMap(WorkLane.init(rawValue:)),
            teamPresetId: opts.value("team"),
            effort: opts.value("effort").flatMap(EffortLevel.init(rawValue:)),
            type: opts.value("type"),
            context: opts.value("context"),
            threadId: opts.value("thread-id"),
            originAgent: opts.value("agent"),
            originConversationId: opts.value("conversation-id"),
            originMessageId: opts.value("message-id"),
            idempotencyKey: opts.value("idempotency-key")
        )
    }

    /// `alln team start ... --json` — async start; forks a self-owning runner
    /// (PO-S01), prints the accepted envelope, and exits. The runner process
    /// owns the journal + heartbeat for the life of the run.
    static func runTeamStart(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json") else {
            FileHandle.standardError.write(Data("usage: alln team start \"<prompt>\" --json [--lane code|design|copy|signal] [--team id] [--effort low|med|high] [--idempotency-key key]\n".utf8))
            exit(2)
        }
        guard var request = parseAsyncTeamStart(args, opts) else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "missing prompt")
            exit(2)
        }
        if let raw = opts.value("lane"), request.lane == nil {
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw)")
            exit(2)
        }
        if let raw = opts.value("effort"), request.effort == nil {
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown effort: \(raw)")
            exit(2)
        }
        // Default cwd is the project root workers should run in when the caller
        // did not pass an explicit repo root.
        if request.repoRoot == nil {
            request.repoRoot = FileManager.default.currentDirectoryPath
        }
        // Absolute path via _NSGetExecutablePath — never argv[0] (posix_spawn
        // does no PATH search; chdir makes relative argv[0] resolve wrongly).
        guard let executable = ProcessOwnership.currentExecutablePath() else {
            emitFailure(code: "INTERNAL_ERROR", message: "could not resolve alln executable path")
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
            print(jsonString(response))
        case .failure(let refusal):
            emitFailure(code: refusal.code, message: refusal.message)
            exit(1)
        }
    }

    /// Internal: detached runner body for `team start` (PO-S01). Becomes a
    /// session leader, claims ownership of the accepted run, and executes it.
    /// Not part of the public agent surface.
    static func runTeamRunner(_ args: [String], _ runtime: ToolRuntime) async {
        _ = ProcessOwnership.becomeSessionLeader()
        let opts = Options(args)
        guard let runId = opts.value("run-id") ?? opts.positional.first, !runId.isEmpty else {
            FileHandle.standardError.write(Data("usage: alln team __runner --run-id <id>\n".utf8))
            exit(2)
        }
        let outcome = await runtime.asyncTeamService().executeRunner(
            runId: runId,
            readyModels: runtime.readyModels
        )
        switch outcome {
        case .success:
            exit(0)
        case .failure(let refusal):
            FileHandle.standardError.write(Data("\(refusal.code): \(refusal.message)\n".utf8))
            exit(1)
        }
    }

    /// `alln team status <run-id> --json [--wait-for <state> --timeout <seconds>]`
    /// Plain status is a single snapshot. With `--wait-for`, blocks in-process
    /// until the target (or a non-matching terminal) or timeout (PO-F3).
    static func runTeamStatus(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json"), let runId = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln team status <run-id> --json [--wait-for <state> --timeout <seconds>]\n".utf8))
            exit(ExitCode.usageError)
        }

        let waitRaw = opts.value("wait-for")
        let timeoutRaw = opts.value("timeout")
        if waitRaw == nil && timeoutRaw == nil {
            guard let status = await runtime.asyncTeamService().status(runId: runId) else {
                failRunNotFound(runId, "no run matches \(runId)", in: await runtime.asyncTeamService().runStore)
            }
            print(jsonString(status))
            return
        }
        guard let waitRaw else {
            fail(code: "CLI_USAGE_ERROR", message: "--timeout requires --wait-for <state>")
        }
        guard let timeoutRaw else {
            fail(code: "CLI_USAGE_ERROR", message: "--wait-for requires --timeout <seconds>")
        }
        guard let target = TeamStatusWaitTarget.parse(waitRaw) else {
            fail(
                code: "CLI_USAGE_ERROR",
                message: "unknown --wait-for state: \(waitRaw) (use queued|running|done|failed|timedOut|cancelled|terminal)"
            )
        }
        guard let timeoutSeconds = Double(timeoutRaw), timeoutSeconds >= 0 else {
            fail(code: "CLI_USAGE_ERROR", message: "--timeout must be a non-negative number of seconds")
        }

        // Duration.seconds takes Integer; keep sub-second precision via ms.
        let timeoutMs = max(0, Int((timeoutSeconds * 1_000.0).rounded()))
        let timeout = Duration.milliseconds(timeoutMs)
        guard let outcome = await runtime.asyncTeamService().waitForStatus(
            runId: runId, target: target, timeout: timeout
        ) else {
            failRunNotFound(runId, "no run matches \(runId)", in: await runtime.asyncTeamService().runStore)
        }

        print(jsonString(outcome.response))
        if outcome.timedOut {
            // STATUS_WAIT_TIMEOUT → exit 3 (stable timeout class).
            exit(ContractRegistry.milestone1.processExitCode(forErrorCode: "STATUS_WAIT_TIMEOUT"))
        }
        if outcome.terminalMismatch {
            // Target not reached; run is terminal — class by lifecycle status.
            switch outcome.response.status {
            case .failed:
                exit(ExitCode.runFailed)
            case .timedOut:
                exit(ExitCode.timeout)
            case .done, .cancelled:
                exit(ExitCode.success)
            case .queued, .running:
                exit(ExitCode.runFailed)
            }
        }
        // Target matched — exit by status class when the target itself is a failure.
        switch outcome.response.status {
        case .failed:
            exit(ExitCode.runFailed)
        case .timedOut:
            exit(ExitCode.timeout)
        case .done, .cancelled, .queued, .running:
            exit(ExitCode.success)
        }
    }

    /// `alln team result <run-id> --json`
    static func runTeamResult(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json"), let runId = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln team result <run-id> --json\n".utf8))
            exit(2)
        }
        switch await runtime.asyncTeamService().result(runId: runId) {
        case .notFound:
            emitRunNotFound(runId, "no run matches \(runId)", in: await runtime.asyncTeamService().runStore)
            exit(1)
        case .notReady(let nr):
            print(jsonString(nr))
        case .ready(let run):
            let context = defaultRunContext(run)
            let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: context)
            print(jsonString(trj))
        }
    }

    /// `alln team cancel <run-id> --json`
    static func runTeamCancel(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json"), let runId = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln team cancel <run-id> --json\n".utf8))
            exit(2)
        }
        guard let response = await runtime.asyncTeamService().cancel(runId: runId) else {
            emitRunNotFound(runId, "no run matches \(runId)", in: await runtime.asyncTeamService().runStore)
            exit(1)
        }
        print(jsonString(response))
    }

    /// `alln team reconcile [run-id] [--all-projects] --json` — explicit
    /// ownership reconcile (PO-S01 v2). Identity-dead owners are PG-killed
    /// (recorded pgid only) and stamped `endReason: reconciledOrphan`. An exact
    /// run-id may target any project; the bare sweep is scoped to the caller's
    /// canonical project root (Concurrent Invocation Isolation F1) — machine-wide
    /// only via the explicit `--all-projects`.
    static func runTeamReconcile(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json") else {
            FileHandle.standardError.write(Data("usage: alln team reconcile [run-id] [--all-projects] --json\n".utf8))
            exit(2)
        }
        let runId = opts.positional.first
        let scopeRoot = opts.flag("all-projects") ? nil : FileManager.default.currentDirectoryPath
        let reaped = await runtime.asyncTeamService().reconcile(runId: runId, scopeRoot: scopeRoot)
        struct ReconcileEnvelope: Encodable {
            var schemaVersion = 1
            var reapedCount: Int
            var reaped: [ReconcileRow]
        }
        struct ReconcileRow: Encodable {
            var runId: String
            var status: String
            var endReason: String?
        }
        let envelope = ReconcileEnvelope(
            reapedCount: reaped.count,
            reaped: reaped.map {
                ReconcileRow(
                    runId: $0.id,
                    status: $0.status.rawValue,
                    endReason: $0.endReason?.rawValue
                )
            }
        )
        print(jsonString(envelope))
    }

    /// `alln ps [--all-projects] [--json]` — read-only ownership inventory
    /// (PO-S05). Reports what reconcile WOULD reap; kills nothing. Defaults to
    /// the caller's project scope (Concurrent Invocation Isolation F1);
    /// `--all-projects` is the explicit machine-wide fleet view.
    static func runOwnershipPs(_ args: [String]) {
        let opts = Options(args)
        let surface = ProcessOwnershipSurface()
        let allProjects = opts.flag("all-projects")
        let scopeRoot = allProjects ? nil : FileManager.default.currentDirectoryPath
        let envelope = surface.list(scopeRoot: scopeRoot)
        if opts.flag("json") {
            print(jsonString(envelope))
        } else {
            print(ProcessOwnershipSurface.humanTable(envelope))
            if !allProjects {
                print("(project scope: \(FileManager.default.currentDirectoryPath) — `alln ps --all-projects` for the fleet view)")
            }
        }
    }

    /// `alln gc [--json]` — safely prune old dead terminal run/relay records.
    static func runOwnershipGC(_ args: [String]) {
        let opts = Options(args)
        let dryRun = opts.flag("dry-run")
        let result = ProcessOwnershipGarbageCollector(dryRun: dryRun).collect()
        if opts.flag("json") {
            print(jsonString(result))
            return
        }
        let verb = dryRun ? "would prune" : "pruned"
        let suffix = dryRun ? "  (dry run — nothing deleted)" : ""
        print("\(verb) \(result.prunedCount) of \(result.consideredCount) ownership record(s)\(suffix)")
        print("kept alive: \(result.keptAlive.count)")
        print("kept non-terminal: \(result.keptNonTerminal.count)")
        print("kept within retention: \(result.keptWithinRetention.count)")
        print("kept thread-referenced: \(result.keptThreadReferenced.count)")
        print("kept unreadable: \(result.keptUnreadable.count)")
        print("kept after removal failure: \(result.keptRemovalFailed.count)")
    }

    /// `alln kill <id> | --all [--all-projects] [--json]` — identity-checked
    /// total group kill + terminal `endReason: killed` (PO-S05). Refuses on
    /// identity mismatch. `--all` is scoped to the caller's project root
    /// (Concurrent Invocation Isolation F1); `--all-projects` makes it the
    /// explicit machine-wide fleet kill. An exact id may target any project.
    static func runOwnershipKill(_ args: [String]) {
        let opts = Options(args)
        let surface = ProcessOwnershipSurface()
        let asJSON = opts.flag("json")

        if opts.flag("all") {
            let allProjects = opts.flag("all-projects")
            let scopeRoot = allProjects ? nil : FileManager.default.currentDirectoryPath
            let result = surface.killAll(scopeRoot: scopeRoot)
            if asJSON {
                print(jsonString(result))
            } else {
                print("killed \(result.killedCount) process tree(s)")
                for row in result.killed {
                    print("  \(row.id) (\(row.kind)) endReason=\(row.endReason ?? "-") killOutcome=\(row.killOutcome ?? "-") signalled=\(row.signalled)")
                }
                for skip in result.skipped {
                    print("  skip \(skip.id): \(skip.reason)")
                }
                if !allProjects {
                    print("(project scope: \(FileManager.default.currentDirectoryPath) — `--all-projects` for machine-wide)")
                }
            }
            return
        }

        guard let id = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln kill <id> | --all [--all-projects] [--json]\n".utf8))
            exit(2)
        }
        switch surface.kill(id: id) {
        case .success(let row):
            // RLR-S04b: `alln kill` exits 0 having honestly reported the settlement
            // verdict — a non-verified stop is `killOutcome: partial/refused/…` in the
            // envelope (the KILL_* error codes are its catalog projection), not a
            // command failure. The single JSON object carries the outcome to the caller.
            if asJSON {
                print(jsonString(OwnershipKillJSON(killed: [row])))
            } else {
                let outcome = row.killOutcome.map { " killOutcome=\($0)" } ?? ""
                print("kill \(row.id) (\(row.kind)) endReason=\(row.endReason ?? "-")\(outcome) signalled=\(row.signalled)")
            }
        case .failure(.notFound(let missing)):
            fail(code: "OWNERSHIP_NOT_FOUND", message: "no owned process tree matches \(missing)")
        case .failure(.alreadyTerminal(let tid, let end)):
            fail(
                code: "OWNERSHIP_ALREADY_TERMINAL",
                message: "\(tid) is already terminal\(end.map { " (endReason=\($0))" } ?? "")"
            )
        case .failure(.identityMismatch(let mid)):
            fail(
                code: "OWNERSHIP_IDENTITY_MISMATCH",
                message: "refusing to signal \(mid): recorded identity does not match the live process (pid reuse)"
            )
        }
    }

    /// `alln docs [topic] [--errors] [--schema] [--examples]` — the generated,
    /// agent-facing reference, projected from the contract registry.
    static func runDocs(_ args: [String]) {
        let opts = Options(args)
        let reg = ContractRegistry.milestone1
        if opts.flag("errors") {
            print("# Error codes\n")
            for e in reg.errors {
                print("## \(e.code) (\(e.ruleId))\n- requiresManual: \(e.requiresManual) · retryable: \(e.retryable)\n- action: \(e.agentAction)\n- \(e.explain)\n")
            }
            return
        }
        if opts.flag("schema") {
            print((try? ContractSchema.json(ContractSchema.teamRunSchema())) ?? "{}")
            print((try? ContractSchema.json(ContractSchema.doctorResultSchema())) ?? "{}")
            return
        }
        if opts.flag("examples") {
            print("# Example recipes\n")
            for ex in reg.examples { print("- `\(ex.id)` — \(ex.title): `\(ex.command)`") }
            return
        }
        if let topic = opts.positional.first {
            if let markdown = HelpService.docsMarkdown(topic: topic) {
                print(markdown)
                return
            }
            let cmds = reg.commands.filter { $0.name == topic || $0.name.hasPrefix(topic + " ") }
            guard !cmds.isEmpty else {
                FileHandle.standardError.write(Data("no docs for topic: \(topic)\n".utf8)); exit(2)
            }
            for c in cmds {
                print("### alln \(c.name)\n\(c.summary)")
                for a in c.args { print("- arg `\(a.name)`\(a.required ? " (required)" : ""): \(a.summary)") }
                for f in c.flags { print("- `--\(f.name)`: \(f.summary)") }
                print("")
            }
            return
        }
        print(ContractDocs.markdown(reg))
    }

    /// Resolves a run reference (`latest` or an id) for `alln show`.
    static func resolveRun(_ ref: String) -> TeamRun? {
        if ref == "latest" { return RunStore().list().max(by: { $0.createdAt < $1.createdAt }) }
        return loadRun(ref)
    }

    /// Query-style verbs (show, spec, floor show) accept `run`; team lifecycle verbs use `runId`.
    /// Accept both keys defensively to prevent silent "latest" drift when callers mix conventions.
    static func runRef(from args: [String: Any]) -> String {
        let ref = (args["run"] as? String) ?? (args["runId"] as? String)
        if let ref, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ref.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "latest"
    }

    /// Resolve a project token (id or repo-root path) to a Project. One SSOT for the
    /// run entrypoints — `alln run` and the team engine resolve the same way.
    static func resolveProject(_ token: String, store: ProjectStore) -> Project? {
        if let byId = try? store.get(token) { return byId }
        let key = RootNormalization.normalize(token).key
        return (try? store.activeProjects())?.first { $0.normalizedRootPath == key }
    }

    /// Resolve a thread reference (`latest` or an id) to a concrete thread id, or nil if no
    /// thread matches. One SSOT for `thread send` / `thread rename`.
    static func resolveThreadId(_ ref: String, store: ThreadStore) -> String? {
        if ref == "latest" { return store.list().first?.id }
        return store.get(ref) != nil ? ref : nil
    }

    /// Default projection context for a persisted run (journal path + reproduce
    /// command derived from the run's own catalog facts).
    static func defaultRunContext(_ run: TeamRun, full: Bool = false) -> TeamRunJSONMapper.Context {
        let runDir = try? RunStore().runDirectory(forRunId: run.id)
        let path = runDir?.appendingPathComponent("run.json").path ?? ""
        return .init(
            runJournalPath: path,
            reproduceCommand: reproduceCommand(run),
            includeWorkerPromptSnapshots: full,
            runDirectory: runDir
        )
    }

    /// The Floor projection JSON for a persisted run, for `alln floor show`.
    static func floorRunJSONString(_ run: TeamRun) -> String {
        let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?
            .appendingPathComponent("run.json").path
        let floor = FloorProjector.project(
            run, reproduceCommand: reproduceCommand(run),
            runJournalPath: journalPath, traceId: "trace_\(run.id)")
        return jsonString(floor)
    }

    /// `alln floor show <run-id|latest> [--json]` — the inspectable Floor for one
    /// team run: worker lanes, durable artifacts, typed return, timeline, and
    /// Execute requirements.
    static func runFloorShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let ref = opts.positional.first ?? "latest"
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        if opts.flag("json") {
            print(floorRunJSONString(run))
        } else {
            let floor = FloorProjector.project(run)
            print("Floor \(run.id) · \(floor.run.status.rawValue) · \(floor.run.family ?? "?")")
            for lane in floor.workerLanes {
                print("  \(lane.purpose.rawValue)\t\(lane.workerId)\t\(lane.status)")
            }
            if let ret = floor.floorReturn { print("\nReturn (\(ret.kind.rawValue)): \(ret.title)") }
        }
    }

    /// `alln show <run-id|latest> [--json] [--full]` — show one run.
    static func runShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln show <run-id|latest> [--json] [--full]\n".utf8)); exit(2)
        }
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        if opts.flag("json") {
            print(jsonString(TeamRunJSONMapper.map(
                run, models: runtime.models, manifests: runtime.registry.all,
                context: defaultRunContext(run, full: opts.flag("full"))
            )))
        } else {
            print("Run \(run.id) · \(run.status.rawValue)")
            print(run.prompt)
            if let plan = run.plan { print("\n\(plan)") }
        }
    }

    /// `alln spec [<run-id>|latest] [--detail summary|full|artifactRefsOnly] [--json]`
    /// — retrieve a run's spec/result packet.
    static func runSpec(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let ref = opts.positional.first ?? "latest"
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        let result = specResult(run, runtime: runtime, detail: opts.value("detail"))
        if opts.flag("json") { print(jsonString(result)) }
        else {
            print(result.summary)
            if let full = result.full, !full.isEmpty { print("\n\(full)") }
            if !result.warnings.isEmpty { print("\nWarnings:"); for w in result.warnings { print("  ⚠︎ \(w)") } }
        }
    }

    /// Project a persisted run into a `SpecRetrieval.Result`.
    static func specResult(_ run: TeamRun, runtime: ToolRuntime, detail: String?) -> SpecRetrieval.Result {
        let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?.appendingPathComponent("run.json").path
        return SpecRetrieval.project(
            run: run, models: runtime.models,
            detail: detail.flatMap(SpecRetrieval.Detail.init(rawValue:)) ?? .summary,
            artifactRefs: journalPath.map { [$0] } ?? [])
    }

    /// `alln export <run-id|latest> --format md` — export the result bundle.
    static func runExport(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln export <run-id|latest> --format md\n".utf8)); exit(2)
        }
        let format = opts.value("format") ?? "md"
        guard format == "md" else {
            fail(code: "CLI_USAGE_ERROR", message: "unsupported export format: \(format) (only md)")
        }
        guard let run = resolveRun(ref) else {
            failRunNotFound(ref == "latest" ? nil : ref, "no run matches \(ref)")
        }
        if let dir = try? RunStore().runDirectory(forRunId: run.id),
           let bundle = try? String(contentsOf: dir.appendingPathComponent("bundle.md"), encoding: .utf8) {
            print(bundle)
        } else {
            print("# \(run.id)\n\n\(run.prompt)\n\n\(run.plan ?? "(no plan)")")
        }
    }

    /// `alln doctor explain <code> [--json]` — explain one registry error code.
    static func runDoctorExplain(_ args: [String]) {
        let opts = Options(args)
        guard let code = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln doctor explain <code> [--json]\n".utf8)); exit(2)
        }
        guard let spec = ContractRegistry.milestone1.errors.first(where: { $0.code == code }) else {
            fail(code: "CLI_USAGE_ERROR", message: "unknown error code: \(code)")
        }
        let bridged = ErrorHelpBridge.explain(spec, contractVersion: ContractRegistry.contractVersion)
        if opts.flag("json") {
            print(jsonString(bridged))
        } else {
            print("\(spec.code)  (\(spec.ruleId))")
            print("  requiresManual: \(spec.requiresManual) · retryable: \(spec.retryable)")
            print("  action: \(spec.agentAction)")
            print("  \(spec.explain)")
            if let ref = bridged.helpRef { print("  help: \(ref)") }
        }
    }

    /// `alln version [--json]` / `alln --version` — binary + contract identity.
    static func runVersion(_ args: [String]) {
        let opts = Options(args)
        let payload = VersionJSON(binaryVersion: binaryVersion)
        if opts.flag("json") {
            print(jsonString(payload))
        } else {
            print("alln \(payload.binaryVersion) (contract \(payload.contractVersion), hash \(payload.contractHash.prefix(12))…)")
        }
    }

    /// `alln bootstrap [--host claude|cursor|codex|generic] [--json]` — the
    /// activation surface that replaced `alln mcp install` (docs/phases/
    /// MCP_Retirement.md §Activation). Prints, never writes: same consent
    /// posture as the retired MCP install.
    static func runBootstrap(_ args: [String]) {
        let opts = Options(args)
        let hostArg = opts.value("host") ?? "generic"
        guard let host = Bootstrap.Host(argument: hostArg) else {
            fail(code: "CLI_USAGE_ERROR", message: "unknown host: \(hostArg) (use claude|cursor|codex|generic)")
        }
        let ctx = Bootstrap.liveContext()
        if opts.flag("json") {
            print(Bootstrap.jsonString(host: host, binaryPath: ctx.binaryPath, onPath: ctx.onPath))
        } else {
            print(Bootstrap.render(host: host, binaryPath: ctx.binaryPath, onPath: ctx.onPath))
        }
    }

    static func runInstallCLI(_ args: [String]) {
        let opts = Options(args)
        let request = InstallCLI.Request(
            argv0: CommandLine.arguments.first,
            pathOverride: opts.value("path"),
            printOnly: opts.flag("print"),
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"]
        )
        switch InstallCLI.run(request) {
        case .printed(let json):
            if opts.flag("json") {
                print(jsonString(json))
            } else {
                let target = json.target ?? "alln"
                let installDir = request.pathOverride
                    ?? InstallCLI.defaultInstallDirectory(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
                print(InstallCLI.printInstructions(target: target, installDir: installDir))
            }
        case .installed(let json):
            if opts.flag("json") {
                print(jsonString(json))
            } else {
                print(InstallCLI.humanLine(json))
            }
        case .failed(let code, let message):
            fail(code: code, message: message)
        }
    }

    static func helpText() -> String {
        """
        alln — local team run, callable by any agent (zero API cost)
          run "<message>" --project <id|path> [--worker <modelId>] [--lane code|design|copy|signal] [--try-fix]  mutating project run (--try-fix: Bug Hunt → gate → one fix)
          team "<question>" [--team id] [--json | --stream]          run a team (--json: TeamRunJSON; --stream: NDJSON)
          team show [--json]                                        show the current default team
          team start "<question>" --json [--lane ...] [--team id]   start async team run (returns run id)
          team status <run-id> --json [--wait-for <state> --timeout <s>]  poll or block-wait async run status
          team result <run-id> --json                             fetch TeamRunJSON when ready
          team cancel <run-id> --json                             cancel an active async run
          team reconcile [run-id] [--all-projects] --json           reap identity-dead async runs (bare: caller's project scope)
          ps [--all-projects] [--json]                              list owned process trees (read-only; project scope by default)
          kill <id> | --all [--all-projects] [--json]               identity-checked total kill + endReason=killed (--all: project scope)
          gc [--json]                                               prune old dead terminal ownership records
          show <run-id|latest> [--json]                             show one run
          export <run-id|latest> --format md                        export a result bundle
          history "<query>" [--json]                                search prior team runs
          models [--json] [--driver <driverId>] [--bench]              list model catalog and Bench state
          models enable|disable <model-id> [--json]                  toggle Bench membership
          models add --driver <id> --name <name> --model-label <l>   add a custom model
          models update|delete <custom-model-id> [--json]            edit or remove a custom model
          boost-window show|set|seed|observations [--json]           configure the Boost window
          doctor [--json] [--full]                                  recovery surface; --full smoke-probes (spends quota)
          doctor explain <code> [--json]                            explain an error/recovery code
          bootstrap [--host claude|cursor|codex|generic] [--json]   paste-ready agent-activation snippet (never edits files)
          version [--json]                                          binary version + contract hash
          docs [topic] [--errors|--schema|--examples]               generated agent-facing reference
          detect                                                    first-run CLI detection, headless
          dev export-contracts [--check]                            regenerate/verify generated contract artifacts
          serve [--health --json]                                 resident coordinator (Serve0 skeleton)
          pair list|approve|revoke|begin [--json]                   manage trusted remote devices
          panel start|round|status|watch|scaffold-brief|done        session-led blind jury on any target
          install-cli [--path <dir>] [--print] [--json]              symlink alln onto your PATH
        """
    }

    static func printHelp() {
        print(helpText())
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? CoreJSON.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// One compact, single-line JSON object — the house law for any `--json` command that
    /// streams progress (FR8): every stdout line, including the final envelope, must
    /// parse independently. Single-envelope commands keep `jsonString` (pretty).
    static func jsonLine<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Loads tool config + builds a `TeamService` from `DefaultConfig` (+ `Config/`
/// overrides when present).
struct ToolRuntime {
    let models: [Model]
    let registry: DriverRegistry
    let teams: [TeamPreset]
    let config: ToolConfig
    /// Cached per-driver invocations from the last detection (health == runs).
    let invocations: [String: ToolInvocation]
    let governor: TeamGovernor
    let asyncTeam: AsyncTeamService
    private let readyModelsOverride: [Model]?

    init() {
        ToolRuntime.applyLoginPath()
        let registry = DefaultConfig.registry
        let models = ModelCatalog.resolvedModels(registry: registry)
        let teams = TeamCatalog.all
        let config = ToolRuntime.loadConfig()
        var invs: [String: ToolInvocation] = [:]
        for record in SetupStore().load().records { if let inv = record.invocation { invs[record.driverId] = inv } }
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.invocations = invs
        let governor = TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.governor = governor
        self.asyncTeam = AsyncTeamService(models: models, registry: registry, teams: teams, config: config, governor: governor, invocations: invs)
        self.readyModelsOverride = nil
    }

    /// Injected runtime for CLI handler tests (isolated async team store).
    init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset],
        config: ToolConfig,
        invocations: [String: ToolInvocation] = [:],
        asyncTeam: AsyncTeamService,
        readyModels: [Model],
        governor: TeamGovernor? = nil
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.invocations = invocations
        self.governor = governor ?? TeamGovernor(capacity: config.maxConcurrentTeamRuns)
        self.asyncTeam = asyncTeam
        self.readyModelsOverride = readyModels
    }

    func service() -> TeamService {
        TeamService(models: models, registry: registry, teams: teams, config: config, governor: governor, invocations: invocations)
    }

    func asyncTeamService() -> AsyncTeamService { asyncTeam }

    /// The ready bench: enabled models whose source probe is ready **and** whose
    /// driver is not capacity-cooling from recent failed runs. Missing setup is
    /// unknown, not ready; cooling Claude/Codex/etc. must not look "ready" in
    /// preflight just because a stale smoke said the binary was found.
    var readyModels: [Model] {
        if let readyModelsOverride { return readyModelsOverride }
        let records = SetupStore().load().records
        let observations = BenchReadiness.recentObservations(from: RunStore().list())
        let cooling = BenchReadiness.coolingDriverIds(observations: observations)
        return BenchReadiness.readyModels(
            models: models,
            probeRecords: records,
            coolingDriverIds: cooling,
            knownDriverIds: Set(registry.all.map(\.id))
        )
    }

    private static func loadConfig() -> ToolConfig {
        let url = AllnighterPaths.config.appendingPathComponent("Tool/config.json")
        if let data = try? Data(contentsOf: url), let cfg = try? CoreJSON.decode(ToolConfig.self, from: data) { return cfg }
        return ToolConfig()
    }

    private static func applyLoginPath() {
        if ProcessInfo.processInfo.environment["ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP"] == "1" { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process(); p.executableURL = URL(fileURLWithPath: shell); p.arguments = ["-lc", "printf %s \"$PATH\""]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return }
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        if exited.wait(timeout: .now() + .seconds(2)) == .timedOut {
            p.terminate()
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { setenv("PATH", path, 1) }
    }
}

/// Tiny argv parser: positionals + `--key value` + `--flag`.
struct Options {
    /// Boolean flags never consume the next token as a value, so
    /// `alln team --json "prompt"` keeps "prompt" as the positional.
    static let booleanFlags: Set<String> = [
        "json", "stream", "full", "check", "errors", "schema", "examples", "quiet", "auto-fix", "health", "submit",
        "bench", "disabled", "no-wait",
    ]
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []
    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if Self.booleanFlags.contains(key) {
                    flags.insert(key); i += 1
                } else if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                    values[key] = args[i + 1]; i += 2
                } else {
                    flags.insert(key); i += 1
                }
            } else { positional.append(a); i += 1 }
        }
    }
    func value(_ key: String) -> String? { values[key] }
    func flag(_ key: String) -> Bool { flags.contains(key) }
}
