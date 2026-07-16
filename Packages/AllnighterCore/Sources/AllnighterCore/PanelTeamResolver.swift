import Foundation

/// Fuzzy team-alias resolution for `panel start --team` (`docs/phases/Pilot_Panel.md`
/// decision 4 / PN-S04). Mirrors `PilotSeatResolver`: case-insensitive exact /
/// contains / suffix match over team id + displayName. Unique → resolved and
/// echoed; ambiguous → candidates with displayName + seat count; none → list teams.
///
/// **Roster mapping (stated):** each team worker row becomes a `PanelSeat` with
/// `workerId = preferredModelId ?? row.id` and `lens = skillId` (the skill is the
/// lens identity; purpose selects answer vs review, both are jury seats). The
/// Team Lead / plan-writer is NOT a panel seat — Panel has no synthesis seat
/// (decision 1: the session is the synthesizer).
public enum PanelTeamResolver {
    public enum Error: Swift.Error, Equatable, Sendable {
        case ambiguous(alias: String, candidates: [TeamPreset])
        case noMatch(alias: String, available: [TeamPreset])
        case noTeams
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

    /// Resolve a team alias to exactly one `TeamPreset`.
    public static func resolveTeam(alias raw: String, teams: [TeamPreset]) -> Result<TeamPreset, Error> {
        let alias = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !alias.isEmpty else {
            return .failure(.noMatch(alias: raw, available: teams.sorted { $0.id < $1.id }))
        }
        guard !teams.isEmpty else { return .failure(.noTeams) }
        let matches = teams.filter { matchesAlias(alias, team: $0) }
        switch matches.count {
        case 0:
            return .failure(.noMatch(alias: raw, available: teams.sorted { $0.id < $1.id }))
        case 1:
            return .success(matches[0])
        default:
            return .failure(.ambiguous(alias: raw, candidates: matches.sorted { $0.id < $1.id }))
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

    /// Resolve a seat alias to a real model id via the same `PilotSeatResolver`
    /// algorithm as `pilot start --dev-worker` (case-insensitive substring/suffix
    /// over model id + displayName).
    ///
    /// Call-site policy (panel start only): prefer **enabled** (on-bench) models so
    /// short aliases like `sonnet` resolve uniquely when only one match is enabled;
    /// fall back to the full catalog so off-bench seats stay addressable
    /// (`cursor_grok` → `model_cursor_grok_45`). Ambiguous among enabled → error.
    public static func resolveSeatAlias(
        _ alias: String,
        models: [Model]
    ) -> Result<String, PilotSeatResolver.Error> {
        let enabled = models.filter(\.enabled)
        if !enabled.isEmpty {
            switch PilotSeatResolver.resolve(alias: alias, models: enabled) {
            case .success(let id):
                return .success(id)
            case .failure(.ambiguous(let a, let candidates)):
                return .failure(.ambiguous(alias: a, candidates: candidates))
            case .failure(.noMatch), .failure(.noReadySeats):
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
        (team.scout == nil ? 0 : 1) + team.workerSpecs.count
    }

    private static func matchesAlias(_ alias: String, team: TeamPreset) -> Bool {
        let id = team.id.lowercased()
        let name = team.displayName.lowercased()
        if id == alias || name == alias { return true }
        if id.contains(alias) || name.contains(alias) { return true }
        if id.hasSuffix(alias) || name.hasSuffix(alias) { return true }
        return false
    }
}
