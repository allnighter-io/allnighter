import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln loop` — the durable PM↔dev loop object (LVC v7 `docs/phases/Loop_Verb_Cutover.md`
/// §2). This slice (LVC-S02a/S02b) wires `loop start` only; `list|status|stop|resume|wait|
/// step|pm` land in later slices. `loop start` builds `RelayCoordinator.Config`/
/// `PilotCLI.StartRequest` directly and dispatches into the existing `PilotCLI`/`RelayCLI`
/// coordinator entry points — `docPath` is `nil` when `--spec` is omitted (LVC-S02b: a brief
/// with no doc still starts a real loop); `pair pilot start`/`pair relay` themselves keep
/// hard-requiring `--doc`, unchanged.
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

        // LVC-S02b: `--spec` is a shortcut, not the shape (LVC v7 §2) — a brief with no
        // doc dispatches a real loop. `Config`/`StartRequest` are built here directly
        // (not via `RelayCLI.parseStartConfig`/`PilotCLI.parseStartConfig`, which keep
        // hard-requiring `--doc` for the retired `pair relay`/`pilot start` verbs) so
        // `docPath` can be `nil` while `brief` always carries the work.
        guard let maxRounds = RelayCLI.parseMaxRounds(opts.value("max-rounds")) else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "--max-rounds must be a positive integer, got \"\(opts.value("max-rounds") ?? "")\""
            )
        }
        let untilParsed = RelayDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--until could not be parsed: \"\(bad)\"")
        }
        let idleParsed = RunCLI.parseIdleTimeoutSeconds(opts.value("idle-timeout"))
        if let error = idleParsed.error {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error)
        }

        switch seats.pm {
        case .caller:
            // Pilot has no clock and no PM prompt of its own — the live session IS the
            // PM and already holds the brief in its own context, so nothing needs it
            // injected. `--until` is refused by `startPilot` itself (untilNotSupported).
            let config = RelayCoordinator.Config(
                projectRoot: project.normalizedRootPath,
                projectId: project.id,
                docPath: specPath,
                brief: brief,
                pmModelId: RelayState.externalPMModelId,
                devModelId: seats.dev,
                maxRounds: maxRounds,
                until: untilParsed.value,
                devTurnIdleTimeoutSeconds: idleParsed.value
            )
            let request = PilotCLI.StartRequest(
                config: config, devModelId: seats.dev, devWorkerAlias: nil, rememberedDevWorker: false
            )
            await PilotCLI.runStart(request: request, opts: opts, runtime: runtime)
        case .agent(let pmId):
            let kickoffMessage: String?
            do {
                kickoffMessage = try RelayCLI.parseKickoffMessage(opts) ?? brief
            } catch let error as RelayCLI.RelayCLIError {
                RelayCLI.fail(error)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
            }
            let config = RelayCoordinator.Config(
                projectRoot: project.normalizedRootPath,
                projectId: project.id,
                docPath: specPath,
                brief: brief,
                pmModelId: pmId,
                devModelId: seats.dev,
                maxRounds: maxRounds,
                until: untilParsed.value,
                devTurnIdleTimeoutSeconds: idleParsed.value,
                kickoffMessage: kickoffMessage
            )
            await RelayCLI.runRelay(config: config, opts: opts, runtime: runtime)
        }
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
