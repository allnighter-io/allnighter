import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln loop` — the durable PM↔dev loop object (LVC v7 `docs/phases/Loop_Verb_Cutover.md`
/// §2). LVC-S02a/S02b/S02c wired `start|list|status|stop|resume|wait`; this slice
/// (LVC-S02d) adds the last two verbs, `step` and `pm`. `loop start` builds
/// `RelayCoordinator.Config`/
/// `PilotCLI.StartRequest` directly and dispatches into the existing `PilotCLI`/`RelayCLI`
/// coordinator entry points — `docPath` is `nil` when `--spec` is omitted (LVC-S02b: a brief
/// with no doc still starts a real loop); `pair pilot start`/`pair relay` themselves keep
/// hard-requiring `--doc`, unchanged. `status|stop|resume|wait` are chair-neutral: the
/// underlying `RelayState` is one substrate for both `--pm caller` and spawned-PM loops
/// (`RelayJSON.project`/`RelayCLI.runStatus` carry no pmMode branching), so a single
/// positional `<loop-id>` forwards straight into the existing `--relay <id>` entry points —
/// no chair lookup needed before dispatch.
enum LoopCLI {
    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        let rest = Array(args.dropFirst())
        switch sub {
        case "start": await runStart(rest, runtime: runtime)
        case "list": runList(rest)
        case "status":
            RelayCLI.runStatus(loopArgs(rest, usageLine: "loop status <loop-id> [--wait-for parked|terminal --timeout <seconds>] [--json]"))
        case "stop":
            RelayCLI.runStop(loopArgs(rest, usageLine: "loop stop <loop-id> [--json]"), runtime: runtime)
        case "resume":
            await RelayCLI.runResume(loopArgs(rest, usageLine: "loop resume <loop-id> --answer <text> [--until HH:MM] [--max-rounds N] [--no-wait] [--json]"), runtime: runtime)
        case "wait":
            PilotCLI.runWatch(loopArgs(rest, usageLine: "loop wait <loop-id> [--max-wait <seconds>] [--json]"))
        case "step":
            await runStep(rest, runtime: runtime)
        case "pm":
            await runPm(rest, runtime: runtime)
        default:
            FileHandle.standardError.write(Data(
                "loop \(sub): not recognized — start|list|status|stop|resume|wait|step|pm.\n".utf8
            ))
            exit(2)
        }
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(Data(
            "usage: alln loop start \"<what you want done>\" [--spec <path>] [--pm caller|<agent-id>] [--dev <agent-id>] [--project <id>] [--dry-run] [--no-wait] [--json]\n"
                .utf8))
        exit(2)
    }

    /// `status|stop|resume|wait` all take a positional `<loop-id>` where the older
    /// `pair relay*`/`pair pilot*` verbs took `--relay <id>`. Reconstructs the flag-only
    /// call those entry points already expect, forwarding every other flag the caller
    /// passed untouched — never dropping `--wait-for`/`--answer`/`--json`/etc.
    static func loopArgs(_ args: [String], usageLine: String) -> [String] {
        let opts = Options(args)
        guard let loopId = opts.positional.first, !loopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            FileHandle.standardError.write(Data("usage: alln \(usageLine)\n".utf8))
            exit(2)
        }
        var forwarded: [String] = ["--relay", loopId]
        for key in opts.flags where key != "relay" {
            forwarded.append("--\(key)")
        }
        for (key, value) in opts.values where key != "relay" {
            forwarded.append("--\(key)")
            forwarded.append(value)
        }
        return forwarded
    }

    // MARK: - list

    static func runList(
        _ args: [String],
        projectStore: ProjectStore = ProjectStore(),
        relayStateStore: RelayStateStore = RelayStateStore()
    ) {
        let opts = Options(args)
        let project = resolveProject(opts: opts, store: projectStore)

        let entries = relayStateStore.list()
            .filter { $0.projectRoot == project.normalizedRootPath }
            .map { state -> LoopListJSON.Entry in
                LoopListJSON.Entry(
                    id: state.id,
                    status: state.status.rawValue,
                    briefOrSpec: state.docPathOrBrief,
                    pm: state.pmMode == .external ? "caller" : state.pmModelId,
                    dev: state.devModelId,
                    updatedAt: state.finishedAt ?? state.rounds.last?.startedAt ?? state.createdAt
                )
            }

        let payload = LoopListJSON(projectId: project.id, projectRoot: project.normalizedRootPath, loops: entries)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
        } else if entries.isEmpty {
            print("no loops for \(project.normalizedRootPath)")
        } else {
            for entry in entries {
                print("\(entry.id)  \(entry.status)  pm=\(entry.pm) dev=\(entry.dev)  \(entry.briefOrSpec)")
            }
        }
    }

    /// Shared with `runStart` — `--project <id|name|path>` or resolved from cwd.
    private static func resolveProject(opts: Options, store: ProjectStore = ProjectStore()) -> Project {
        if let projectToken = opts.value("project") {
            guard let resolved = AllnighterCLI.resolveProject(projectToken, store: store) else {
                AllnighterCLI.fail(code: "PROJECT_NOT_FOUND", message: "project not found: \(projectToken)")
            }
            return resolved
        }
        if let resolved = AllnighterCLI.resolveProjectFromCwd(store: store) {
            return resolved
        }
        let cwd = FileManager.default.currentDirectoryPath
        let gitRoot = GitObserver().repoTopLevel(forPath: cwd) ?? cwd
        AllnighterCLI.fail(
            code: "PROJECT_NOT_FOUND",
            message: "no registered project for \(gitRoot) — run `alln project add \(gitRoot)`"
        )
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
        let project = resolveProject(opts: opts)

        let seats = resolveSeats(opts: opts, models: runtime.models)

        if opts.flag("dry-run") {
            emitDryRun(brief: brief, specPath: specPath, pmRaw: opts.value("pm"), devRaw: opts.value("dev"), project: project, seats: seats)
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

    private static func emitDryRun(
        brief: String, specPath: String?, pmRaw: String?, devRaw: String?, project: Project, seats: ResolvedSeats
    ) {
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
                command: buildStartCommand(brief: brief, specPath: specPath, pmRaw: pmRaw, devRaw: devRaw)
            )
        )
        print(AllnighterCLI.jsonString(payload))
    }

    /// The reproduce command must echo back every explicitly-supplied flag and omit
    /// only the ones the caller actually omitted — a defaulted `--pm`/`--dev` (tier
    /// default, never typed) must NOT appear, or a caller following the printed
    /// command silently loses the casting they asked for.
    static func buildStartCommand(brief: String, specPath: String?, pmRaw: String?, devRaw: String?) -> String {
        var command = "alln loop start \"\(brief)\""
        if let specPath { command += " --spec \(specPath)" }
        if let pmRaw { command += " --pm \(pmRaw)" }
        if let devRaw { command += " --dev \(devRaw)" }
        return command
    }

    // MARK: - step (was `pair pilot handoff`)

    /// `alln loop step <loop-id> <message>` / `alln loop step <loop-id> --done <summary>`
    /// (LVC v7 §2, Law 3 — `docs/phases/Loop_Verb_Cutover.md` §3). `step` is
    /// chair-neutral BY DEFINITION: it is accepted only when the loop's durable
    /// `status == .awaitingPM`, checked on the status alone, never on `pmMode`/who
    /// holds the chair. `awaitingPM` is documented Pilot-only (`RelayState.swift:195-202`)
    /// — an agent-occupied loop dispatches its own decision inside `RelayCoordinator`
    /// and so is never observably `awaitingPM`; that is what makes this chair-neutral
    /// without ever consulting the occupant. Do NOT add a `pmMode`/occupant check here —
    /// that was v5's Law 3 violation (corrected in v6/v7).
    static func runStep(
        _ args: [String], runtime: ToolRuntime,
        stateStore: RelayStateStore = RelayStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async {
        let opts = Options(args)
        guard let loopId = opts.positional.first, !loopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stepUsage()
        }
        let doneSummary = opts.value("done")
        let message = opts.positional.count > 1 ? opts.positional[1] : nil
        if doneSummary != nil, message != nil {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "loop step takes either a message or --done <summary>, not both"
            )
        }

        let submission: String
        do {
            if let doneSummary {
                submission = try PilotCLI.synthesizeSubmission(verdict: .done, handover: nil, note: doneSummary)
            } else if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submission = try PilotCLI.synthesizeSubmission(verdict: .continueRelay, handover: message, note: nil)
            } else {
                stepUsage()
            }
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        guard let state = stateStore.load(id: loopId) else {
            AllnighterCLI.fail(code: "RELAY_NOT_FOUND", message: "loop not found: \(loopId)")
        }
        guard state.status == .awaitingPM else {
            AllnighterCLI.fail(
                code: "RELAY_NOT_AWAITING_PM",
                message: "loop is not awaiting a PM decision (status: \(state.status.rawValue))"
            )
        }

        let projectId = projectStore.resolveFresh(state.projectRoot)?.id
        let emitJSON = opts.flag("json")
        let coordinator = RelayDispatch.makeCoordinator(runtime: runtime)
        let progressSink: RelayCoordinator.EventSink? = emitJSON ? { @Sendable event in
            print(RelayDispatch.progressJSONLine(event))
        } : nil
        let result = await coordinator.runExternalRound(
            relayId: loopId, submission: submission, projectId: projectId, events: progressSink
        )
        switch result {
        case .success(let payload):
            PilotCLI.emitHandoffResult(payload, json: emitJSON)
        case .failure(let error):
            PilotCLI.failPilotRound(error)
        }
    }

    private static func stepUsage() -> Never {
        FileHandle.standardError.write(Data(
            "usage: alln loop step <loop-id> <message>\n       alln loop step <loop-id> --done <summary>\n".utf8
        ))
        exit(2)
    }

    // MARK: - pm (was `pair relay adopt` + `pair pilot adopt` — collapsed, NOT symmetric)

    /// `alln loop pm <loop-id> <occupant>` (LVC v7 §2 "Both adopts collapse under one
    /// verb — but they are NOT symmetric"). Which transition applies is decided by
    /// the CURRENT chair, not the requested occupant — `RelayCoordinator.adopt`/
    /// `.adoptToPilot` already enforce each column's own precondition from the loaded
    /// state (chair == caller vs. chair == an agent), so this only routes to the
    /// matching entry point for the requested occupant; it never re-derives or
    /// loosens either column's eligibility:
    ///
    /// | `occupant` | was | requires current chair | eligible | effect |
    /// | --- | --- | --- | --- | --- |
    /// | an agent id | `relay adopt` | `caller` | `awaitingPM`\|`escalated` | dispatches a round |
    /// | `caller` | `pilot adopt` | an agent | `RelayState.isResumable` | static relabel, no dispatch |
    static func runPm(_ args: [String], runtime: ToolRuntime) async {
        let opts = Options(args)
        guard opts.positional.count >= 2,
              !opts.positional[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !opts.positional[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            FileHandle.standardError.write(Data(
                "usage: alln loop pm <loop-id> <caller|agent-id> [--max-rounds N] [--until HH:MM] [--no-wait] [--json]\n".utf8
            ))
            exit(2)
        }
        let loopId = opts.positional[0]
        let occupant = opts.positional[1]

        var forwarded: [String] = ["--relay", loopId]
        for key in opts.flags where key != "relay" {
            forwarded.append("--\(key)")
        }
        for (key, value) in opts.values where key != "relay" {
            forwarded.append("--\(key)")
            forwarded.append(value)
        }

        if occupant == "caller" {
            PilotCLI.runAdopt(forwarded)
        } else {
            forwarded.append(contentsOf: ["--pm-model", occupant])
            await RelayCLI.runAdopt(forwarded, runtime: runtime)
        }
    }
}
