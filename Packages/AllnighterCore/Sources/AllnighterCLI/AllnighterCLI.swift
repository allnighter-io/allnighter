import Foundation
import AllnighterCore
import AllnighterEngine

/// `allnighter` — Council-as-Tool (RB6). The universal shell surface any terminal
/// agent can call, plus an MCP stdio server. Judgment only: links the council
/// engine, never dispatch/executor code. Local Fusion at zero marginal cost.
@main
struct AllnighterCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }

        let runtime = ToolRuntime()
        switch command {
        case "ask": await runAsk(args, runtime)
        case "presets": await runPresets(args, runtime)
        case "recall": await runRecall(args, runtime)
        case "doctor": await runDoctor(runtime)
        case "detect": await runDetect(runtime)
        case "mcp": await MCPServer(runtime: runtime).serve()
        case "install-cli": printInstallCLI()
        case "mcp-install": printMCPInstall()
        case "help", "--help", "-h": printHelp()
        default:
            FileHandle.standardError.write(Data("unknown command: \(command)\n".utf8)); printHelp(); exit(2)
        }
    }

    // MARK: - Subcommands

    static func runAsk(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let question = opts.positional.first ?? opts.value("question") else {
            FileHandle.standardError.write(Data("usage: allnighter ask \"<question>\" [--preset id] [--context text] [--json]\n".utf8)); exit(2)
        }
        let request = CouncilRequest(question: question, presetId: opts.value("preset"), context: opts.value("context"))
        let result = await runtime.service().run(request, origin: .cli, originAgent: opts.value("agent"))
        if opts.flag("json") {
            print(jsonString(result))
        } else if result.status == .failed && result.runId.isEmpty {
            FileHandle.standardError.write(Data((result.note + "\n").utf8)); exit(1)
        } else {
            print(result.masterPlan ?? "(no master plan — status \(result.status.rawValue))")
            FileHandle.standardError.write(Data("\n[council \(result.preset): \(result.invocations) invocations; run \(result.runId)]\n".utf8))
        }
    }

    static func runPresets(_ args: [String], _ runtime: ToolRuntime) async {
        let summaries = await runtime.service().presetSummaries()
        if Options(args).flag("json") {
            let arr = summaries.map { ["id": $0.id, "name": $0.name, "shape": $0.shape] as [String: Any] }
            print(String(decoding: (try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted])) ?? Data(), as: UTF8.self))
        } else {
            for s in summaries { print("\(s.id)\t\(s.name)\t\(s.shape)") }
        }
    }

    static func runRecall(_ args: [String], _ runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let query = opts.positional.first else {
            FileHandle.standardError.write(Data("usage: allnighter recall \"<query>\"\n".utf8)); exit(2)
        }
        let hits = await runtime.service().recall(query: query)
        if opts.flag("json") {
            print(jsonString(hits))
        } else if hits.isEmpty {
            print("(no prior councils match)")
        } else {
            for h in hits { print("\(h.createdAt) · \(h.runId)\n  \(h.prompt)\n  \(h.masterPlanExcerpt.replacingOccurrences(of: "\n", with: " ").prefix(160))\n") }
        }
    }

    static func runDoctor(_ runtime: ToolRuntime) async {
        let diagnoses = await Doctor(commandRunner: SubprocessCommandRunner()).diagnoseAll(workers: runtime.workers, registry: runtime.registry)
        for d in diagnoses {
            let status = d.isHealthy ? "healthy" : (d.health == .unknown ? "manual" : "UNHEALTHY")
            print("\(d.workerName)\t\(status)\t\(d.version ?? "")")
            if let hint = d.fixHint { print("  → \(hint)") }
        }
    }

    /// First-run CLI detection, headless — proves the detector on a real machine
    /// before any Setup UI (docs/phases/setup/01 §11, Phase 1). Runs real smoke
    /// probes. Note: the CLI uses `DefaultConfig` (no `setup` blocks yet), so bins
    /// fall back to `invoke.command` and loginFlow guidance comes from the app's
    /// bundle registry, not here.
    static func runDetect(_ runtime: ToolRuntime) async {
        var models: [String: String] = [:]
        for w in runtime.workers where models[w.driverId] == nil { models[w.driverId] = w.modelLabel }
        let records = await CLIDetector(commandRunner: SubprocessCommandRunner())
            .probeAll(runtime.registry.all, models: models, now: Date())
        for r in records.sorted(by: { $0.driverId < $1.driverId }) {
            let path = r.invocation?.resolvedPath ?? "—"
            switch r.status {
            case .ready(let v):
                print("\(r.driverId)\tREADY\t\(v)\t\(path)")
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
    }

    static func printInstallCLI() {
        let path = CommandLine.arguments.first ?? "allnighter"
        print("""
        To call `allnighter` from any shell/agent, symlink it onto your PATH:
          ln -sf "\(path)" /usr/local/bin/allnighter
        (Distribution is deferred; this is the dev-build path.)
        """)
    }

    static func printMCPInstall() {
        let path = CommandLine.arguments.first ?? "/path/to/allnighter"
        print("""
        Add this MCP server to your agent's config (Claude Code / Codex / Cursor),
        then restart the agent. Example (Claude Code ~/.claude/mcp or settings):
          { "mcpServers": { "allnighter": { "command": "\(path)", "args": ["mcp"] } } }
        Reachability check: `allnighter presets` should list the council presets.
        """)
    }

    static func printHelp() {
        print("""
        allnighter — local Fusion council, callable by any agent (zero API cost)
          ask "<question>" [--preset id] [--context text] [--json]   run a council
          presets [--json]                                           list presets + work shape
          recall "<query>" [--json]                                  search prior councils (free)
          doctor                                                     check worker CLIs
          mcp                                                        run as an MCP stdio server
          install-cli | mcp-install                                  setup helpers
        """)
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? CoreJSON.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Loads tool config + builds a `CouncilService` from `DefaultConfig` (+ `Config/`
/// overrides when present).
struct ToolRuntime {
    let workers: [Worker]
    let registry: DriverRegistry
    let presets: [PanelPreset]
    let config: ToolConfig

    init() {
        // Bridge the login-shell PATH so spawned CLIs resolve as in a terminal.
        ToolRuntime.applyLoginPath()
        self.workers = DefaultConfig.workers
        self.registry = DefaultConfig.registry
        self.presets = DefaultConfig.tieredPresets(panel: DefaultConfig.workers)
        self.config = ToolRuntime.loadConfig()
    }

    func service() -> CouncilService {
        CouncilService(workers: workers, registry: registry, presets: presets, config: config)
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
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []
    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < args.count && !args[i + 1].hasPrefix("--") { values[key] = args[i + 1]; i += 2 }
                else { flags.insert(key); i += 1 }
            } else { positional.append(a); i += 1 }
        }
    }
    func value(_ key: String) -> String? { values[key] }
    func flag(_ key: String) -> Bool { flags.contains(key) }
}
