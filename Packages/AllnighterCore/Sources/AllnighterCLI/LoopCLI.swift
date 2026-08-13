import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln loop` — the durable PM↔dev loop object (LVC v7 `docs/phases/Loop_Verb_Cutover.md`
/// §2). LVC-S02a/S02b/S02c wired `start|list|status|stop|resume|wait`; this slice
/// (LVC-S02d) adds the last two verbs, `step` and `pm`. `loop start` builds
/// `LoopCoordinator.Config`/
/// `PilotCLI.StartRequest` directly and dispatches into the existing `PilotCLI`/`LoopEngineCLI`
/// coordinator entry points — `docPath` is `nil` when `--spec` is omitted (LVC-S02b: a brief
/// with no doc still starts a real loop); `pair pilot start`/`pair relay` themselves keep
/// hard-requiring `--doc`, unchanged. `status|stop|resume|wait` are chair-neutral: the
/// underlying `LoopState` is one substrate for both `--pm caller` and spawned-PM loops
/// (`LoopJSON.project`/`LoopEngineCLI.runStatus` carry no pmMode branching), so a single
/// positional `<loop-id>` forwards straight into the existing `--relay <id>` entry points —
/// no chair lookup needed before dispatch.
enum LoopCLI {
    /// Subcommands `run` dispatches. Single source for the unknown-subcommand
    /// message and the contract gate that every live verb is declared in
    /// `ContractRegistry` — add here and in the switch together.
    static let implementedSubcommands: [String] = [
        "start", "list", "status", "stop", "resume", "wait", "step", "pm",
    ]

    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        let rest = Array(args.dropFirst())
        switch sub {
        case "start": await runStart(rest, runtime: runtime)
        case "list": runList(rest)
        case "status":
            LoopEngineCLI.runStatus(loopArgs(rest, usageLine: "loop status <loop-id> [--wait-for parked|terminal --timeout <seconds>] [--json]"))
        case "stop":
            LoopEngineCLI.runStop(loopArgs(rest, usageLine: "loop stop <loop-id> [--json]"), runtime: runtime)
        case "resume":
            await EntitlementAdmission.skippingInner {
                await LoopEngineCLI.runResume(loopArgs(rest, usageLine: "loop resume <loop-id> --answer <text> [--until HH:MM] [--max-rounds N] [--no-wait] [--json]"), runtime: runtime)
            }
        case "wait":
            PilotCLI.runWatch(loopArgs(rest, usageLine: "loop wait <loop-id> [--max-wait <seconds>] [--json]"))
        case "step":
            await EntitlementAdmission.skippingInner {
                await runStep(rest, runtime: runtime)
            }
        case "pm":
            await runPm(rest, runtime: runtime)
        default:
            let known = implementedSubcommands.joined(separator: "|")
            FileHandle.standardError.write(Data(
                "loop \(sub): not recognized — \(known).\n".utf8
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
        loopStateStore: LoopStateStore = LoopStateStore()
    ) {
        let opts = Options(args)
        let project = resolveProject(opts: opts, store: projectStore)

        let legacyNotice = legacyLoopsPathNotice(loopsRoot: loopStateStore.rootDirectory)

        let entries = loopStateStore.list()
            .filter { $0.projectRoot == project.normalizedRootPath }
            .map { state -> LoopListJSON.Entry in
                LoopListJSON.Entry(
                    id: state.id,
                    status: state.status.rawValue,
                    briefOrSpec: state.docPathOrBrief,
                    pm: state.isCallerChair ? "caller" : state.pmModelId,
                    dev: state.devModelId,
                    updatedAt: state.finishedAt ?? state.rounds.last?.startedAt ?? state.createdAt
                )
            }

        let payload = LoopListJSON(
            projectId: project.id,
            projectRoot: project.normalizedRootPath,
            loops: entries,
            legacyStatePathNotice: legacyNotice
        )
        if opts.flag("json") {
            print(AllnighterCLI.jsonString(payload))
        } else if let legacyNotice {
            FileHandle.standardError.write(Data(legacyNotice.utf8))
            FileHandle.standardError.write(Data("\n".utf8))
            if entries.isEmpty {
                print("no loops listed for \(project.normalizedRootPath) (see notice above)")
            } else {
                for entry in entries {
                    print("\(entry.id)  \(entry.status)  pm=\(entry.pm) dev=\(entry.dev)  \(entry.briefOrSpec)")
                }
            }
        } else if entries.isEmpty {
            print("no loops for \(project.normalizedRootPath)")
        } else {
            for entry in entries {
                print("\(entry.id)  \(entry.status)  pm=\(entry.pm) dev=\(entry.dev)  \(entry.briefOrSpec)")
            }
        }
    }

    /// When `Loops/` does not exist but legacy `Relays/` still has state, fail loud —
    /// never imply no loops ever existed.
    private static func legacyLoopsPathNotice(loopsRoot: URL) -> String? {
        let fm = FileManager.default
        let legacy = AllnighterPaths.legacyRelaysDirectory
        guard !fm.fileExists(atPath: loopsRoot.path),
              fm.fileExists(atPath: legacy.path) else {
            return nil
        }
        return "loop state moved from \(legacy.path) to \(loopsRoot.path) in LVC-S09 — existing loops are not migrated; finish or stop in-flight loops under Relays/ before upgrading, or move state manually"
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
        var localExecutionWarning: String?
        /// Warn-and-allow when `--pm` is a local Ollama seat. Never blocks.
        var localLeadDisclosure: String?
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

        if let disclosure = seats.localLeadDisclosure {
            discloseOnce(disclosure)
        }

        // LVC-S02b: `--spec` is a shortcut, not the shape (LVC v7 §2) — a brief with no
        // doc dispatches a real loop. `Config`/`StartRequest` are built here directly
        // (not via `LoopEngineCLI.parseStartConfig`/`PilotCLI.parseStartConfig`, which keep
        // hard-requiring `--doc` for the retired `pair relay`/`pilot start` verbs) so
        // `docPath` can be `nil` while `brief` always carries the work.
        guard let maxRounds = LoopEngineCLI.parseMaxRounds(opts.value("max-rounds")) else {
            AllnighterCLI.fail(
                code: "CLI_USAGE_ERROR",
                message: "--max-rounds must be a positive integer, got \"\(opts.value("max-rounds") ?? "")\""
            )
        }
        let untilParsed = LoopDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--until could not be parsed: \"\(bad)\"")
        }
        let idleParsed = RunCLI.parseIdleTimeoutSeconds(opts.value("idle-timeout"))
        if let error = idleParsed.error {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: error)
        }

        switch await EntitlementGate.standard.admitDispatch() {
        case .admit:
            break
        case .refuse(let refusal):
            AllnighterCLI.fail(
                code: "ENTITLEMENT_LIMIT",
                message: refusal.message,
                nextAction: EntitlementLimitNextAction.agent
            )
        }

        switch seats.pm {
        case .caller:
            // Pilot has no clock and no PM prompt of its own — the live session IS the
            // PM and already holds the brief in its own context, so nothing needs it
            // injected. `--until` is refused by `startPilot` itself (untilNotSupported).
            let config = LoopCoordinator.Config(
                projectRoot: project.normalizedRootPath,
                projectId: project.id,
                docPath: specPath,
                brief: brief,
                pmModelId: LoopState.callerPMModelId,
                devModelId: seats.dev,
                maxRounds: maxRounds,
                until: untilParsed.value,
                devTurnIdleTimeoutSeconds: idleParsed.value
            )
            let request = PilotCLI.StartRequest(
                config: config, devModelId: seats.dev, devWorkerAlias: nil, rememberedDevWorker: false
            )
            await EntitlementAdmission.skippingInner {
                await PilotCLI.runStart(request: request, opts: opts, runtime: runtime)
            }
        case .agent(let pmId):
            let kickoffMessage: String?
            do {
                kickoffMessage = try LoopEngineCLI.parseKickoffMessage(opts) ?? brief
            } catch let error as LoopEngineCLI.LoopEngineCLIError {
                LoopEngineCLI.fail(error)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
            }
            let config = LoopCoordinator.Config(
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
            await EntitlementAdmission.skippingInner {
                await LoopEngineCLI.runRelay(config: config, opts: opts, runtime: runtime)
            }
        }
    }

    /// `--pm` omitted → Frontier tier default. `--pm caller` → the reserved occupant,
    /// never resolved as a model id. `--pm <id>` → honor-or-fail exact-id resolution,
    /// same choke point `pair relay --pm-model` uses (`LoopEngineCLI.swift:402-405`).
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

        var localLeadDisclosure: String?
        if case .agent(let id) = pm,
           let model = models.first(where: { $0.id == id }) {
            let snapshot = OllamaLocalDoctorReport.snapshotIfAllowed(
                transport: nil,
                observedAt: Date(),
                isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
            )
            localLeadDisclosure = LoopLocalSeatPolicy.localLeadDisclosure(
                for: model,
                servedContextWindow: LoopLocalSeatPolicy.servedContextWindow(
                    for: model,
                    snapshot: snapshot
                )
            )
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

        var localExecutionWarning: String?
        if let model = models.first(where: { $0.id == dev }) {
            localExecutionWarning = LoopLocalSeatPolicy.localExecutionWarning(for: model)
        }

        return ResolvedSeats(
            pm: pm, pmSource: pmSource, dev: dev, devSource: devSource,
            localExecutionWarning: localExecutionWarning,
            localLeadDisclosure: localLeadDisclosure
        )
    }

    /// One-shot stderr disclosure. Dry-run JSON carries the same text in
    /// `warnings` and does not also print here.
    private static func discloseOnce(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    private static func emitDryRun(
        brief: String, specPath: String?, pmRaw: String?, devRaw: String?, project: Project, seats: ResolvedSeats
    ) {
        var warnings: [String] = []
        var ready = true
        if let specPath, !FileManager.default.fileExists(atPath: URL(fileURLWithPath: specPath, relativeTo: URL(fileURLWithPath: project.normalizedRootPath)).path) {
            warnings.append("--spec \(specPath) does not exist under \(project.normalizedRootPath) yet — the PM will hit this on round 1")
            ready = false
        }
        if let localWarning = seats.localExecutionWarning {
            warnings.append(localWarning)
            ready = false
        }
        if let leadDisclosure = seats.localLeadDisclosure {
            warnings.append(leadDisclosure)
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
            ready: ready,
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
    /// holds the chair. `awaitingPM` is documented Pilot-only (`LoopState.swift:195-202`)
    /// — an agent-occupied loop dispatches its own decision inside `LoopCoordinator`
    /// and so is never observably `awaitingPM`; that is what makes this chair-neutral
    /// without ever consulting the occupant. Do NOT add a `pmMode`/occupant check here —
    /// that was v5's Law 3 violation (corrected in v6/v7).
    static func runStep(
        _ args: [String], runtime: ToolRuntime,
        stateStore: LoopStateStore = LoopStateStore(),
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

        // LOOP-TWIN: free twin — no coordinator, no durable writes.
        if opts.flag("dry-run") {
            let payload = await dryRunStep(
                loopId: loopId,
                message: message,
                doneSummary: doneSummary,
                stateStore: stateStore,
                projectStore: projectStore
            )
            print(AllnighterCLI.jsonString(payload))
            return
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
        let coordinator = LoopDispatch.makeCoordinator(runtime: runtime)
        let progressSink: LoopCoordinator.EventSink? = emitJSON ? { @Sendable event in
            print(LoopDispatch.progressJSONLine(event))
        } : nil
        let result = await coordinator.runExternalRound(
            loopId: loopId, submission: submission, projectId: projectId, events: progressSink
        )
        switch result {
        case .success(let payload):
            PilotCLI.emitHandoffResult(payload, json: emitJSON)
        case .failure(let error):
            PilotCLI.failPilotRound(error)
        }
    }

    /// LOOP-TWIN: pure resolve for `loop step --dry-run`. Load-only; never
    /// `runExternalRound`, never appends a round, never starts a worker.
    static func dryRunStep(
        loopId: String,
        message: String?,
        doneSummary: String?,
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async -> LoopStartDryRunJSON {
        var warnings: [String] = []
        let payloadBrief: String
        if let doneSummary {
            payloadBrief = doneSummary
        } else if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payloadBrief = message
        } else {
            payloadBrief = ""
            warnings.append("loop step takes a message or --done <summary>")
        }

        // Resolve the submission shape the real path would use (pure; no dispatch).
        if payloadBrief.isEmpty == false {
            do {
                if doneSummary != nil {
                    _ = try PilotCLI.synthesizeSubmission(verdict: .done, handover: nil, note: doneSummary)
                } else if let message {
                    _ = try PilotCLI.synthesizeSubmission(verdict: .continueRelay, handover: message, note: nil)
                }
            } catch {
                warnings.append("could not synthesize step payload: \(error)")
            }
        }

        var projectId = ""
        var projectRoot = ""
        var specPath: String?
        var pmOccupant = "?"
        var devOccupant = "?"
        var ready = warnings.isEmpty

        switch stateStore.loadResult(id: loopId) {
        case .failure(.notFound):
            warnings.append("loop not found: \(loopId)")
            ready = false
        case .failure(.decodeFailed(let detail)):
            warnings.append(detail.agentMessage)
            ready = false
        case .success(let state):
            projectRoot = state.projectRoot
            projectId = projectStore.resolveFresh(state.projectRoot)?.id ?? ""
            specPath = state.docPath
            let seats = LoopDryRunSupport.seatOccupant(from: state)
            pmOccupant = seats.pm
            devOccupant = seats.dev
            if state.status != .awaitingPM {
                warnings.append(
                    "loop is not awaiting a PM decision (status: \(state.status.rawValue))"
                )
                ready = false
            }
            if doneSummary == nil, message != nil {
                // continue path would dispatch a dev turn — surface write-lock.
                if let lockWarning = await LoopDryRunSupport.writeLockWarning(projectRoot: state.projectRoot) {
                    warnings.append(lockWarning)
                }
            }
        }

        if payloadBrief.isEmpty { ready = false }

        return LoopStartDryRunJSON(
            brief: payloadBrief,
            specPath: specPath,
            projectId: projectId,
            projectRoot: projectRoot,
            pm: .init(occupant: pmOccupant, source: "loop"),
            dev: .init(occupant: devOccupant, source: "loop"),
            ready: ready,
            warnings: warnings,
            nextAction: AgentNextAction(
                kind: "startTeamRun",
                label: doneSummary != nil ? "Close the loop for real" : "Step the loop for real",
                command: LoopDryRunSupport.stepCommand(
                    loopId: loopId, message: message, doneSummary: doneSummary
                )
            )
        )
    }

    private static func stepUsage() -> Never {
        FileHandle.standardError.write(Data(
            "usage: alln loop step <loop-id> <message> [--dry-run] [--json]\n       alln loop step <loop-id> --done <summary> [--dry-run] [--json]\n".utf8
        ))
        exit(2)
    }

    // MARK: - pm (was `pair relay adopt` + `pair pilot adopt` — collapsed, NOT symmetric)

    /// `alln loop pm <loop-id> <occupant>` (LVC v7 §2 "Both adopts collapse under one
    /// verb — but they are NOT symmetric"). Which transition applies is decided by
    /// the CURRENT chair, not the requested occupant — `LoopCoordinator.adopt`/
    /// `.adoptToPilot` already enforce each column's own precondition from the loaded
    /// state (chair == caller vs. chair == an agent), so this only routes to the
    /// matching entry point for the requested occupant; it never re-derives or
    /// loosens either column's eligibility:
    ///
    /// | `occupant` | was | requires current chair | eligible | effect |
    /// | --- | --- | --- | --- | --- |
    /// | an agent id | `relay adopt` | `caller` | `awaitingPM`\|`escalated` | dispatches a round |
    /// | `caller` | `pilot adopt` | an agent | `LoopState.isResumable` | static relabel, no dispatch |
    static func runPm(
        _ args: [String],
        runtime: ToolRuntime,
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async {
        let opts = Options(args)
        guard opts.positional.count >= 2,
              !opts.positional[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !opts.positional[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            FileHandle.standardError.write(Data(
                "usage: alln loop pm <loop-id> <caller|agent-id> [--max-rounds N] [--until HH:MM] [--dry-run] [--no-wait] [--json]\n".utf8
            ))
            exit(2)
        }
        let loopId = opts.positional[0]
        let occupant = opts.positional[1]

        // LOOP-TWIN: free twin — no adopt, no durable writes.
        if opts.flag("dry-run") {
            let payload = await dryRunPm(
                loopId: loopId,
                occupant: occupant,
                opts: opts,
                models: runtime.models,
                stateStore: stateStore,
                projectStore: projectStore
            )
            print(AllnighterCLI.jsonString(payload))
            return
        }

        var forwarded: [String] = ["--relay", loopId]
        for key in opts.flags where key != "relay" {
            forwarded.append("--\(key)")
        }
        for (key, value) in opts.values where key != "relay" {
            forwarded.append("--\(key)")
            forwarded.append(value)
        }

        if occupant == "caller" {
            PilotCLI.runAdopt(forwarded, stateStore: stateStore)
        } else {
            switch ExactIdResolver.resolveWorker(occupant, flag: "--pm", models: runtime.models) {
            case .success(let model):
                let snapshot = OllamaLocalDoctorReport.snapshotIfAllowed(
                    transport: nil,
                    observedAt: Date(),
                    isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
                )
                if let disclosure = LoopLocalSeatPolicy.localLeadDisclosure(
                    for: model,
                    servedContextWindow: LoopLocalSeatPolicy.servedContextWindow(
                        for: model,
                        snapshot: snapshot
                    )
                ) {
                    discloseOnce(disclosure)
                }
            case .failure(let failure):
                AllnighterCLI.failExactId(failure)
            }
            forwarded.append(contentsOf: ["--pm-model", occupant])
            await LoopEngineCLI.runAdopt(forwarded, runtime: runtime, stateStore: stateStore, projectStore: projectStore)
        }
    }

    /// LOOP-TWIN: pure resolve for `loop pm --dry-run`. Load-only — never
    /// `adopt` / `adoptToPilot` (those flip occupant / dispatch). Does not call
    /// `reconcileOrphan` either (that can write when owner is dead).
    static func dryRunPm(
        loopId: String,
        occupant: String,
        opts: Options,
        models: [Model],
        stateStore: LoopStateStore = LoopStateStore(),
        projectStore: ProjectStore = ProjectStore()
    ) async -> LoopStartDryRunJSON {
        var warnings: [String] = []
        let brief = "pm → \(occupant)"

        // Resolve agent id when not handing to caller (same choke point as real adopt).
        var resolvedPmOccupant = occupant
        var pmSource = "requested"
        if occupant != "caller" {
            switch ExactIdResolver.resolveWorker(occupant, flag: "occupant", models: models) {
            case .success(let model):
                resolvedPmOccupant = model.id
                pmSource = "explicit"
                let snapshot = OllamaLocalDoctorReport.snapshotIfAllowed(
                    transport: nil,
                    observedAt: Date(),
                    isTestHost: AllnighterSupportRoot.isRunningUnderTestHost
                )
                if let disclosure = LoopLocalSeatPolicy.localLeadDisclosure(
                    for: model,
                    servedContextWindow: LoopLocalSeatPolicy.servedContextWindow(
                        for: model,
                        snapshot: snapshot
                    )
                ) {
                    warnings.append(disclosure)
                }
            case .failure(let failure):
                warnings.append(failure.message)
            }
        } else {
            pmSource = "caller"
        }

        if opts.value("max-rounds") != nil, LoopEngineCLI.parseMaxRounds(opts.value("max-rounds")) == nil {
            warnings.append("--max-rounds must be a positive integer, got \"\(opts.value("max-rounds") ?? "")\"")
        }
        let untilParsed = LoopDispatch.parseUntilValidated(opts.value("until"))
        if let bad = untilParsed.invalid {
            warnings.append("--until could not be parsed: \"\(bad)\"")
        }

        var projectId = ""
        var projectRoot = ""
        var specPath: String?
        var currentPm = "?"
        var devOccupant = "?"
        // Lead disclosure is warn-and-allow — it sits in `warnings` but does not
        // flip ready. Blocking issues below still do.
        var ready = true

        switch stateStore.loadResult(id: loopId) {
        case .failure(.notFound):
            warnings.append("loop not found: \(loopId)")
            ready = false
        case .failure(.decodeFailed(let detail)):
            warnings.append(detail.agentMessage)
            ready = false
        case .success(let state):
            projectRoot = state.projectRoot
            projectId = projectStore.resolveFresh(state.projectRoot)?.id ?? ""
            specPath = state.docPath
            let seats = LoopDryRunSupport.seatOccupant(from: state)
            currentPm = seats.pm
            devOccupant = seats.dev

            if occupant == "caller" {
                // Real path: adoptToPilot — parked spawned loop only (isResumable).
                // No reconcileOrphan here (that mutates dead-owner running).
                if state.isCallerChair {
                    warnings.append("loop already has caller as PM — nothing to hand over")
                    ready = false
                } else if !state.isResumable {
                    warnings.append(
                        "loop is not adoptable to caller (status: \(state.status.rawValue)) — requires escalated or orphan-reconciled stopped"
                    )
                    ready = false
                }
                // caller path: status flip only, no worker dispatch / no write lock spend.
            } else {
                // Real path: adopt — caller-chair awaitingPM|escalated → agent PM + dispatch.
                if !state.isCallerChair {
                    warnings.append(
                        "loop PM is already an agent (\(currentPm)) — agent-PM adopt requires a caller-held loop"
                    )
                    ready = false
                } else if state.status != .awaitingPM && state.status != .escalated {
                    warnings.append(
                        "loop is not adoptable to an agent PM (status: \(state.status.rawValue)) — requires awaitingPM or escalated"
                    )
                    ready = false
                } else if let lockWarning = await LoopDryRunSupport.writeLockWarning(projectRoot: state.projectRoot) {
                    warnings.append(lockWarning)
                }
            }
        }

        if opts.value("max-rounds") != nil && LoopEngineCLI.parseMaxRounds(opts.value("max-rounds")) == nil {
            ready = false
        }
        if untilParsed.invalid != nil { ready = false }
        // Unresolved agent id keeps ready false.
        if occupant != "caller", pmSource != "explicit" { ready = false }

        let reportPm = occupant == "caller" ? "caller" : resolvedPmOccupant
        return LoopStartDryRunJSON(
            brief: brief,
            specPath: specPath,
            projectId: projectId,
            projectRoot: projectRoot,
            pm: .init(occupant: reportPm, source: pmSource),
            dev: .init(occupant: devOccupant, source: "loop"),
            ready: ready,
            warnings: warnings,
            nextAction: AgentNextAction(
                kind: "startTeamRun",
                label: occupant == "caller"
                    ? "Hand PM seat to caller for real"
                    : "Hand PM seat to agent and continue for real",
                command: LoopDryRunSupport.pmCommand(
                    loopId: loopId,
                    occupant: occupant,
                    maxRounds: opts.value("max-rounds"),
                    until: opts.value("until")
                )
            )
        )
    }
}
