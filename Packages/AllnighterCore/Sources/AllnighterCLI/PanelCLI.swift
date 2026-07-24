import Foundation
import AllnighterCore
import AllnighterEngine

/// Frozen Code Red Panel surface. It stays parse-compatible but may not route work.
enum PanelCLI {
    struct StartRequest {
        var config: PanelCoordinator.Config
        var teamId: String?
        var rememberedTeam: Bool
        var laneDefault: Bool
        var seats: [PanelSeat]
    }

    static func run(_ args: [String], runtime: ToolRuntime) async {
        _ = args
        _ = runtime
        AllnighterCLI.fail(
            code: "CODE_RED_UNSUPPORTED",
            message: "Panel is temporarily unsupported during Code Red; use `alln run` in the registered repository"
        )
    }

    // MARK: - start


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

        // End-to-end roster preflight: model exists + driver manifest present.
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





    /// Resident-projected lifecycle payloads. The client deliberately never
    /// reloads PanelState: a restricted host may not be able to inspect the
    /// coordinator's journal, and only the coordinator can reconcile a dead
    /// round owner before reporting status.






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
