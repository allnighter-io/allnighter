import Foundation

/// Exact-id team resolution for `panel start --team` (MR-S04 / Menu Not Router).
/// Canonical team ids only — display names never authorize dispatch.
///
/// **Roster mapping (stated):** Panel resolves each worker row against the ready
/// model bench, then uses the resolved model id as its `PanelSeat.workerId` and
/// the skill as its lens. This matters for capability-only built-ins: their row
/// ids are skill ids, not model ids. The Team Lead / plan-writer is NOT a panel
/// seat — Panel has no synthesis seat (decision 1: the session is the synthesizer).
public enum PanelTeamResolver {
    public enum Error: Swift.Error, Equatable, Sendable {
        case ambiguous(alias: String, candidates: [TeamPreset])
        case noMatch(alias: String, available: [TeamPreset])
        case noTeams
        /// Structured exact-id failure (preferred path).
        case exactId(ExactIdResolver.Failure)
    }

    public enum RosterValidationError: Swift.Error, Equatable, Sendable {
        /// Model id not present in the catalog (team preferredModelId stale, etc.).
        case unknownModel(workerId: String, modelId: String)
        /// Model exists but its driver has no registered manifest.
        case noDriver(workerId: String, modelId: String, driverId: String)
    }

    public struct ResolvedRoster: Sendable, Equatable {
        public var team: TeamPreset?
        public var seats: [PanelSeat]
        /// True when the team came from the remembered-last-used store (not an explicit flag).
        public var rememberedTeam: Bool
        /// True when the team is the lane-default fallback (no remembered, no flags).
        public var laneDefault: Bool

        public init(
            team: TeamPreset?,
            seats: [PanelSeat],
            rememberedTeam: Bool = false,
            laneDefault: Bool = false
        ) {
            self.team = team
            self.seats = seats
            self.rememberedTeam = rememberedTeam
            self.laneDefault = laneDefault
        }
    }

    /// Parsed `--seat <alias>:<lens>` before model-id resolution.
    public struct ParsedSeatFlag: Sendable, Equatable {
        public var alias: String
        public var lens: String

        public init(alias: String, lens: String) {
            self.alias = alias
            self.lens = lens
        }
    }

    /// Resolve a canonical team id to exactly one `TeamPreset`.
    public static func resolveTeam(alias raw: String, teams: [TeamPreset]) -> Result<TeamPreset, Error> {
        guard !teams.isEmpty else { return .failure(.noTeams) }
        switch ExactIdResolver.resolveTeam(raw, flag: "--team", teams: teams) {
        case .success(let team):
            return .success(team)
        case .failure(let failure):
            return .failure(.exactId(failure))
        }
    }

    /// Map a team's worker specs → panel seats.
    ///
    /// Mapping (stated): `lens = skillId` (the skill is the lens identity).
    /// `workerId = preferredModelId ?? row.id` when unique on the roster; on
    /// collision (self-fusion / shared preferred model) →
    /// `preferredModelId#row.id` so seats stay addressable for `--seats` reruns.
    /// Model id for RO/dispatch is always the prefix before `#` (see `modelId(for:)`).
    /// Includes answer + review rows (jury seats); excludes the Lead/plan-writer
    /// (session synthesizes — decision 1). Scout rows are included as answer seats.
    public static func seats(from team: TeamPreset) -> [PanelSeat] {
        var rows: [TeamWorkerSpec] = []
        if let scout = team.scout { rows.append(scout) }
        rows.append(contentsOf: team.workerSpecs)

        var seenModels: Set<String> = []
        return rows.map { row in
            let model = row.preferredModelId ?? row.id
            let workerId: String
            if seenModels.contains(model) {
                workerId = "\(model)#\(row.id)"
            } else {
                seenModels.insert(model)
                workerId = model
            }
            return PanelSeat(workerId: workerId, lens: row.skillId)
        }
    }

    /// Resolve a team's panel jury against the ready bench. Unlike the legacy
    /// static projection above, this never mistakes a capability-only worker row
    /// id for a model id (for example `spec_proof_planner`).
    public static func seats(from team: TeamPreset, readyModels: [Model]) -> [PanelSeat] {
        let rows = (team.scout.map { [$0] } ?? []) + team.workerSpecs
        // Preserve the legacy exact-preference roster byte-for-byte. Only teams
        // that actually express capability-only need require dynamic resolution.
        guard rows.contains(where: { $0.preferredModelId == nil }) else {
            return seats(from: team)
        }
        let resolved = TeamResolver.resolve(
            team: team,
            requestLane: team.lane,
            requestEffort: team.defaultEffort,
            readyModels: readyModels.filter(\.enabled)
        )
        let workers = (resolved.scoutWorker.map { [$0] } ?? [])
            + resolved.answerWorkers
            + resolved.reviewWorkers
        return workers.compactMap {
            guard let skillID = $0.skillId else { return nil }
            return PanelSeat(workerId: $0.id, lens: skillID)
        }
    }

    /// Recover the model id from a panel seat workerId (`model` or `model#rowId`).
    public static func modelId(for workerId: String) -> String {
        if let idx = workerId.firstIndex(of: "#") {
            return String(workerId[..<idx])
        }
        return workerId
    }

    /// Parse one `--seat <alias>:<lens>` entry. Alias is NOT stored as workerId —
    /// resolve it with `resolveSeatAlias` (PilotSeatResolver) before building state.
    public static func parseSeatFlag(_ raw: String) -> ParsedSeatFlag? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let alias = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lens = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty, !lens.isEmpty else { return nil }
        return ParsedSeatFlag(alias: alias, lens: lens)
    }

    /// Resolve a seat token to a real model id via `ExactIdResolver` (MR-S04).
    /// Canonical model ids only — display names never authorize dispatch.
    public static func resolveSeatAlias(
        _ alias: String,
        models: [Model]
    ) -> Result<String, PilotSeatResolver.Error> {
        let enabled = models.filter(\.enabled)
        if !enabled.isEmpty {
            switch PilotSeatResolver.resolve(alias: alias, models: enabled) {
            case .success(let id):
                return .success(id)
            case .failure(.exactId), .failure(.noMatch), .failure(.noReadySeats), .failure(.ambiguous):
                break
            }
        }
        return PilotSeatResolver.resolve(alias: alias, models: models)
    }

    /// Parse + resolve one `--seat` flag into a durable `PanelSeat` with a real model id.
    /// Returns `nil` when the flag shape is invalid (`alias:lens` missing).
    public static func resolveSeatFlag(
        _ raw: String,
        models: [Model]
    ) -> Result<PanelSeat, PilotSeatResolver.Error>? {
        guard let parsed = parseSeatFlag(raw) else { return nil }
        switch resolveSeatAlias(parsed.alias, models: models) {
        case .success(let modelId):
            return .success(PanelSeat(workerId: modelId, lens: parsed.lens))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Apply `--seat` overrides/extends on top of a base roster.
    /// Same workerId → replace lens; new workerId → append.
    public static func applySeatOverrides(base: [PanelSeat], overrides: [PanelSeat]) -> [PanelSeat] {
        var byId: [String: PanelSeat] = [:]
        var order: [String] = []
        for seat in base {
            if byId[seat.workerId] == nil { order.append(seat.workerId) }
            byId[seat.workerId] = seat
        }
        for seat in overrides {
            if byId[seat.workerId] == nil {
                order.append(seat.workerId)
            }
            byId[seat.workerId] = seat
        }
        return order.compactMap { byId[$0] }
    }

    /// End-to-end roster preflight: every seat's model id exists in the catalog and
    /// has a driver manifest so isolation mode is determinable (RO vs clone). Failures
    /// belong at `panel start` (exit 2), never as mid-round "not a known model".
    public static func validateRoster(
        seats: [PanelSeat],
        models: [Model],
        registry: DriverRegistry
    ) -> Result<Void, RosterValidationError> {
        for seat in seats {
            let modelId = modelId(for: seat.workerId)
            guard let model = models.first(where: { $0.id == modelId }) else {
                return .failure(.unknownModel(workerId: seat.workerId, modelId: modelId))
            }
            guard registry.manifest(for: model) != nil else {
                return .failure(.noDriver(workerId: seat.workerId, modelId: modelId, driverId: model.driverId))
            }
        }
        return .success(())
    }

    public static func formatCandidates(_ teams: [TeamPreset]) -> String {
        teams.map { "\($0.id) (\($0.displayName), \(seatCount($0)) seats)" }
            .joined(separator: ", ")
    }

    public static func formatAvailable(_ teams: [TeamPreset]) -> String {
        let list = teams.sorted { $0.id < $1.id }.map {
            "\($0.id) (\($0.displayName), \(seatCount($0)) seats)"
        }
        return list.isEmpty ? "(none)" : list.joined(separator: ", ")
    }

    public static func seatCount(_ team: TeamPreset) -> Int {
        team.catalogSeatCount
    }

}
