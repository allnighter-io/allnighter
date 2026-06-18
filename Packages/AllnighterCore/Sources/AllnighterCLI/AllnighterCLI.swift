import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln` — Team-as-Tool (RB6). The universal shell surface any terminal
/// agent can call, plus an MCP stdio server. Judgment only: links the team
/// engine, never dispatch/executor code. Local Fusion at zero marginal cost.
@main
struct AllnighterCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }

        let runtime = ToolRuntime()
        switch command {
        case "teams" where args.first == "show": runTeamsShow(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "duplicate": runTeamsDuplicate(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "edit": runTeamsEdit(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "set-default": runTeamsSetDefault(Array(args.dropFirst()), runtime)
        case "teams" where args.first == "delete": runTeamsDelete(Array(args.dropFirst()), runtime)
        case "teams": runTeamCatalog(args, runtime)
        case "skills" where args.first == "show": runSkillShow(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "duplicate": runSkillsDuplicate(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "new": runSkillsNew(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "edit": runSkillsEdit(Array(args.dropFirst()), runtime)
        case "skills" where args.first == "delete": runSkillsDelete(Array(args.dropFirst()), runtime)
        case "skills": runSkillCatalog(args, runtime)
        case "thread" where args.first == "send": await ThreadSendCLI.runSend(Array(args.dropFirst()), runtime: runtime)
        case "team" where args.first == "show": runTeamShow(Array(args.dropFirst()), runtime)
        case "team" where args.first == "hello": print(mcpHelloJSONString(runtime))
        case "team" where args.first == "preflight": runTeamPreflight(Array(args.dropFirst()), runtime)
        case "team" where args.first == "start": await runTeamStart(Array(args.dropFirst()), runtime)
        case "team" where args.first == "status": await runTeamStatus(Array(args.dropFirst()), runtime)
        case "team" where args.first == "result": await runTeamResult(Array(args.dropFirst()), runtime)
        case "team" where args.first == "cancel": await runTeamCancel(Array(args.dropFirst()), runtime)
        case "team": await runTeam(args, runtime)
        case "models": await runModels(args, runtime)
        case "history": await runHistory(args, runtime)
        case "docs": runDocs(args)
        case "show": runShow(args, runtime)
        case "spec": runSpec(args, runtime)
        case "export": runExport(args, runtime)
        case "doctor" where args.first == "explain": runDoctorExplain(Array(args.dropFirst()))
        case "doctor": await runDoctor(args, runtime)
        case "detect": await runDetect(runtime)
        case "dev": runDev(args)
        case "mcp" where args.first == "install": printMCPInstall()   // consent-gated: prints config, never edits it
        case "mcp": await MCPServer(runtime: runtime).serve()         // `mcp serve --stdio` (or bare)
        case "serve": await runServe(args)
        case "pending": PendingCLI.run(args.first, Array(args.dropFirst()), runtime: runtime)
        case "install-cli": printInstallCLI()
        case "mcp-install": printMCPInstall()
        case "help", "--help", "-h": printHelp()
        default:
            FileHandle.standardError.write(Data("unknown command: \(command)\n".utf8)); printHelp(); exit(2)
        }
    }

    // MARK: - Subcommands

    static func runTeam(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let question = opts.positional.first ?? opts.value("question") else {
            FileHandle.standardError.write(Data("usage: alln team \"<question>\" [--lane build|design|copy] [--team id] [--effort low|med|high] [--type t] [--json | --stream]\n".utf8)); exit(2)
        }
        // --json and --stream are mutually exclusive (checked before spending quota).
        if opts.flag("json") && opts.flag("stream") {
            emitFailure(code: "CLI_USAGE_ERROR", message: "--json and --stream are mutually exclusive")
            exit(2)
        }
        // `--team` is the public selector; `--preset` is a hidden compat alias.
        let teamId = opts.value("team") ?? opts.value("preset")
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use build|design|copy)"); exit(2)
        }
        let effort = opts.value("effort").flatMap(EffortLevel.init(rawValue:))
        if let raw = opts.value("effort"), effort == nil {
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown effort: \(raw) (use low|med|high)"); exit(2)
        }
        let request = TeamRequest(
            question: question, lane: lane, teamPresetId: teamId, effort: effort,
            type: opts.value("type"), context: opts.value("context")
        )

        if opts.flag("stream") {
            // Live NDJSON: emit events as the run progresses, not after it settles.
            let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
            let runTask = Task { await runtime.service().run(request, origin: .cli, originAgent: opts.value("agent"), events: continuation) }
            var mapper = NDJSONStreamProjector.LiveMapper()
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
                emitFailure(code: "RUN_NOT_FOUND", message: "team run did not persist")
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

    /// Emits the shared machine failure envelope (one JSON object on stdout).
    static func emitFailure(code: String, message: String) {
        struct Failure: Encodable { let schemaVersion = 1; let success = false; let error: ErrorEnvelope }
        let env = ErrorEnvelope(code: code, message: message, requiresManual: code == "RUN_NOT_FOUND", retryable: false)
        print(jsonString(Failure(error: env)))
    }

    static func emitCatalogError(_ error: CatalogError, skillContext: Bool = false) -> Never {
        let (code, message) = catalogErrorEnvelope(error, skillContext: skillContext)
        emitFailure(code: code, message: message)
        exit(1)
    }

    static func catalogErrorEnvelope(_ error: CatalogError, skillContext: Bool = false) -> (code: String, message: String) {
        switch error {
        case .teamNotFound: return ("TEAM_NOT_FOUND", "team not found")
        case .skillNotFound: return ("SKILL_NOT_FOUND", "skill not found")
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
        }
    }

    static func runModels(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        if opts.flag("json") {
            print(jsonString(runtime.models))
        } else {
            for m in runtime.models {
                print("\(m.id)\t\(m.displayName)\t\(m.driverId)\t\(m.enabled ? "on" : "off")")
            }
        }
    }

    static func runHistory(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let query = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln history \"<query>\"\n".utf8)); exit(2)
        }
        let hits = await runtime.service().recall(query: query)
        if opts.flag("json") {
            print(jsonString(hits))
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
        let result = await doctorResult(runtime, full: full)
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
            try await ResidentCoordinator(binaryVersion: binaryVersion).runUntilSignal()
        } catch {
            FileHandle.standardError.write(Data("coordinator failed: \(error)\n".utf8)); exit(1)
        }
    }

    /// Builds a `DoctorResult` — shared by `alln doctor` and the MCP `doctor` tool
    /// so both project the same contract.
    static func doctorResult(_ runtime: ToolRuntime, full: Bool) async -> DoctorResult {
        var modelLabels: [String: String] = [:]
        for m in runtime.models where modelLabels[m.driverId] == nil { modelLabels[m.driverId] = m.modelLabel }
        // CLI runs in the user's terminal, so resolve interactively (-lic) to see
        // the same PATH the terminal does (Track 0.1).
        let records = await CLIDetector(commandRunner: SubprocessCommandRunner(), interactive: true)
            .probeAll(runtime.registry.all, models: modelLabels, now: Date(), smoke: full)
        let inputs = DoctorReport.Inputs(
            binaryVersion: binaryVersion,
            contractVersion: ContractRegistry.contractVersion,
            docsVersionMatchesBinary: true,
            configDirWritable: ensureWritable(AllnighterPaths.config),
            runsDirWritable: ensureWritable(AllnighterPaths.runs),
            pendingDirWritable: ensureWritable(AllnighterPaths.pending),
            coordinator: ResidentCoordinatorProbe().doctorCoordinator(),
            full: full
        )
        return DoctorReport.build(models: runtime.models, manifests: runtime.registry.all, records: records, inputs: inputs)
    }

    private static func ensureWritable(_ url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    private static func printDoctorHuman(_ r: DoctorResult, full: Bool) {
        print("alln doctor — \(r.status.rawValue)\(full ? " (full)" : "")")
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
    }

    /// First-run CLI detection, headless — proves the detector on a real machine
    /// before any Setup UI (docs/phases/setup/01 §11, Phase 1). Runs real smoke
    /// probes. Note: the CLI uses `DefaultConfig` (no `setup` blocks yet), so bins
    /// fall back to `invoke.command` and loginFlow guidance comes from the app's
    /// bundle registry, not here.
    static func runDetect(_ runtime: ToolRuntime) async {
        var models: [String: String] = [:]
        for w in runtime.models where models[w.driverId] == nil { models[w.driverId] = w.modelLabel }
        let records = await CLIDetector(commandRunner: SubprocessCommandRunner(), interactive: true)
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
        let artifacts: [ContractExport.Artifact]
        do { artifacts = try ContractExport.artifacts() }
        catch {
            FileHandle.standardError.write(Data("export failed: \(error)\n".utf8)); exit(1)
        }
        let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(ContractExport.generatedDir)

        if opts.flag("check") {
            var drifted: [String] = []
            for a in artifacts {
                let onDisk = try? String(contentsOf: baseURL.appendingPathComponent(a.filename), encoding: .utf8)
                if onDisk != a.contents { drifted.append(a.filename) }
            }
            if drifted.isEmpty {
                print("contracts up to date (\(artifacts.count) artifacts)")
            } else {
                FileHandle.standardError.write(Data("CONTRACT_DRIFT: \(drifted.joined(separator: ", "))\nRun `alln dev export-contracts`, then rebuild.\n".utf8))
                exit(1)
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
                for a in artifacts {
                    try a.contents.write(to: baseURL.appendingPathComponent(a.filename), atomically: true, encoding: .utf8)
                }
                print("wrote \(artifacts.count) artifacts to \(ContractExport.generatedDir)/")
            } catch {
                FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1)
            }
        }
    }

    // MARK: - team show / docs / show / export / doctor explain

    /// `alln team show [--lane build|design|copy] [--json]` — the default team for
    /// each lane (or one lane). Does NOT run.
    static func runTeamShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        if opts.flag("json") { print(teamShowJSONString(runtime, lane: opts.value("lane").flatMap(WorkLane.init(rawValue:)))); return }
        let lanes = opts.value("lane").flatMap(WorkLane.init(rawValue:)).map { [$0] } ?? WorkLane.allCases
        for lane in lanes {
            guard let team = runtime.teams.defaultTeam(for: lane) else { continue }
            let counts = team.workerCountByEffort()
            print("\(lane.rawValue) → \(team.displayName) (\(team.id)) · default \(team.defaultEffort.displayLabel) · \(team.outputKind.rawValue)")
            print("  workers L/M/H: \(counts[.low] ?? 0)/\(counts[.med] ?? 0)/\(counts[.high] ?? 0) · lead \(team.lead.skillId)")
        }
    }

    /// The default-team-per-lane snapshot JSON — shared by `alln team show --json`
    /// and the MCP `team_show` tool.
    static func teamShowJSONString(_ runtime: ToolRuntime, lane: WorkLane? = nil) -> String {
        let lanes = lane.map { [$0] } ?? WorkLane.allCases
        struct TeamView: Encodable {
            let id, displayName, lane, outputKind, defaultEffort: String
            let isDefaultForLane: Bool
            let workerCountByEffort: [String: Int]
        }
        struct Snapshot: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let defaults: [TeamView]
        }
        let defaults = lanes.compactMap { lane -> TeamView? in
            guard let t = runtime.teams.defaultTeam(for: lane) else { return nil }
            let counts = t.workerCountByEffort()
            return TeamView(id: t.id, displayName: t.displayName, lane: t.lane.rawValue,
                            outputKind: t.outputKind.rawValue, defaultEffort: t.defaultEffort.rawValue,
                            isDefaultForLane: true,
                            workerCountByEffort: ["low": counts[.low] ?? 0, "med": counts[.med] ?? 0, "high": counts[.high] ?? 0])
        }
        return jsonString(Snapshot(contractVersion: ContractRegistry.contractVersion, defaults: defaults))
    }

    /// `alln teams [--lane build|design|copy] [--json]` — the lane-scoped team
    /// catalog summary (no full prompt templates).
    static func runTeamCatalog(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use build|design|copy)"); exit(2)
        }
        if opts.flag("json") {
            print(teamsCatalogJSONString(runtime, lane: lane))
        } else {
            let teams = lane.map { runtime.teams.teams(in: $0) } ?? runtime.teams
            for t in teams {
                let c = t.workerCountByEffort()
                print("\(t.id)\t\(t.displayName)\t\(t.lane.rawValue)/\(t.outputKind.rawValue)\tdefault \(t.defaultEffort.rawValue)\tL/M/H \(c[.low] ?? 0)/\(c[.med] ?? 0)/\(c[.high] ?? 0)\(t.isDefaultForLane ? "\t(default)" : "")")
            }
        }
    }

    /// The lane-scoped catalog summary JSON — shared by `alln teams --json`
    /// and the MCP `teams_list` tool.
    static func teamsCatalogJSONString(_ runtime: ToolRuntime, lane: WorkLane?) -> String {
        let teams = lane.map { runtime.teams.teams(in: $0) } ?? runtime.teams
        struct TeamSummary: Encodable {
            let id, displayName, lane, outputKind, defaultEffort: String
            let builtIn, isDefaultForLane: Bool
            let workerCountByEffort: [String: Int]
            let disabledReason: String?
        }
        struct Catalog: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let lane: String?
            let teams: [TeamSummary]
        }
        let summaries = teams.map { t -> TeamSummary in
            let c = t.workerCountByEffort()
            return TeamSummary(id: t.id, displayName: t.displayName, lane: t.lane.rawValue,
                               outputKind: t.outputKind.rawValue, defaultEffort: t.defaultEffort.rawValue,
                               builtIn: t.builtIn, isDefaultForLane: t.isDefaultForLane,
                               workerCountByEffort: ["low": c[.low] ?? 0, "med": c[.med] ?? 0, "high": c[.high] ?? 0],
                               disabledReason: nil)
        }
        return jsonString(Catalog(contractVersion: ContractRegistry.contractVersion, lane: lane?.rawValue, teams: summaries))
    }

    /// `alln skills [--lane build|design|copy] [--json]` — lane-scoped skill catalog (no templates).
    static func runSkillCatalog(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let lane = opts.value("lane").flatMap(WorkLane.init(rawValue:))
        if let raw = opts.value("lane"), lane == nil {
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown lane: \(raw) (use build|design|copy)"); exit(2)
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
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln skills show <skill-id> [--json]"); exit(2)
        }
        guard let skill = SkillCatalog.get(id) else {
            emitFailure(code: "SKILL_NOT_FOUND", message: "unknown skill: \(id)"); exit(2)
        }
        if opts.flag("json") {
            print(skillShowJSONString(skill))
        } else {
            print("\(skill.id)\t\(skill.displayName)\t\(skill.lane.rawValue)\t\(skill.purpose.rawValue)")
            print(skill.template)
        }
    }

    static func skillsCatalogJSONString(lane: WorkLane?) -> String {
        struct SkillSummary: Encodable {
            let id, displayName, lane, purpose: String
            let builtIn: Bool
        }
        struct Catalog: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let lane: String?
            let skills: [SkillSummary]
        }
        let skills: [Skill]
        if let lane {
            skills = SkillCatalog.list(lane: lane)
        } else {
            skills = WorkLane.allCases.flatMap { SkillCatalog.list(lane: $0) }
        }
        let summaries = skills.map {
            SkillSummary(id: $0.id, displayName: $0.displayName, lane: $0.lane.rawValue,
                         purpose: $0.purpose.rawValue, builtIn: $0.builtIn)
        }
        return jsonString(Catalog(contractVersion: ContractRegistry.contractVersion, lane: lane?.rawValue, skills: summaries))
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

    /// `alln teams show <team-id> [--json]` — one team including worker rows.
    static func runTeamsShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln teams show <team-id> [--json]"); exit(2)
        }
        guard let team = TeamCatalog.get(id) else {
            emitFailure(code: "TEAM_NOT_FOUND", message: "unknown team: \(id)"); exit(2)
        }
        if opts.flag("json") { print(teamShowJSONString(team)) }
        else {
            print("\(team.id)\t\(team.displayName)\t\(team.lane.rawValue)/\(team.outputKind.rawValue)")
            for row in team.workerSpecs {
                print("  \(row.id)\t\(row.skillId)\t\(row.purpose.rawValue)\t\(row.minEffort.rawValue)")
            }
        }
    }

    static func teamShowJSONString(_ team: TeamPreset) -> String {
        struct WorkerRow: Encodable {
            let id, skillId, purpose, minEffort: String
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
        }
        let rows = team.workerSpecs.map {
            WorkerRow(id: $0.id, skillId: $0.skillId, purpose: $0.purpose.rawValue,
                      minEffort: $0.minEffort.rawValue, count: $0.count, required: $0.required)
        }
        return jsonString(Detail(
            contractVersion: ContractRegistry.contractVersion,
            id: team.id, displayName: team.displayName, lane: team.lane.rawValue,
            outputKind: team.outputKind.rawValue, defaultEffort: team.defaultEffort.rawValue,
            builtIn: team.builtIn, isDefaultForLane: team.isDefaultForLane,
            description: team.description, workerSpecs: rows
        ))
    }

    /// `alln teams duplicate <team-id> [--name <displayName>] [--json]`
    static func runTeamsDuplicate(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln teams duplicate <team-id> [--name <name>] [--json]"); exit(2)
        }
        do {
            let team = try TeamCatalog.duplicateBuiltIn(id, name: opts.value("name"))
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("duplicated \(id) → \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    /// `alln teams edit <team-id> [--file <path>] [--json]` — full replacement save.
    static func runTeamsEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln teams edit <team-id> [--file <path>] [--json]"); exit(2)
        }
        guard TeamCatalog.get(id) != nil else {
            emitFailure(code: "TEAM_NOT_FOUND", message: "unknown team: \(id)"); exit(2)
        }
        do {
            let team = try loadTeamDefinition(from: opts.value("file"), expectedId: id)
            try TeamCatalog.saveCustom(team)
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("saved \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    /// `alln teams set-default <team-id> [--json]`
    static func runTeamsSetDefault(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln teams set-default <team-id> [--json]"); exit(2)
        }
        do {
            let team = try TeamCatalog.setDefault(id)
            if opts.flag("json") { print(teamShowJSONString(team)) }
            else { print("default for \(team.lane.rawValue) → \(team.id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    /// `alln teams delete <team-id> [--json]`
    static func runTeamsDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln teams delete <team-id> [--json]"); exit(2)
        }
        do {
            try TeamCatalog.deleteCustom(id)
            if opts.flag("json") { print(jsonString(DeleteAck(deleted: id))) }
            else { print("deleted \(id)") }
        } catch let error as CatalogError { emitCatalogError(error) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
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
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln skills duplicate <skill-id> [--name <name>] [--json]"); exit(2)
        }
        do {
            let skill = try SkillCatalog.duplicateBuiltIn(id, name: opts.value("name"))
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("duplicated \(id) → \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    /// `alln skills new --lane <lane> --name <name> --purpose <purpose> [--template-file <path>] [--json]`
    static func runSkillsNew(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let laneRaw = opts.value("lane"), let lane = WorkLane(rawValue: laneRaw) else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln skills new --lane build|design|copy --name <name> --purpose answer|review|planWriter [--template-file <path>] [--json]"); exit(2)
        }
        guard let name = opts.value("name"), !name.isEmpty else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "--name is required"); exit(2)
        }
        guard let purposeRaw = opts.value("purpose"), let purpose = SkillPurpose(rawValue: purposeRaw) else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "--purpose must be answer, review, or planWriter"); exit(2)
        }
        let template: String
        do { template = try loadTemplateText(opts.value("template-file")) }
        catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
        do {
            let skill = try SkillCatalog.createCustom(lane: lane, name: name, purpose: purpose, template: template)
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("created \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    /// `alln skills edit <skill-id> [--name <displayName>] [--template-file <path>] [--json]`
    static func runSkillsEdit(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln skills edit <skill-id> [--name <name>] [--template-file <path>] [--json]"); exit(2)
        }
        guard var skill = SkillCatalog.get(id) else {
            emitFailure(code: "SKILL_NOT_FOUND", message: "unknown skill: \(id)"); exit(2)
        }
        if let name = opts.value("name") { skill.displayName = name }
        do {
            if let path = opts.value("template-file") { skill.template = try loadTemplateText(path) }
            try SkillCatalog.saveCustom(skill)
            if opts.flag("json") { print(skillShowJSONString(skill)) }
            else { print("saved \(skill.id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    /// `alln skills delete <skill-id> [--json]`
    static func runSkillsDelete(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let id = opts.positional.first else {
            emitFailure(code: "CLI_USAGE_ERROR", message: "usage: alln skills delete <skill-id> [--json]"); exit(2)
        }
        do {
            try SkillCatalog.deleteCustom(id)
            if opts.flag("json") { print(jsonString(DeleteAck(deleted: id))) }
            else { print("deleted \(id)") }
        } catch let error as CatalogError { emitCatalogError(error, skillContext: true) }
        catch { emitFailure(code: "CLI_USAGE_ERROR", message: "\(error)"); exit(1) }
    }

    static func loadTemplateText(_ path: String?) throws -> String {
        guard let path else { return "You are a helpful specialist for this lane." }
        return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    struct DeleteAck: Encodable {
        let schemaVersion = 1
        let deleted: String
    }

    /// The agent bootstrap snapshot JSON — shared by `alln team hello` and the MCP
    /// `mcp_hello` tool. Cheap, non-mutating, quota-free (cached readiness).
    static func mcpHelloJSONString(_ runtime: ToolRuntime) -> String {
        let verdict = AgentReadiness.evaluate(teams: runtime.teams, readyModels: runtime.readyModels)
        struct ToolRef: Encodable { let name: String; let schemaRef: String }
        struct Quickstart: Encodable {
            let recommendedAfterHello = "team_preflight when canStartTeamRun is true; doctor when false"
            let whenToUseTeamStart = "Use for review, fanout, bug hunt, design, copy, or long work."
            let whenToUsePending = "Use when the user wants work later or admission blocks."
            let whenToUseSpecGet = "Use when the user asks for the full packet/spec."
        }
        struct Hello: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let binaryVersion: String
            let docsVersionMatchesBinary = true
            let canStartTeamRun: Bool
            let readyTeams: [ReadyTeam]
            let blockedReason: String?
            let nextAction: AgentNextAction
            let tools: [ToolRef]
            let quickstart = Quickstart()
        }
        let tools = ContractRegistry.milestone1.mcpTools.map { ToolRef(name: $0.name, schemaRef: "tool://\($0.name).schema.json") }
        return jsonString(Hello(
            contractVersion: ContractRegistry.contractVersion, binaryVersion: binaryVersion,
            canStartTeamRun: verdict.canStartTeamRun, readyTeams: verdict.readyTeams,
            blockedReason: verdict.blockedReason, nextAction: verdict.nextAction, tools: tools))
    }

    /// `alln team preflight [--lane l] [--team id] [--effort e] [--type t]` — resolve
    /// against the ready bench without running. Always prints JSON.
    static func runTeamPreflight(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        var dict: [String: Any] = [:]
        for k in ["lane", "team", "effort", "type"] { if let v = opts.value(k) { dict[k] = v } }
        print(jsonString(preflight(runtime, args: dict)))
    }

    /// Run preflight from CLI/MCP args (lane/team/type/effort) against the ready bench.
    static func preflight(_ runtime: ToolRuntime, args: [String: Any]) -> TeamPreflight.Result {
        TeamPreflight.preflight(
            teams: runtime.teams,
            lane: (args["lane"] as? String).flatMap(WorkLane.init(rawValue:)),
            teamId: args["team"] as? String,
            type: args["type"] as? String,
            effort: (args["effort"] as? String).flatMap(EffortLevel.init(rawValue:)),
            readyModels: runtime.readyModels)
    }

    static func parseAsyncTeamStart(_ args: [String], _ opts: Options) -> AsyncTeamStartRequest? {
        guard let question = opts.positional.first ?? opts.value("question") else { return nil }
        return AsyncTeamStartRequest(
            question: question,
            lane: opts.value("lane").flatMap(WorkLane.init(rawValue:)),
            teamPresetId: opts.value("team") ?? opts.value("preset"),
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

    /// `alln team start ... --json` — async start; returns run id after preflight + journal write.
    static func runTeamStart(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json") else {
            FileHandle.standardError.write(Data("usage: alln team start \"<prompt>\" --json [--lane build|design|copy] [--team id] [--effort low|med|high] [--idempotency-key key]\n".utf8))
            exit(2)
        }
        guard let request = parseAsyncTeamStart(args, opts) else {
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
        let outcome = await runtime.asyncTeamService().start(request, origin: .cli, readyModels: runtime.readyModels)
        switch outcome {
        case .success(let response):
            print(jsonString(response))
        case .failure(let refusal):
            emitFailure(code: refusal.code, message: refusal.message)
            exit(1)
        }
    }

    /// `alln team status <run-id> --json`
    static func runTeamStatus(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.flag("json"), let runId = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln team status <run-id> --json\n".utf8))
            exit(2)
        }
        guard let status = await runtime.asyncTeamService().status(runId: runId) else {
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(runId)")
            exit(1)
        }
        print(jsonString(status))
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
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(runId)")
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
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(runId)")
            exit(1)
        }
        print(jsonString(response))
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

    /// Resolves a run reference (`latest` or an id). Shared by `alln show` and the
    /// MCP `show` tool.
    static func resolveRun(_ ref: String) -> TeamRun? {
        if ref == "latest" { return RunStore().list().max(by: { $0.createdAt < $1.createdAt }) }
        return loadRun(ref)
    }

    /// Default projection context for a persisted run (journal path + reproduce
    /// command derived from the run's own catalog facts).
    static func defaultRunContext(_ run: TeamRun, full: Bool = false) -> TeamRunJSONMapper.Context {
        let path = (try? RunStore().runDirectory(forRunId: run.id))?.appendingPathComponent("run.json").path ?? ""
        return .init(runJournalPath: path, reproduceCommand: reproduceCommand(run), includeWorkerPromptSnapshots: full)
    }

    /// `alln show <run-id|latest> [--json] [--full]` — show one run.
    static func runShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln show <run-id|latest> [--json] [--full]\n".utf8)); exit(2)
        }
        guard let run = resolveRun(ref) else {
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(ref)"); exit(1)
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
    /// — retrieve a run's spec/result packet. Shared with the MCP `spec_get` tool.
    static func runSpec(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        let ref = opts.positional.first ?? "latest"
        guard let run = resolveRun(ref) else {
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(ref)"); exit(1)
        }
        let result = specResult(run, runtime: runtime, detail: opts.value("detail"))
        if opts.flag("json") { print(jsonString(result)) }
        else {
            print(result.summary)
            if let full = result.full, !full.isEmpty { print("\n\(full)") }
            if !result.warnings.isEmpty { print("\nWarnings:"); for w in result.warnings { print("  ⚠︎ \(w)") } }
        }
    }

    /// Project a persisted run into a `SpecRetrieval.Result` (shared CLI/MCP).
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
            emitFailure(code: "CLI_USAGE_ERROR", message: "unsupported export format: \(format) (only md)"); exit(2)
        }
        guard let run = resolveRun(ref) else {
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(ref)"); exit(1)
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
            emitFailure(code: "CLI_USAGE_ERROR", message: "unknown error code: \(code)"); exit(2)
        }
        if opts.flag("json") {
            print(jsonString(spec))
        } else {
            print("\(spec.code)  (\(spec.ruleId))")
            print("  requiresManual: \(spec.requiresManual) · retryable: \(spec.retryable)")
            print("  action: \(spec.agentAction)")
            print("  \(spec.explain)")
        }
    }

    static func printInstallCLI() {
        let path = CommandLine.arguments.first ?? "alln"
        print("""
        To call `alln` from any shell/agent, symlink it onto your PATH:
          ln -sf "\(path)" /usr/local/bin/alln
        (Distribution is deferred; this is the dev-build path.)
        """)
    }

    static func printMCPInstall() {
        let path = CommandLine.arguments.first ?? "/path/to/alln"
        print("""
        Add this MCP server to your agent's config (Claude Code / Codex / Cursor),
        then restart the agent. Example (Claude Code ~/.claude/mcp or settings):
          { "mcpServers": { "alln": { "command": "\(path)", "args": ["mcp"] } } }
        Reachability check: `alln models` should list the Bench models.
        """)
    }

    static func printHelp() {
        print("""
        alln — local team run, callable by any agent (zero API cost)
          team "<question>" [--preset id] [--json | --stream]        run a team (--json: TeamRunJSON; --stream: NDJSON)
          team show [--json]                                        show the current default team
          team start "<question>" --json [--lane ...] [--team id]   start async team run (returns run id)
          team status <run-id> --json                             poll async run status
          team result <run-id> --json                             fetch TeamRunJSON when ready
          team cancel <run-id> --json                             cancel an active async run
          show <run-id|latest> [--json]                             show one run
          export <run-id|latest> --format md                        export a result bundle
          history "<query>" [--json]                                search prior team runs
          models [--json]                                           list bench models
          doctor [--json] [--full]                                  recovery surface; --full smoke-probes (spends quota)
          doctor explain <code> [--json]                            explain an error/recovery code
          docs [topic] [--errors|--schema|--examples]               generated agent-facing reference
          detect                                                    first-run CLI detection, headless
          dev export-contracts [--check]                            regenerate/verify generated contract artifacts
          serve [--health --json]                                 resident coordinator (Serve0 skeleton)
          mcp                                                       run as an MCP stdio server
          install-cli | mcp-install                                 setup helpers
        """)
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? CoreJSON.encode(value) else { return "{}" }
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
    let asyncTeam: AsyncTeamService
    private let readyModelsOverride: [Model]?

    init() {
        ToolRuntime.applyLoginPath()
        let models = DefaultConfig.models
        let registry = DefaultConfig.registry
        let teams = TeamCatalog.all
        let config = ToolRuntime.loadConfig()
        var invs: [String: ToolInvocation] = [:]
        for record in SetupStore().load().records { if let inv = record.invocation { invs[record.driverId] = inv } }
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.invocations = invs
        self.asyncTeam = AsyncTeamService(models: models, registry: registry, teams: teams, config: config, invocations: invs)
        self.readyModelsOverride = nil
    }

    /// Injected runtime for MCP/CLI handler tests (isolated async team store).
    init(
        models: [Model],
        registry: DriverRegistry,
        teams: [TeamPreset],
        config: ToolConfig,
        invocations: [String: ToolInvocation] = [:],
        asyncTeam: AsyncTeamService,
        readyModels: [Model]
    ) {
        self.models = models
        self.registry = registry
        self.teams = teams
        self.config = config
        self.invocations = invocations
        self.asyncTeam = asyncTeam
        self.readyModelsOverride = readyModels
    }

    func service() -> TeamService {
        TeamService(models: models, registry: registry, teams: teams, config: config, invocations: invocations)
    }

    func asyncTeamService() -> AsyncTeamService { asyncTeam }

    /// The ready bench from cached detection (no quota): enabled models whose
    /// source was detected ready. Falls back to all enabled models when no
    /// detection cache exists yet (fresh dev environment — optimistic, not a lie:
    /// a per-worker failure still surfaces honestly at run time).
    var readyModels: [Model] {
        if let readyModelsOverride { return readyModelsOverride }
        let readyDrivers = TeamAssembler.readyDriverIds(from: SetupStore().load().records)
        guard !readyDrivers.isEmpty else { return models.filter(\.enabled) }
        return models.filter { $0.enabled && readyDrivers.contains($0.driverId) }
    }

    private static func loadConfig() -> ToolConfig {
        let url = AllnighterPaths.config.appendingPathComponent("Tool/config.json")
        if let data = try? Data(contentsOf: url), let cfg = try? CoreJSON.decode(ToolConfig.self, from: data) { return cfg }
        return ToolConfig()
    }

    private static func applyLoginPath() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process(); p.executableURL = URL(fileURLWithPath: shell); p.arguments = ["-lic", "printf %s \"$PATH\""]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
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
