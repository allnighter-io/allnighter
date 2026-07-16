import Foundation
import AllnighterCore
import AllnighterEngine

/// `alln panel start|round|status|watch|scaffold-brief|done` — top-level Panel
/// surface (`docs/phases/Pilot_Panel.md` decision 11 / PN-S04). Session-led blind
/// jury; NOT under `pair` (a jury is not a pair). Thin CLI over `PanelCoordinator`.
enum PanelCLI {
    struct StartRequest {
        var config: PanelCoordinator.Config
        var teamId: String?
        var rememberedTeam: Bool
        var laneDefault: Bool
        var seats: [PanelSeat]
    }

    static func run(_ args: [String], runtime: ToolRuntime) async {
        guard let sub = args.first else { usage() }
        switch sub {
        case "start": await runStart(Array(args.dropFirst()), runtime: runtime)
        case "round": await runRound(Array(args.dropFirst()), runtime: runtime)
        case "status": runStatus(Array(args.dropFirst()))
        case "watch": runWatch(Array(args.dropFirst()))
        case "scaffold-brief": runScaffoldBrief(Array(args.dropFirst()))
        case "done": runDone(Array(args.dropFirst()))
        default: usage()
        }
    }

    // MARK: - start

    static func runStart(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else {
            usage("panel start --doc <path> --project <id|path> [--team <alias>] [--seat <alias>:<lens> …] [--max-rounds N] [--json]")
        }
        let opts = Options(args)
        let request: StartRequest
        do {
            request = try parseStartConfig(
                args,
                models: runtime.models,
                registry: runtime.registry
            )
        } catch let error as PanelCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        let store = PanelStateStore()
        let coordinator = PanelCoordinator(
            stateStore: store,
            threadProjector: PanelThreadProjector(),
            workerRunner: WorkerInvokerFactory.makeWorkerInvoker(invocations: runtime.invocations),
            models: runtime.models,
            registry: runtime.registry
        )
        switch coordinator.start(
            config: request.config,
            models: runtime.models,
            registry: runtime.registry
        ) {
        case .success(let state):
            let scaffoldPath: String
            do {
                scaffoldPath = try PanelBriefScaffold.writeRoundFile(panelId: state.id, round: 1, stateStore: store)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not write brief scaffold: \(error)")
            }
            if let teamId = request.teamId {
                do {
                    try PanelTeamStore().save(projectId: request.config.projectId, teamId: teamId)
                } catch {
                    AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not remember panel team: \(error)")
                }
            }
            let resolvedTarget = PanelCoordinator.resolveTargetPath(
                state.targetPath, projectRoot: state.projectRoot
            )
            let targetHash = PanelState.contentHash(ofFileAt: resolvedTarget) ?? ""
            let advisory = dirtyTargetAdvisory(
                projectRoot: state.projectRoot,
                targetPath: state.targetPath
            )
            emitStartResult(
                state,
                targetHash: targetHash,
                dirtyAdvisory: advisory,
                scaffoldPath: scaffoldPath,
                rememberedTeam: request.rememberedTeam,
                laneDefault: request.laneDefault,
                json: opts.flag("json")
            )
        case .failure(.emptyRoster):
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "panel roster is empty — pass --team or --seat")
        case .failure(.seatNotIsolated(_, let message)):
            AllnighterCLI.fail(code: "PANEL_SEAT_NOT_ISOLATED", message: message)
        case .failure(.targetMissing(let path)):
            AllnighterCLI.fail(
                code: "PANEL_TARGET_MISSING",
                message: "target not found or unreadable: \(path) — pass an existing --doc path"
            )
        }
    }

    static func parseStartConfig(
        _ args: [String],
        projectStore: ProjectStore = ProjectStore(),
        models: [Model] = [],
        registry: DriverRegistry = DriverRegistry(),
        teams: [TeamPreset]? = nil,
        teamStore: PanelTeamStore = PanelTeamStore()
    ) throws -> StartRequest {
        let opts = Options(args)
        guard let docPath = opts.value("doc") else { throw PanelCLIError.missingRequired("--doc <path>") }
        guard let projectToken = opts.value("project") else { throw PanelCLIError.missingRequired("--project <id|path>") }
        guard let project = projectStore.resolveFresh(projectToken) else {
            throw PanelCLIError.projectNotFound(projectToken)
        }
        guard let maxRounds = parseMaxRounds(opts.value("max-rounds")) else {
            throw PanelCLIError.invalidMaxRounds(opts.value("max-rounds") ?? "")
        }

        let catalog = teams ?? TeamCatalog.all
        var baseSeats: [PanelSeat] = []
        var teamId: String?
        var remembered = false
        var laneDefault = false

        let seatFlags = multiSeatFlags(args)
        let hasExplicitSeats = !seatFlags.isEmpty

        if let teamAlias = opts.value("team") {
            switch PanelTeamResolver.resolveTeam(alias: teamAlias, teams: catalog) {
            case .success(let team):
                teamId = team.id
                baseSeats = PanelTeamResolver.seats(from: team)
            case .failure(.ambiguous(let alias, let candidates)):
                throw PanelCLIError.ambiguousTeam(
                    alias: alias,
                    candidates: PanelTeamResolver.formatCandidates(candidates)
                )
            case .failure(.noMatch(let alias, let available)):
                throw PanelCLIError.teamNotFound(
                    alias: alias,
                    available: PanelTeamResolver.formatAvailable(available)
                )
            case .failure(.noTeams):
                throw PanelCLIError.teamNotFound(alias: teamAlias, available: "(none)")
            }
        } else if hasExplicitSeats {
            // Power mode: seats only — no team base.
            baseSeats = []
        } else if let rememberedId = teamStore.load(projectId: project.id)?.teamId,
                  let team = catalog.first(where: { $0.id == rememberedId }) {
            teamId = team.id
            baseSeats = PanelTeamResolver.seats(from: team)
            remembered = true
        } else if let defaultTeam = catalog.defaultTeam(for: .code) {
            teamId = defaultTeam.id
            baseSeats = PanelTeamResolver.seats(from: defaultTeam)
            laneDefault = true
        } else {
            throw PanelCLIError.missingRoster(
                available: PanelTeamResolver.formatAvailable(catalog)
            )
        }

        // --seat entries override/extend (Options only keeps last --seat; collect all).
        var overrides: [PanelSeat] = []
        for raw in seatFlags {
            guard let seat = PanelTeamResolver.parseSeatFlag(raw) else {
                throw PanelCLIError.invalidSeat(raw)
            }
            overrides.append(seat)
        }
        let seats = PanelTeamResolver.applySeatOverrides(base: baseSeats, overrides: overrides)
        guard !seats.isEmpty else {
            throw PanelCLIError.missingRoster(
                available: PanelTeamResolver.formatAvailable(catalog)
            )
        }

        // v0 isolation enforcement at start — refuse any non-RO-enforcing seat.
        // workerId may be `model#rowId` after roster uniquing; check the model id.
        let catalogModels = models.isEmpty ? ModelCatalog.resolvedModels(registry: registry) : models
        for seat in seats {
            let modelId = PanelTeamResolver.modelId(for: seat.workerId)
            if let violation = PanelReadOnlyArgs.capabilityViolation(
                workerId: modelId, models: catalogModels, registry: registry
            ) {
                throw PanelCLIError.seatNotIsolated(workerId: seat.workerId, message: violation.message)
            }
        }

        let config = PanelCoordinator.Config(
            projectRoot: project.normalizedRootPath,
            projectId: project.id,
            targetPath: docPath,
            teamId: teamId,
            seats: seats,
            maxRounds: maxRounds
        )
        return StartRequest(
            config: config,
            teamId: teamId,
            rememberedTeam: remembered,
            laneDefault: laneDefault,
            seats: seats
        )
    }

    // MARK: - round

    static func runRound(_ args: [String], runtime: ToolRuntime) async {
        guard !args.isEmpty else {
            usage("panel round --panel <id> [--brief <md>|-] [--seats a,b] [--no-wait] [--json]")
        }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }

        let brief: String?
        do {
            brief = try parseBrief(opts)
        } catch let error as PanelCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        let seatFilter: [String]?
        if let raw = opts.value("seats") {
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            seatFilter = parts.isEmpty ? nil : parts
        } else {
            seatFilter = nil
        }

        if opts.flag("no-wait") {
            dispatchRoundInBackground(
                panelId: panelId, opts: opts, brief: brief, seatFilter: seatFilter, json: opts.flag("json")
            )
            return
        }

        let store = PanelStateStore()
        guard store.load(id: panelId) != nil else { fail(.panelNotFound(panelId)) }

        let coordinator = PanelCoordinator(
            stateStore: store,
            threadProjector: PanelThreadProjector(),
            workerRunner: WorkerInvokerFactory.makeWorkerInvoker(invocations: runtime.invocations),
            models: runtime.models,
            registry: runtime.registry
        )
        let result = await coordinator.runRound(
            panelId: panelId, brief: brief, seatFilter: seatFilter
        ) { event in
            emitProgress(event, json: opts.flag("json"))
        }
        switch result {
        case .success(let payload):
            emitRoundResult(payload, json: opts.flag("json"))
        case .failure(let error):
            failRound(error)
        }
    }

    static func parseBrief(_ opts: Options) throws -> String? {
        guard let raw = opts.value("brief") else { return nil }
        if raw == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PanelCLIError.noBrief
            }
            return text
        }
        guard let contents = try? String(contentsOf: URL(fileURLWithPath: raw), encoding: .utf8) else {
            throw PanelCLIError.fileUnreadable(raw)
        }
        return contents
    }

    // MARK: - status / watch / done / scaffold-brief

    enum InFlightRecovery: Equatable {
        case none
        case roundAlive
        case orphanReconciled
    }

    static func loadPanelState(
        panelId: String,
        stateStore: PanelStateStore,
        reconcileOrphans: Bool
    ) -> (state: PanelState, recovery: InFlightRecovery)? {
        guard var state = stateStore.load(id: panelId) else { return nil }
        guard state.status == .running else { return (state, .none) }
        if stateStore.isOwnerDead(id: panelId) {
            if reconcileOrphans {
                state = stateStore.reconcileIfOrphaned(state)
                // Orphan settle bypasses PanelCoordinator.persist — heal the projected
                // thread here so running seat placeholders do not stick (PN-S05).
                PanelThreadProjector().sync(state: state, now: Date())
            }
            return (state, .orphanReconciled)
        }
        return (state, .roundAlive)
    }

    static func runStatus(
        _ args: [String],
        stateStore: PanelStateStore = PanelStateStore()
    ) {
        guard !args.isEmpty else { usage("panel status --panel <id> [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }
        guard let loaded = loadPanelState(
            panelId: panelId, stateStore: stateStore, reconcileOrphans: true
        ) else { fail(.panelNotFound(panelId)) }
        emitStatusResult(loaded.state, recovery: loaded.recovery, json: opts.flag("json"))
    }

    static func runWatch(
        _ args: [String],
        stateStore: PanelStateStore = PanelStateStore(),
        pollInterval: TimeInterval = 1.0,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        guard !args.isEmpty else { usage("panel watch --panel <id> [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }

        guard var loaded = loadPanelState(
            panelId: panelId, stateStore: stateStore, reconcileOrphans: false
        ) else { fail(.panelNotFound(panelId)) }

        if loaded.state.status != .running {
            emitWatchResult(loaded.state, note: "nothing in flight", json: opts.flag("json"))
            return
        }

        // Dead owner → tell the user to re-run watch after reconcile (DX5).
        if stateStore.isOwnerDead(id: panelId) {
            loaded = loadPanelState(panelId: panelId, stateStore: stateStore, reconcileOrphans: true)
                ?? loaded
            emitWatchResult(
                loaded.state,
                note: "owner process died mid-round — reconciled; re-run `alln panel watch --panel \(panelId)` if needed",
                json: opts.flag("json")
            )
            return
        }

        while true {
            guard let current = loadPanelState(
                panelId: panelId, stateStore: stateStore, reconcileOrphans: true
            ) else { fail(.panelNotFound(panelId)) }
            if current.state.status != .running {
                emitWatchResult(current.state, note: nil, json: opts.flag("json"))
                return
            }
            if stateStore.isOwnerDead(id: panelId) {
                let reconciled = loadPanelState(
                    panelId: panelId, stateStore: stateStore, reconcileOrphans: true
                )
                emitWatchResult(
                    reconciled?.state ?? current.state,
                    note: "owner process died mid-round — reconciled; run `alln panel watch --panel \(panelId)`",
                    json: opts.flag("json")
                )
                return
            }
            sleep(pollInterval)
        }
    }

    static func runDone(
        _ args: [String],
        stateStore: PanelStateStore = PanelStateStore()
    ) {
        guard !args.isEmpty else { usage("panel done --panel <id> [--note …] [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }
        let coordinator = PanelCoordinator(
            stateStore: stateStore,
            threadProjector: PanelThreadProjector()
        )
        switch coordinator.done(panelId: panelId, note: opts.value("note")) {
        case .success(let state):
            emitDoneResult(state, json: opts.flag("json"))
        case .failure(.panelNotFound):
            fail(.panelNotFound(panelId))
        case .failure(.roundInFlight):
            AllnighterCLI.fail(
                code: "PANEL_ROUND_IN_FLIGHT",
                message: "a round is already dispatching — wait for it to settle, or poll with `panel status`/`panel watch`"
            )
        case .failure(.alreadyDone):
            AllnighterCLI.fail(code: "PANEL_NOT_AWAITING", message: "panel is already done")
        }
    }

    static func runScaffoldBrief(
        _ args: [String],
        stateStore: PanelStateStore = PanelStateStore()
    ) {
        guard !args.isEmpty else { usage("panel scaffold-brief --panel <id> [--round N] [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }
        let round = Int(opts.value("round") ?? "1") ?? 1
        guard round > 0 else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--round must be a positive integer")
        }
        guard stateStore.load(id: panelId) != nil else { fail(.panelNotFound(panelId)) }
        let template = PanelBriefScaffold.template(round: round)
        if opts.flag("json") {
            print(AllnighterCLI.jsonString([
                "panelId": panelId,
                "round": String(round),
                "template": template,
            ]))
        } else {
            print(template, terminator: "")
        }
    }

    // MARK: - emit

    private static func emitStartResult(
        _ state: PanelState,
        targetHash: String,
        dirtyAdvisory: String?,
        scaffoldPath: String,
        rememberedTeam: Bool,
        laneDefault: Bool,
        json: Bool
    ) {
        let panelJSON = PanelJSON.project(
            state, contractVersion: ContractRegistry.contractVersion, targetHash: targetHash
        )
        let next = "alln panel round --panel \(state.id)"
        if json {
            print(AllnighterCLI.jsonString(PanelStartJSON(
                contractVersion: ContractRegistry.contractVersion,
                panel: panelJSON,
                roster: state.seats.map(PanelSeatJSON.init),
                targetHash: targetHash,
                dirtyTargetAdvisory: dirtyAdvisory,
                scaffoldPath: scaffoldPath,
                nextCommand: next,
                teamId: state.teamId,
                rememberedTeam: rememberedTeam ? true : (laneDefault ? false : nil)
            )))
        } else {
            print("panel \(state.id)")
            print("status: \(state.status.rawValue)")
            if let teamId = state.teamId {
                let source: String
                if rememberedTeam { source = " (remembered)" }
                else if laneDefault { source = " (lane default)" }
                else { source = "" }
                print("team: \(teamId)\(source)")
            }
            print("roster:")
            for seat in state.seats {
                print("  - \(seat.workerId) lens=\(seat.lens)")
            }
            print("target: \(state.targetPath)")
            print("targetHash: \(targetHash)")
            if let dirtyAdvisory {
                print("advisory: \(dirtyAdvisory)")
            }
            print("scaffold: \(scaffoldPath)")
            print("next: \(next)")
        }
    }

    private static func emitProgress(_ event: PanelCoordinator.PanelEvent, json: Bool) {
        // NDJSON progress while blocking (even without --json, seats stream as they settle).
        let line: PanelProgressJSON
        switch event {
        case .seatStarted(let seat, let round, let attempt):
            line = PanelProgressJSON(event: "seatStarted", seat: seat, round: round, attempt: attempt)
        case .seatSettled(let seat, let round, let attempt, let status):
            line = PanelProgressJSON(event: "seatSettled", seat: seat, round: round, attempt: attempt, status: status)
        case .roundSettled(let round, let attempt):
            line = PanelProgressJSON(event: "roundSettled", round: round, attempt: attempt)
        }
        // Always NDJSON for progress (transport for early reading).
        if let data = try? CoreJSON.encode(line),
           let s = String(data: data, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
        _ = json
    }

    private static func emitRoundResult(
        _ payload: PanelCoordinator.RoundResult,
        json: Bool
    ) {
        let panelJSON = PanelJSON.project(payload.state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonString(PanelRoundJSON(
                contractVersion: ContractRegistry.contractVersion,
                panel: panelJSON,
                round: payload.round.roundNumber,
                attempt: payload.attempt.attemptNumber,
                targetHash: payload.round.targetHash,
                briefSource: payload.round.briefSource.rawValue,
                seatResults: payload.round.seatResults.map(SeatResultJSON.init)
            )))
        } else {
            print("panel \(payload.state.id) round \(payload.round.roundNumber) attempt \(payload.attempt.attemptNumber)")
            print("status: \(payload.state.status.rawValue)")
            print("targetHash: \(payload.round.targetHash)")
            for seat in payload.round.seatResults {
                print("\n----- seat \(seat.workerId) (\(seat.lens)) [\(seat.status.rawValue)] -----")
                if !seat.report.isEmpty {
                    print(seat.report)
                } else if let reason = seat.reason {
                    print(reason)
                }
            }
            print("\nnext: alln panel round --panel \(payload.state.id) --brief <focus.md>")
            print("  or: alln panel done --panel \(payload.state.id) --note \"…\"")
        }
    }

    private static func emitStatusResult(
        _ state: PanelState,
        recovery: InFlightRecovery,
        json: Bool
    ) {
        let panelJSON = PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        if json {
            var recoveryStr: String?
            var nextActions: [AgentSurfaceNextAction] = []
            switch recovery {
            case .none: break
            case .roundAlive:
                recoveryStr = "roundAlive"
                nextActions = [
                    AgentSurfaceNextAction(
                        kind: "wait",
                        label: "Watch panel round",
                        command: "alln panel watch --panel \(state.id)"
                    )
                ]
            case .orphanReconciled:
                recoveryStr = "orphanReconciled"
                nextActions = [
                    AgentSurfaceNextAction(
                        kind: "recover",
                        label: "Re-watch after orphan reconcile",
                        command: "alln panel watch --panel \(state.id)"
                    )
                ]
            }
            print(AllnighterCLI.jsonString(PanelStatusJSON(
                panel: panelJSON, recovery: recoveryStr, nextActions: nextActions
            )))
        } else {
            print("panel \(state.id)")
            print("status: \(state.status.rawValue)")
            print("target: \(state.targetPath)")
            print("rounds: \(state.rounds.count)/\(state.maxRounds)")
            if let last = state.rounds.last {
                print("last targetHash: \(last.targetHash)")
            }
            switch recovery {
            case .none: break
            case .roundAlive:
                print("recovery: round in flight — run `alln panel watch --panel \(state.id)`")
            case .orphanReconciled:
                print("recovery: owner died mid-round (reconciled) — run `alln panel watch --panel \(state.id)`")
            }
            if let note = state.note { print("note: \(note)") }
        }
    }

    private static func emitWatchResult(_ state: PanelState, note: String?, json: Bool) {
        let panelJSON = PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonString(PanelWatchJSON(panel: panelJSON, note: note)))
        } else {
            print("panel \(state.id)")
            print("status: \(state.status.rawValue)")
            if let last = state.rounds.last {
                for seat in last.seatResults {
                    print("\n----- seat \(seat.workerId) (\(seat.lens)) [\(seat.status.rawValue)] -----")
                    if !seat.report.isEmpty { print(seat.report) }
                }
            }
            if let note { print("\nnote: \(note)") }
        }
    }

    private static func emitDoneResult(_ state: PanelState, json: Bool) {
        let panelJSON = PanelJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        if json {
            print(AllnighterCLI.jsonString(panelJSON))
        } else {
            print("panel \(state.id) done")
            if let note = state.note { print("note: \(note)") }
            print("chain: alln pair pilot start --doc \(state.targetPath) --project \(state.projectId)")
        }
    }

    // MARK: - dirty advisory

    /// Advisory only — never refuses. Nudges the session to commit first so
    /// edit-in-place synthesis stays one revert away.
    static func dirtyTargetAdvisory(projectRoot: String, targetPath: String, git: GitObserver = GitObserver()) -> String? {
        let dirty = git.dirtyFiles(rootPath: projectRoot)
        let normalized = targetPath.hasPrefix("./") ? String(targetPath.dropFirst(2)) : targetPath
        let hits = dirty.filter { $0 == normalized || $0.hasSuffix("/" + normalized) || normalized.hasSuffix($0) }
        // Also treat untracked/dirty when the target path appears, or when the file is untracked.
        let targetHit = !hits.isEmpty || dirty.contains(where: { $0.contains((normalized as NSString).lastPathComponent) })
        guard targetHit else {
            // If the whole tree is dirty but target specifically isn't listed, still quiet.
            // Untracked target: git status shows "?? path".
            return nil
        }
        return "commit first so edit-in-place synthesis stays one revert away (target is dirty/untracked)"
    }

    // MARK: - background round

    private static func dispatchRoundInBackground(
        panelId: String,
        opts: Options,
        brief: String?,
        seatFilter: [String]?,
        json: Bool
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        var childArgs = ["panel", "round", "--panel", panelId]
        if let brief {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("alln-panel-brief-\(panelId)-\(UUID().uuidString).md")
            do {
                try brief.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not stage brief: \(error)")
            }
            childArgs += ["--brief", tempURL.path]
        }
        if let seatFilter {
            childArgs += ["--seats", seatFilter.joined(separator: ",")]
        }
        if json { childArgs.append("--json") }
        process.arguments = childArgs
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "could not dispatch background round: \(error)")
        }
        print("dispatched (pid \(process.processIdentifier)) — poll with `alln panel status --panel \(panelId) --json` or `alln panel watch --panel \(panelId)`")
    }

    // MARK: - helpers

    static func parseMaxRounds(_ raw: String?) -> Int? {
        guard let raw else { return 10 }
        guard let n = Int(raw), n > 0 else { return nil }
        return n
    }

    /// Collect every `--seat <value>` from argv (Options only keeps the last).
    static func multiSeatFlags(_ args: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "--seat", i + 1 < args.count {
                out.append(args[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        return out
    }

    // MARK: - errors

    enum PanelCLIError: Error, Equatable {
        case missingRequired(String)
        case projectNotFound(String)
        case panelNotFound(String)
        case invalidMaxRounds(String)
        case invalidSeat(String)
        case ambiguousTeam(alias: String, candidates: String)
        case teamNotFound(alias: String, available: String)
        case missingRoster(available: String)
        case seatNotIsolated(workerId: String, message: String)
        case fileUnreadable(String)
        case noBrief
    }

    static func errorEnvelope(_ error: PanelCLIError) -> (code: String, message: String) {
        switch error {
        case .missingRequired(let flag):
            return ("CLI_USAGE_ERROR", "missing required \(flag)")
        case .projectNotFound(let token):
            return ("PROJECT_NOT_FOUND", "project not found: \(token)")
        case .panelNotFound(let id):
            return ("PANEL_NOT_FOUND", "panel not found: \(id)")
        case .invalidMaxRounds(let raw):
            return ("CLI_USAGE_ERROR", "--max-rounds must be a positive integer (got \(raw.isEmpty ? "empty" : raw))")
        case .invalidSeat(let raw):
            return ("CLI_USAGE_ERROR", "invalid --seat '\(raw)' — expected <alias>:<lens>")
        case .ambiguousTeam(let alias, let candidates):
            return ("CLI_USAGE_ERROR", "ambiguous --team '\(alias)' — candidates: \(candidates)")
        case .teamNotFound(let alias, let available):
            return ("TEAM_NOT_FOUND", "no team matches '\(alias)' — available: \(available)")
        case .missingRoster(let available):
            return ("CLI_USAGE_ERROR", "pass --team <alias> or --seat <alias>:<lens> — available teams: \(available)")
        case .seatNotIsolated(_, let message):
            return ("PANEL_SEAT_NOT_ISOLATED", message)
        case .fileUnreadable(let path):
            return ("CLI_USAGE_ERROR", "could not read file: \(path)")
        case .noBrief:
            return ("CLI_USAGE_ERROR", "--brief - produced empty stdin")
        }
    }

    static func roundErrorEnvelope(_ error: PanelCoordinator.RoundError) -> (code: String, message: String) {
        switch error {
        case .panelNotFound:
            return ("PANEL_NOT_FOUND", "panel not found")
        case .roundInFlight:
            return ("PANEL_ROUND_IN_FLIGHT", "a round is already dispatching — wait for it to settle, or poll with `panel status`/`panel watch`")
        case .notAwaitingPM(let status):
            return ("PANEL_NOT_AWAITING", "panel is \(status), not awaitingPM — nothing to dispatch")
        case .targetMissing(let path):
            return ("PANEL_TARGET_MISSING", "target not found or unreadable: \(path)")
        case .briefRequired:
            return ("CLI_USAGE_ERROR", "round 2+ requires --brief <md>|- (focus brief required — include a rejection-carry line)")
        case .maxRoundsReached(let max):
            return ("PANEL_NOT_AWAITING", "reached --max-rounds (\(max)) — declare done or raise the ceiling on a new panel")
        case .unknownSeats(let ids):
            return ("CLI_USAGE_ERROR", "unknown seats in --seats: \(ids.joined(separator: ", "))")
        case .emptySeatFilter:
            return ("CLI_USAGE_ERROR", "--seats must name at least one seat")
        }
    }

    private static func fail(_ error: PanelCLIError) -> Never {
        let (code, message) = errorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func failRound(_ error: PanelCoordinator.RoundError) -> Never {
        let (code, message) = roundErrorEnvelope(error)
        AllnighterCLI.fail(code: code, message: message)
    }

    private static func usage(_ detail: String = "panel start|round|status|watch|scaffold-brief|done") -> Never {
        FileHandle.standardError.write(Data("usage: alln \(detail)\n".utf8))
        exit(2)
    }
}

struct PanelStatusJSON: Encodable {
    let panel: PanelJSON
    let recovery: String?
    let nextActions: [AgentSurfaceNextAction]
}

struct PanelWatchJSON: Encodable {
    let panel: PanelJSON
    let note: String?
}
