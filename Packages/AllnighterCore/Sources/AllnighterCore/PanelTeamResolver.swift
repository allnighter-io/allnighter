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

    /// Parse one `--seat <alias>:<lens>` entry. Alias is treated as workerId
    /// (model id or seat id); lens is free text.
    public static func parseSeatFlag(_ raw: String) -> PanelSeat? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let workerId = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lens = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workerId.isEmpty, !lens.isEmpty else { return nil }
        return PanelSeat(workerId: workerId, lens: lens)
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
