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
        case "status": await runStatus(Array(args.dropFirst()))
        case "watch": await runWatch(Array(args.dropFirst()))
        case "scaffold-brief": runScaffoldBrief(Array(args.dropFirst()))
        case "done": await runDone(Array(args.dropFirst()))
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
                registry: runtime.registry,
                probeRecords: SetupStore().load().records
            )
        } catch let error as PanelCLIError {
            fail(error)
        } catch {
            AllnighterCLI.fail(code: "INTERNAL_ERROR", message: "\(error)")
        }

        let receipt = await residentPanelRequest(.panelStart(.init(
            projectRoot: request.config.projectRoot,
            projectId: request.config.projectId,
            targetPath: request.config.targetPath,
            teamId: request.teamId,
            seats: request.seats,
            maxRounds: request.config.maxRounds,
            rememberedTeam: request.rememberedTeam,
            laneDefault: request.laneDefault
        )))
        guard case let .panelStart(payload) = receipt.result else {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator returned an invalid panel start response")
        }
        emitStartPayload(payload, json: opts.flag("json"))
    }

    static func parseStartConfig(
        _ args: [String],
        projectStore: ProjectStore = ProjectStore(),
        models: [Model] = [],
        registry: DriverRegistry = DriverRegistry(),
        teams: [TeamPreset]? = nil,
        teamStore: PanelTeamStore = PanelTeamStore(),
        probeRecords: [ToolProbeRecord] = []
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
        let registryForValidation = registry.all.isEmpty ? DefaultConfig.registry : registry
        let catalogModels = models.isEmpty
            ? ModelCatalog.resolvedModels(registry: registryForValidation)
            : models
        // A caller's cached readiness is not execution truth. The resident
        // coordinator owns spawn-time readiness and will preserve this selected
        // roster (or report its per-seat failure) without self-fusing it.
        let dispatchableModels = catalogModels
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
                baseSeats = PanelTeamResolver.seats(from: team, readyModels: dispatchableModels)
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
            case .failure(.exactId(let failure)):
                throw PanelCLIError.teamNotFound(
                    alias: failure.provided,
                    available: PanelTeamResolver.formatAvailable(catalog)
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
            baseSeats = PanelTeamResolver.seats(from: team, readyModels: dispatchableModels)
            remembered = true
        } else if let defaultTeam = catalog.defaultTeam(for: .code) {
            teamId = defaultTeam.id
            baseSeats = PanelTeamResolver.seats(from: defaultTeam, readyModels: dispatchableModels)
            laneDefault = true
        } else {
            throw PanelCLIError.missingRoster(
                available: PanelTeamResolver.formatAvailable(catalog)
            )
        }

        // --seat entries override/extend (Options only keeps last --seat; collect all).
        // Resolve each alias through PilotSeatResolver AT START — never store the raw
        // alias string as workerId in PanelState (decision 4 / works-test fix).
        let readyForErrors = dispatchableModels.filter(\.enabled)
        var overrides: [PanelSeat] = []
        for raw in seatFlags {
            guard let resolved = PanelTeamResolver.resolveSeatFlag(raw, models: dispatchableModels) else {
                throw PanelCLIError.invalidSeat(raw)
            }
            switch resolved {
            case .success(let seat):
                overrides.append(seat)
            case .failure(.ambiguous(let alias, let candidates)):
                throw PanelCLIError.ambiguousSeat(
                    alias: alias,
                    candidates: PilotSeatResolver.formatCandidates(candidates)
                )
            case .failure(.noMatch(let alias, _)):
                throw PanelCLIError.seatNotFound(
                    alias: alias,
                    readySeats: PilotSeatResolver.formatReadySeats(readyForErrors)
                )
            case .failure(.exactId(let failure)):
                throw PanelCLIError.seatNotFound(
                    alias: failure.provided,
                    readySeats: PilotSeatResolver.formatReadySeats(readyForErrors)
                )
            case .failure(.noReadySeats):
                throw PanelCLIError.seatNotFound(
                    alias: aliasFromSeatFlag(raw) ?? raw,
                    readySeats: PilotSeatResolver.formatReadySeats(readyForErrors)
                )
            }
        }
        let seats = PanelTeamResolver.applySeatOverrides(base: baseSeats, overrides: overrides)
        guard !seats.isEmpty else {
            throw PanelCLIError.missingRoster(
                available: PanelTeamResolver.formatAvailable(catalog)
            )
        }

        // End-to-end roster preflight: model exists + driver manifest present so
        // isolation mode is determinable. Fail at start (exit 2), never mid-round.
        switch PanelTeamResolver.validateRoster(
            seats: seats, models: catalogModels, registry: registryForValidation
        ) {
        case .success:
            break
        case .failure(.unknownModel(let workerId, let modelId)):
            throw PanelCLIError.unknownSeatModel(workerId: workerId, modelId: modelId)
        case .failure(.noDriver(let workerId, let modelId, let driverId)):
            throw PanelCLIError.seatNoDriver(workerId: workerId, modelId: modelId, driverId: driverId)
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

        let receipt = await residentPanelRequest(.panelRound(.init(
            panelId: panelId, brief: brief, seatFilter: seatFilter
        )))
        if case let .panelRound(payload) = receipt.result {
            emitRoundPayload(payload, json: opts.flag("json"))
            return
        }
        guard case .panelStatus = receipt.result else {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator returned an invalid panel round response")
        }
        if opts.flag("no-wait") {
            print("dispatched — poll with `alln panel status --panel \(panelId) --json`")
            return
        }
        while true {
            let statusReceipt = await residentPanelQuery(.panelStatus, panelId: panelId)
            guard case let .panelStatus(panel) = statusReceipt.result else {
                AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator returned an invalid panel status response")
            }
            if panel.status != "running" { break }
            try? await Task.sleep(for: .seconds(1))
        }
        let resultReceipt = await residentPanelQuery(.panelResult, panelId: panelId)
        guard case let .panelRound(payload) = resultReceipt.result else {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator did not return a settled panel round")
        }
        emitRoundPayload(payload, json: opts.flag("json"))
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

    private static func residentPanelRequest(
        _ operation: ResidentExecutionOperation
    ) async -> ResidentExecutionReceipt {
        let rendezvous = ResidentExecutionRendezvous()
        do {
            let submitted = try rendezvous.submit(
                operation: operation,
                idempotencyKey: UUID().uuidString.lowercased()
            )
            guard let receipt = try await rendezvous.waitForReceipt(requestId: submitted.requestId) else {
                AllnighterCLI.fail(code: "RESIDENT_ACCEPT_TIMEOUT", message: "resident coordinator did not answer the panel request before timeout")
            }
            if let rejection = receipt.rejection {
                AllnighterCLI.fail(code: rejection.code, message: rejection.message)
            }
            return receipt
        } catch ResidentExecutionRendezvous.Error.unavailable {
            AllnighterCLI.fail(code: "COORDINATOR_UNAVAILABLE", message: "resident coordinator is unavailable; enable it with `alln serve install`")
        } catch {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident panel request failed: \(error)")
        }
    }

    private static func residentPanelQuery(
        _ kind: ResidentExecutionOperation.Query.Kind,
        panelId: String
    ) async -> ResidentExecutionReceipt {
        await residentPanelRequest(.query(.init(kind: kind, canonicalId: panelId)))
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

    static func runStatus(_ args: [String]) async {
        guard !args.isEmpty else { usage("panel status --panel <id> [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }
        let receipt = await residentPanelQuery(.panelStatus, panelId: panelId)
        guard case let .panelStatus(panel) = receipt.result else {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator returned an invalid panel status response")
        }
        emitStatusPayload(panel, json: opts.flag("json"))
    }

    static func runWatch(_ args: [String]) async {
        guard !args.isEmpty else { usage("panel watch --panel <id> [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }
        while true {
            let receipt = await residentPanelQuery(.panelStatus, panelId: panelId)
            guard case let .panelStatus(panel) = receipt.result else {
                AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator returned an invalid panel watch response")
            }
            if panel.status != "running" {
                emitWatchPayload(panel, note: panel.status == "done" ? "nothing in flight" : nil, json: opts.flag("json"))
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    static func runDone(_ args: [String]) async {
        guard !args.isEmpty else { usage("panel done --panel <id> [--note …] [--json]") }
        let opts = Options(args)
        guard let panelId = opts.value("panel") else { fail(.missingRequired("--panel <id>")) }
        let receipt = await residentPanelRequest(.panelDone(.init(panelId: panelId, note: opts.value("note"))))
        guard case let .panelStatus(panel) = receipt.result else {
            AllnighterCLI.fail(code: "RESIDENT_REQUEST_REJECTED", message: "resident coordinator returned an invalid panel done response")
        }
        emitDonePayload(panel, json: opts.flag("json"))
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

    private static func emitStartPayload(_ payload: PanelStartJSON, json: Bool) {
        if json {
            print(AllnighterCLI.jsonString(payload))
        } else {
            print("panel \(payload.panel.panelId)")
            print("status: \(payload.panel.status)")
            print("target: \(payload.panel.targetPath)")
            print("scaffold: \(payload.scaffoldPath)")
            print("next: \(payload.nextCommand)")
        }
    }

    private static func emitRoundPayload(_ payload: PanelRoundJSON, json: Bool) {
        if json {
            print(AllnighterCLI.jsonLine(payload))
        } else {
            print("panel \(payload.panel.panelId) round \(payload.round) attempt \(payload.attempt)")
            print("status: \(payload.panel.status)")
            for seat in payload.seatResults {
                print("\n----- seat \(seat.workerId) (\(seat.lens)) [\(seat.status)] -----")
                if !seat.report.isEmpty { print(seat.report) }
                else if let reason = seat.reason { print(reason) }
            }
        }
    }

    private static func emitStartResult(
        _ state: PanelState,
        targetHash: String,
        dirtyAdvisory: String?,
        scaffoldPath: String,
        rememberedTeam: Bool,
        laneDefault: Bool,
        isolation: [PanelSeatIsolation.SeatPlan],
        json: Bool
    ) {
        let modeBySeat = Dictionary(uniqueKeysWithValues: isolation.map { ($0.workerId, $0) })
        let isolationModes = Dictionary(uniqueKeysWithValues: isolation.map {
            ($0.workerId, $0.mode.rawValue)
        })
        let rosterJSON = state.seats.map {
            PanelSeatJSON($0, isolation: isolationModes[$0.workerId])
        }
        let panelJSON = PanelJSON.project(
            state,
            contractVersion: ContractRegistry.contractVersion,
            targetHash: targetHash,
            isolationBySeat: isolationModes
        )
        let next = "alln panel round --panel \(state.id)"
        let isolationJSON = isolation.map {
            PanelSeatIsolationJSON(
                workerId: $0.workerId,
                mode: $0.mode.rawValue,
                driverId: $0.driverId,
                advisory: $0.advisory
            )
        }
        if json {
            print(AllnighterCLI.jsonString(PanelStartJSON(
                contractVersion: ContractRegistry.contractVersion,
                panel: panelJSON,
                roster: rosterJSON,
                targetHash: targetHash,
                dirtyTargetAdvisory: dirtyAdvisory,
                scaffoldPath: scaffoldPath,
                nextCommand: next,
                teamId: state.teamId,
                rememberedTeam: rememberedTeam ? true : (laneDefault ? false : nil),
                isolation: isolationJSON
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
                let mode = modeBySeat[seat.workerId]?.mode.rawValue ?? "unknown"
                print("  - \(seat.workerId) lens=\(seat.lens) isolation=\(mode)")
            }
            print("target: \(state.targetPath)")
            print("targetHash: \(targetHash)")
            if let dirtyAdvisory {
                print("advisory: \(dirtyAdvisory)")
            }
            for plan in isolation where plan.mode == .clone {
                if let advisory = plan.advisory {
                    print("advisory: \(advisory)")
                }
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
        print(AllnighterCLI.jsonLine(line))
        fflush(stdout)
        _ = json
    }

    private static func emitRoundResult(
        _ payload: PanelCoordinator.RoundResult,
        json: Bool
    ) {
        let panelJSON = PanelJSON.project(payload.state, contractVersion: ContractRegistry.contractVersion)
        let unstructuredSeats = PanelUnstructuredSeats.project(from: payload.round.seatResults)
        let convergence = PanelConvergence.project(from: payload.round.seatResults)
        if json {
            print(AllnighterCLI.jsonLine(PanelRoundJSON(
                contractVersion: ContractRegistry.contractVersion,
                panel: panelJSON,
                round: payload.round.roundNumber,
                attempt: payload.attempt.attemptNumber,
                outcome: PanelRoundOutcome.project(from: payload.round),
                targetHash: payload.round.targetHash,
                briefSource: payload.round.briefSource.rawValue,
                seatResults: payload.round.seatResults.map(SeatResultJSON.init),
                unstructuredSeats: unstructuredSeats,
                convergence: convergence
            )))
        } else {
            print("panel \(payload.state.id) round \(payload.round.roundNumber) attempt \(payload.attempt.attemptNumber)")
            print("status: \(payload.state.status.rawValue)")
            print("outcome: \(PanelRoundOutcome.project(from: payload.round))")
            print("targetHash: \(payload.round.targetHash)")
            for workerId in unstructuredSeats {
                print("⚠ unstructured seat: \(workerId) — no parseable findings block; read its verbatim report (content may be real)")
            }
            for entry in convergence {
                print("◎ convergence: \(entry.anchor) — seats: \(entry.seats.joined(separator: ", "))")
            }
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

    /// Resident-projected lifecycle payloads. The client deliberately never
    /// reloads PanelState: a restricted host may not be able to inspect the
    /// coordinator's journal, and only the coordinator can reconcile a dead
    /// round owner before reporting status.
    private static func emitStatusPayload(_ panel: PanelJSON, json: Bool) {
        if json {
            print(AllnighterCLI.jsonString(PanelStatusJSON(panel: panel, recovery: nil, nextActions: [])))
        } else {
            print("panel \(panel.panelId)")
            print("status: \(panel.status)")
            print("target: \(panel.targetPath)")
            print("rounds: \(panel.rounds)/\(panel.maxRounds)")
            if let last = panel.roundLog.last {
                print("last targetHash: \(last.targetHash)")
                for seat in last.seatResults {
                    let detail = seat.reason.map { " — \($0)" } ?? ""
                    print("seat \(seat.workerId): \(seat.status)\(detail)")
                }
            }
            if let note = panel.note { print("note: \(note)") }
        }
    }

    private static func emitWatchPayload(_ panel: PanelJSON, note: String?, json: Bool) {
        if json {
            print(AllnighterCLI.jsonString(PanelWatchJSON(panel: panel, note: note)))
        } else {
            print("panel \(panel.panelId)")
            print("status: \(panel.status)")
            if let last = panel.roundLog.last {
                for seat in last.seatResults {
                    print("\n----- seat \(seat.workerId) (\(seat.lens)) [\(seat.status)] -----")
                    if !seat.report.isEmpty { print(seat.report) }
                    else if let reason = seat.reason { print(reason) }
                }
            }
            if let note { print("\nnote: \(note)") }
        }
    }

    private static func emitDonePayload(_ panel: PanelJSON, json: Bool) {
        if json {
            print(AllnighterCLI.jsonString(panel))
        } else {
            print("panel \(panel.panelId) done")
            if let note = panel.note { print("note: \(note)") }
            print("chain: alln pair pilot start --doc \(panel.targetPath)")
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
                for seat in last.seatResults {
                    let detail = seat.reason.map { " — \($0)" } ?? ""
                    print("seat \(seat.workerId): \(seat.status.rawValue)\(detail)")
                }
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
                    if !seat.report.isEmpty {
                        print(seat.report)
                    } else if let reason = seat.reason {
                        print(reason)
                    }
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
        case ambiguousSeat(alias: String, candidates: String)
        case seatNotFound(alias: String, readySeats: String)
        case unknownSeatModel(workerId: String, modelId: String)
        case seatNoDriver(workerId: String, modelId: String, driverId: String)
        case ambiguousTeam(alias: String, candidates: String)
        case teamNotFound(alias: String, available: String)
        case missingRoster(available: String)
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
        case .ambiguousSeat(let alias, let candidates):
            return ("CLI_USAGE_ERROR", "ambiguous --seat alias '\(alias)' — candidates: \(candidates)")
        case .seatNotFound(let alias, let readySeats):
            return ("CLI_USAGE_ERROR", "no seat matches '\(alias)' — ready seats: \(readySeats)")
        case .unknownSeatModel(let workerId, let modelId):
            return (
                "CLI_USAGE_ERROR",
                "panel seat '\(workerId)' is not a known model (\(modelId)) — fix the roster at start (team preferredModelId or --seat alias)"
            )
        case .seatNoDriver(let workerId, _, let driverId):
            return (
                "CLI_USAGE_ERROR",
                "panel seat '\(workerId)' has no registered driver manifest for '\(driverId)'"
            )
        case .ambiguousTeam(let alias, let candidates):
            return ("CLI_USAGE_ERROR", "ambiguous --team '\(alias)' — candidates: \(candidates)")
        case .teamNotFound(let alias, let available):
            return ("TEAM_NOT_FOUND", "no team matches '\(alias)' — available: \(available)")
        case .missingRoster(let available):
            return ("CLI_USAGE_ERROR", "pass --team <alias> or --seat <alias>:<lens> — available teams: \(available)")
        case .fileUnreadable(let path):
            return ("CLI_USAGE_ERROR", "could not read file: \(path)")
        case .noBrief:
            return ("CLI_USAGE_ERROR", "--brief - produced empty stdin")
        }
    }

    /// Extract the alias side of `--seat alias:lens` for error messages.
    private static func aliasFromSeatFlag(_ raw: String) -> String? {
        PanelTeamResolver.parseSeatFlag(raw)?.alias
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
