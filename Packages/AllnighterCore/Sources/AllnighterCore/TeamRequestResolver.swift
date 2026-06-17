import Foundation

/// Maps a Fan out request (lane / team / type / effort) onto a concrete catalog
/// team before resolution. `--team` is the selector; `--type` is Copy-only sugar
/// that routes to a team only when no team was given, and a conflicting team/type
/// pair is rejected (Fanout_Team_Catalog §Canonical Fan out request).
public enum TeamRequestResolver {

    public struct Resolved: Sendable, Equatable {
        public var team: TeamPreset
        public var lane: WorkLane
        public var effort: EffortLevel
        /// Echoed only when `type` actually routed/validated the team (else nil).
        public var type: String?
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case laneRequired
        case unknownTeam(String)
        case laneMismatch(team: String, teamLane: WorkLane, requestLane: WorkLane)
        case conflictingTeamAndType(team: String, type: String)
        case noTeamForType(lane: WorkLane, type: String)
        case noTeamInLane(WorkLane)

        /// Stable error code for the CLI/MCP error envelope.
        public var code: String {
            switch self {
            case .laneRequired, .laneMismatch, .conflictingTeamAndType, .noTeamForType: return "CLI_USAGE_ERROR"
            case .unknownTeam, .noTeamInLane: return "DEFAULT_TEAM_INVALID"
            }
        }

        public var description: String {
            switch self {
            case .laneRequired:
                return "Fan out requires a lane: pass --lane build|design|copy (or --team)."
            case .unknownTeam(let id):
                return "unknown team: \(id). Run `alln teams --lane <lane> --json`."
            case .laneMismatch(let team, let teamLane, let requestLane):
                return "team \(team) is a \(teamLane.rawValue) team but --lane is \(requestLane.rawValue)."
            case .conflictingTeamAndType(let team, let type):
                return "--type \(type) conflicts with --team \(team) (type is not in the team's typeTags)."
            case .noTeamForType(let lane, let type):
                return "no \(lane.rawValue) team matches --type \(type)."
            case .noTeamInLane(let lane):
                return "no team available in lane \(lane.rawValue)."
            }
        }
    }

    public static func resolve(
        teams: [TeamPreset],
        lane: WorkLane?,
        teamId: String?,
        type: String?,
        effort: EffortLevel?
    ) -> Result<Resolved, Failure> {
        // Explicit team wins; lane is derived from it when omitted.
        if let teamId, !teamId.isEmpty {
            guard let team = teams.first(where: { $0.id == teamId }) else {
                return .failure(.unknownTeam(teamId))
            }
            if let lane, lane != team.lane {
                return .failure(.laneMismatch(team: teamId, teamLane: team.lane, requestLane: lane))
            }
            var matchedType: String?
            if let type, !type.isEmpty {
                guard team.typeTags.contains(type) else {
                    return .failure(.conflictingTeamAndType(team: teamId, type: type))
                }
                matchedType = type
            }
            return .success(Resolved(team: team, lane: team.lane,
                                     effort: effort ?? team.defaultEffort, type: matchedType))
        }

        // No explicit team: lane is required.
        guard let lane else { return .failure(.laneRequired) }

        // Type routing (Copy sugar): pick the team whose typeTags contains the type.
        if let type, !type.isEmpty {
            guard let team = teams.teams(in: lane).first(where: { $0.typeTags.contains(type) }) else {
                return .failure(.noTeamForType(lane: lane, type: type))
            }
            return .success(Resolved(team: team, lane: lane,
                                     effort: effort ?? team.defaultEffort, type: type))
        }

        // Otherwise the lane default team.
        guard let team = teams.defaultTeam(for: lane) else {
            return .failure(.noTeamInLane(lane))
        }
        return .success(Resolved(team: team, lane: lane, effort: effort ?? team.defaultEffort, type: nil))
    }
}
