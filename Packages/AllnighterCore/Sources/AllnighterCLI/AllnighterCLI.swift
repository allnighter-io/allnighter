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
        case "team" where args.first == "show": runTeamShow(Array(args.dropFirst()), runtime)
        case "team": await runTeam(args, runtime)
        case "models": await runModels(args, runtime)
        case "history": await runHistory(args, runtime)
        case "docs": runDocs(args)
        case "show": runShow(args, runtime)
        case "export": runExport(args, runtime)
        case "doctor" where args.first == "explain": runDoctorExplain(Array(args.dropFirst()))
        case "doctor": await runDoctor(args, runtime)
        case "detect": await runDetect(runtime)
        case "dev": runDev(args)
        case "mcp" where args.first == "install": printMCPInstall()   // consent-gated: prints config, never edits it
        case "mcp": await MCPServer(runtime: runtime).serve()         // `mcp serve --stdio` (or bare)
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
            FileHandle.standardError.write(Data("usage: alln team \"<question>\" [--preset id] [--lane l] [--type t] [--effort e] [--json | --stream]\n".utf8)); exit(2)
        }
        // --json and --stream are mutually exclusive (checked before spending quota).
        if opts.flag("json") && opts.flag("stream") {
            emitFailure(code: "CLI_USAGE_ERROR", message: "--json and --stream are mutually exclusive")
            exit(2)
        }
        let request = TeamRequest(question: question, presetId: opts.value("preset"), context: opts.value("context"))

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
            // M1 step 5 (breaking): emit TeamRunJSON projected from the persisted
            // run, replacing the legacy TeamToolResult shape.
            guard !result.runId.isEmpty, let run = loadRun(result.runId) else {
                emitFailure(code: "RUN_NOT_FOUND", message: result.note.isEmpty ? "team run did not persist" : result.note)
                exit(1)
            }
            let journalPath = (try? RunStore().runDirectory(forRunId: run.id))?
                .appendingPathComponent("run.json").path ?? ""
            let context = TeamRunJSONMapper.Context(
                promptSource: .init(kind: opts.value("file") != nil ? .file : .positional, path: opts.value("file")),
                lane: opts.value("lane"), type: opts.value("type"), effort: opts.value("effort"),
                runJournalPath: journalPath
            )
            let trj = TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: context)
            print(jsonString(trj))
            return
        }

        if result.status == .failed && result.runId.isEmpty {
            FileHandle.standardError.write(Data((result.note + "\n").utf8)); exit(1)
        } else {
            print(result.plan ?? "(no plan — status \(result.status.rawValue))")
            FileHandle.standardError.write(Data("\n[team \(result.preset): \(result.invocations) invocations; run \(result.runId)]\n".utf8))
        }
    }

    /// Loads a persisted run for projection to `TeamRunJSON`.
    static func loadRun(_ runId: String) -> TeamRun? {
        guard let url = try? RunStore().runDirectory(forRunId: runId).appendingPathComponent("run.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CoreJSON.decode(TeamRun.self, from: data)
    }

    /// Emits the shared machine failure envelope (one JSON object on stdout).
    private static func emitFailure(code: String, message: String) {
        struct Failure: Encodable { let schemaVersion = 1; let success = false; let error: ErrorEnvelope }
        let env = ErrorEnvelope(code: code, message: message, requiresManual: code == "RUN_NOT_FOUND", retryable: false)
        print(jsonString(Failure(error: env)))
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

    /// Builds a `DoctorResult` — shared by `alln doctor` and the MCP `doctor` tool
    /// so both project the same contract.
    static func doctorResult(_ runtime: ToolRuntime, full: Bool) async -> DoctorResult {
        var modelLabels: [String: String] = [:]
        for m in runtime.models where modelLabels[m.driverId] == nil { modelLabels[m.driverId] = m.modelLabel }
        let records = await CLIDetector(commandRunner: SubprocessCommandRunner())
            .probeAll(runtime.registry.all, models: modelLabels, now: Date(), smoke: full)
        let inputs = DoctorReport.Inputs(
            binaryVersion: binaryVersion,
            contractVersion: ContractRegistry.contractVersion,
            docsVersionMatchesBinary: true,
            configDirWritable: ensureWritable(AllnighterPaths.config),
            runsDirWritable: ensureWritable(AllnighterPaths.runs),
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
        let records = await CLIDetector(commandRunner: SubprocessCommandRunner())
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

    /// `alln team show [--json]` — the current default team lineup. Does NOT run.
    static func runTeamShow(_ args: [String], _ runtime: ToolRuntime) {
        if Options(args).flag("json") { print(teamShowJSONString(runtime)); return }
        let preset = runtime.presets.first { $0.id == runtime.config.defaultPresetId } ?? runtime.presets.first
        let modelById = Dictionary(runtime.models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let workers = preset?.workerSpecs.expandedWorkers() ?? []
        print("Team: \(preset?.displayName ?? "default") · \(workers.count) workers")
        for w in workers { print("  \(modelById[w.modelId]?.displayName ?? w.modelId)\t\(w.skillId ?? "—")") }
        if let id = preset?.synthesis.planWriterModelId, let m = modelById[id] { print("Plan writer: \(m.displayName)") }
    }

    /// The current-team snapshot JSON — shared by `alln team show --json` and the
    /// MCP `team_show` tool.
    static func teamShowJSONString(_ runtime: ToolRuntime) -> String {
        let preset = runtime.presets.first { $0.id == runtime.config.defaultPresetId } ?? runtime.presets.first
        let modelById = Dictionary(runtime.models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let workers = preset?.workerSpecs.expandedWorkers() ?? []
        struct WorkerView: Encodable { let id, modelId, modelName: String; let skillId: String?; let instanceIndex: Int }
        struct TeamView: Encodable {
            let schemaVersion = 1
            let contractVersion: String
            let teamPresetId: String?
            let planWriterModelId: String?
            let workers: [WorkerView]
        }
        let views = workers.map { w in
            WorkerView(id: w.id, modelId: w.modelId, modelName: modelById[w.modelId]?.displayName ?? w.modelId, skillId: w.skillId, instanceIndex: w.instanceIndex)
        }
        return jsonString(TeamView(contractVersion: ContractRegistry.contractVersion, teamPresetId: preset?.id, planWriterModelId: preset?.synthesis.planWriterModelId, workers: views))
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

    /// Default projection context for a persisted run (run-journal path only).
    static func defaultRunContext(_ run: TeamRun) -> TeamRunJSONMapper.Context {
        let path = (try? RunStore().runDirectory(forRunId: run.id))?.appendingPathComponent("run.json").path ?? ""
        return .init(runJournalPath: path)
    }

    /// `alln show <run-id|latest> [--json]` — show one run.
    static func runShow(_ args: [String], _ runtime: ToolRuntime) {
        let opts = Options(args)
        guard let ref = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: alln show <run-id|latest> [--json]\n".utf8)); exit(2)
        }
        guard let run = resolveRun(ref) else {
            emitFailure(code: "RUN_NOT_FOUND", message: "no run matches \(ref)"); exit(1)
        }
        if opts.flag("json") {
            print(jsonString(TeamRunJSONMapper.map(run, models: runtime.models, manifests: runtime.registry.all, context: defaultRunContext(run))))
        } else {
            print("Run \(run.id) · \(run.status.rawValue)")
            print(run.prompt)
            if let plan = run.plan { print("\n\(plan)") }
        }
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
          show <run-id|latest> [--json]                             show one run
          export <run-id|latest> --format md                        export a result bundle
          history "<query>" [--json]                                search prior team runs
          models [--json]                                           list bench models
          doctor [--json] [--full]                                  recovery surface; --full smoke-probes (spends quota)
          doctor explain <code> [--json]                            explain an error/recovery code
          docs [topic] [--errors|--schema|--examples]               generated agent-facing reference
          detect                                                    first-run CLI detection, headless
          dev export-contracts [--check]                            regenerate/verify generated contract artifacts
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
    let presets: [PanelPreset]
    let config: ToolConfig
    /// Cached per-driver invocations from the last detection (health == runs).
    let invocations: [String: ToolInvocation]

    init() {
        // Bridge the login-shell PATH so spawned CLIs resolve as in a terminal.
        ToolRuntime.applyLoginPath()
        self.models = DefaultConfig.models
        self.registry = DefaultConfig.registry
        self.presets = DefaultConfig.tieredPresets(models: DefaultConfig.models)
        self.config = ToolRuntime.loadConfig()
        var invs: [String: ToolInvocation] = [:]
        for record in SetupStore().load().records { if let inv = record.invocation { invs[record.driverId] = inv } }
        self.invocations = invs
    }

    func service() -> TeamService {
        TeamService(models: models, registry: registry, presets: presets, config: config, invocations: invocations)
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
        "json", "stream", "full", "check", "errors", "schema", "examples", "quiet", "auto-fix",
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
