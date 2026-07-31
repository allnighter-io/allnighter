import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln loop` — the durable PM↔dev loop object (LVC v7 `docs/phases/Loop_Verb_Cutover.md`
/// §2). This slice (LVC-S02a) wires `loop start` only; `list|status|stop|resume|wait|step|pm`
/// land in later slices. `loop start` dispatches into the existing `pair pilot start` /
/// `pair relay` coordinator paths verbatim — no new coordinator logic here.
enum LoopCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        switch sub {
        case "start": await runStart(Array(args.dropFirst()), runtime: runtime)
        default:
            FileHandle.standardError.write(Data((
                "loop \(sub): not yet implemented in this build — only `loop start` exists so far.\n" +
                "Coming in later slices: list, status, stop, resume, wait, step, pm.\n"
            ).utf8))
            exit(2)
        }
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(Data(
            "usage: alln loop start \"<what you want done>\" [--spec <path>] [--pm caller|<agent-id>] [--dev <agent-id>] [--project <id>] [--dry-run] [--no-wait] [--json]\n"
                .utf8))
        exit(2)
    }

    // MARK: - start

    enum PMSeat: Equatable {
        case caller
        case agent(String)
    }

    struct ResolvedSeats {
        var pm: PMSeat
        var pmSource: String
        var dev: String
        var devSource: String
    }

    static func runStart(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard let brief = opts.positional.first,
              !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            usage()
        }
        let specPath = opts.value("spec")

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

        let seats = resolveSeats(opts: opts, models: runtime.models)

        if opts.flag("dry-run") {
            emitDryRun(brief: brief, specPath: specPath, project: project, seats: seats)
            return
        }

        // Live dispatch reuses the existing coordinator paths untouched. Both paths
        // (RelayCoordinator.Config.docPath / PilotCLI's --doc) still require a spec
        // doc today — making a real (non-dry-run) round run brief-only end to end is
        // LVC-S02's coordinator work, out of scope for this slice (LVC-S02a: CLI +
        // dry-run only). `--dry-run` already resolves and reports readiness brief-only.
        guard let specPath else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "alln loop start needs --spec <path> to actually dispatch a round today — brief-only live dispatch lands in a later loop slice. `--dry-run` already works with the brief alone."
            )
        }

        switch seats.pm {
        case .caller:
            var forwarded = ["--doc", specPath, "--project", project.id, "--dev-model", seats.dev]
            forwarded += passthrough(opts, keys: ["max-rounds", "idle-timeout", "json"])
            await PilotCLI.runStart(forwarded, runtime: runtime)
        case .agent(let pmId):
            var forwarded = ["--doc", specPath, "--project", project.id, "--pm-model", pmId, "--dev-model", seats.dev]
            if opts.value("message") == nil, opts.value("message-file") == nil {
                forwarded += ["--message", brief]
            }
            forwarded += passthrough(
                opts, keys: ["message", "message-file", "until", "max-rounds", "idle-timeout", "no-wait", "json"])
            await RelayCLI.runRelay(forwarded, runtime: runtime)
        }
    }

    /// Rebuilds a `--key value` / `--flag` argv slice from parsed `Options` for the
    /// keys the underlying coordinator path accepts unchanged.
    private static func passthrough(_ opts: Options, keys: [String]) -> [String] {
        var out: [String] = []
        for key in keys {
            if Options.booleanFlags.contains(key) {
                if opts.flag(key) { out.append("--\(key)") }
            } else if let value = opts.value(key) {
                out.append("--\(key)")
                out.append(value)
            }
        }
        return out
    }

    /// `--pm` omitted → Frontier tier default. `--pm caller` → the reserved occupant,
    /// never resolved as a model id. `--pm <id>` → honor-or-fail exact-id resolution,
    /// same choke point `pair relay --pm-model` uses (`RelayCLI.swift:402-405`).
    /// `--dev` mirrors this against the Balanced tier.
    static func resolveSeats(opts: Options, models: [Model]) -> ResolvedSeats {
        let settings = DefaultModelSettingsPersistence().load()

        let pm: PMSeat
        let pmSource: String
        if let pmRaw = opts.value("pm") {
            if pmRaw == "caller" {
                pm = .caller
                pmSource = "caller"
            } else {
                switch ExactIdResolver.resolveWorker(pmRaw, flag: "--pm", models: models) {
                case .success(let model):
                    pm = .agent(model.id)
                    pmSource = "explicit"
                case .failure(let failure):
                    AllnighterCLI.failExactId(failure)
                }
            }
        } else {
            guard let defaultId = settings.tierDefault(.frontier) else {
                AllnighterCLI.fail(
                    code: "CLI_USAGE_ERROR",
                    message: "no Frontier-tier default model is configured — set one in `alln defaults` or pass --pm explicitly"
                )
            }
            pm = .agent(defaultId)
            pmSource = "tier:frontier"
        }

        let dev: String
        let devSource: String
        if let devRaw = opts.value("dev") {
            switch ExactIdResolver.resolveWorker(devRaw, flag: "--dev", models: models) {
            case .success(let model):
                dev = model.id
                devSource = "explicit"
            case .failure(let failure):
                AllnighterCLI.failExactId(failure)
            }
        } else {
            guard let defaultId = settings.tierDefault(.balanced) else {
                AllnighterCLI.fail(
                    code: "CLI_USAGE_ERROR",
                    message: "no Balanced-tier default model is configured — set one in `alln defaults` or pass --dev explicitly"
                )
            }
            dev = defaultId
            devSource = "tier:balanced"
        }

        return ResolvedSeats(pm: pm, pmSource: pmSource, dev: dev, devSource: devSource)
    }

    private static func emitDryRun(brief: String, specPath: String?, project: Project, seats: ResolvedSeats) {
        var warnings: [String] = []
        if let specPath, !FileManager.default.fileExists(atPath: URL(fileURLWithPath: specPath, relativeTo: URL(fileURLWithPath: project.normalizedRootPath)).path) {
            warnings.append("--spec \(specPath) does not exist under \(project.normalizedRootPath) yet — the PM will hit this on round 1")
        }

        let pmOccupant: String
        switch seats.pm {
        case .caller: pmOccupant = "caller"
        case .agent(let id): pmOccupant = id
        }

        let payload = LoopStartDryRunJSON(
            brief: brief,
            specPath: specPath,
            projectId: project.id,
            projectRoot: project.normalizedRootPath,
            pm: .init(occupant: pmOccupant, source: seats.pmSource),
            dev: .init(occupant: seats.dev, source: seats.devSource),
            ready: warnings.isEmpty,
            warnings: warnings,
            nextAction: AgentNextAction(
                kind: "startTeamRun",
                label: "Start the loop for real",
                command: "alln loop start \"\(brief)\"" + (specPath.map { " --spec \($0)" } ?? "")
            )
        )
        print(AllnighterCLI.jsonString(payload))
    }
}
