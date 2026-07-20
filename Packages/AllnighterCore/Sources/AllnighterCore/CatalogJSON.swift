import Foundation

// MARK: - Catalog list contracts (teams_list / skills_list)

/// The lane-scoped team catalog summary returned by `alln teams --json` and the
/// MCP `teams_list` tool. A structured, schema-backed projection (M-A) so agents
/// can discover teams — and the `mutating` flag before running — without parsing
/// prose. The full lineup/prompt templates belong to `teams show`.
public struct TeamCatalogJSON: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var displayName: String
        public var lane: String
        public var outputKind: String
        public var defaultEffort: String
        public var mutating: Bool
        public var builtIn: Bool
        public var isDefaultForLane: Bool
        public var workerCount: Int
        /// User-facing on/off state: `false` when the team has been switched OFF
        /// (`TeamVisibility`). Inactive teams are dropped from listings by default
        /// and only appear when `includeInactive` is requested. Resolution by id
        /// (`team_start`, default-run team, a thread's chosen team) is unaffected.
        public var active: Bool
        public var disabledReason: String?

        public init(id: String, displayName: String, lane: String, outputKind: String,
                    defaultEffort: String, mutating: Bool, builtIn: Bool,
                    isDefaultForLane: Bool, workerCount: Int, active: Bool = true,
                    disabledReason: String? = nil) {
            self.id = id; self.displayName = displayName; self.lane = lane; self.outputKind = outputKind
            self.defaultEffort = defaultEffort; self.mutating = mutating
            self.builtIn = builtIn; self.isDefaultForLane = isDefaultForLane
            self.workerCount = workerCount; self.active = active; self.disabledReason = disabledReason
        }
    }

    public var schemaVersion: Int
    public var contractVersion: String
    public var lane: String?
    public var teams: [Entry]
    public var counsel: String?
    public var nextActions: [AgentSurfaceNextAction]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, contractVersion, lane, teams, counsel, nextActions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        contractVersion = try c.decode(String.self, forKey: .contractVersion)
        lane = try c.decodeIfPresent(String.self, forKey: .lane)
        teams = try c.decode([Entry].self, forKey: .teams)
        counsel = try c.decodeIfPresent(String.self, forKey: .counsel)
        nextActions = try c.decodeIfPresent([AgentSurfaceNextAction].self, forKey: .nextActions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(contractVersion, forKey: .contractVersion)
        try c.encodeIfPresent(lane, forKey: .lane)
        try c.encode(teams, forKey: .teams)
        try c.encodeIfPresent(counsel, forKey: .counsel)
        try c.encode(nextActions, forKey: .nextActions)
    }

    public init(schemaVersion: Int = 1, contractVersion: String, lane: String? = nil, teams: [Entry],
                counsel: String? = nil, nextActions: [AgentSurfaceNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.lane = lane; self.teams = teams; self.counsel = counsel; self.nextActions = nextActions
    }

    /// Projects the lane-scoped catalog. Teams switched OFF in `TeamVisibility` are
    /// dropped unless `includeInactive` is true, in which case they are returned with
    /// `active: false`. This is the single funnel for `alln teams --json` and the MCP
    /// `teams_list` tool, so the "Inactive" state is honored identically across GUI,
    /// CLI, and MCP.
    public static func project(_ teams: [TeamPreset], lane: WorkLane?, contractVersion: String,
                               includeInactive: Bool = false) -> TeamCatalogJSON {
        let entries = teams.compactMap { team -> Entry? in
            let active = TeamVisibility.isEnabled(team.id)
            guard active || includeInactive else { return nil }
            return Entry(id: team.id, displayName: team.displayName, lane: team.lane.rawValue,
                         outputKind: team.outputKind.rawValue, defaultEffort: team.defaultEffort.rawValue,
                         mutating: team.mutating, builtIn: team.builtIn,
                         isDefaultForLane: team.isDefaultForLane,
                         // Seat count includes Team Lead + worker rows (AE-S10 — matches preflight).
                         workerCount: team.workerSpecs.count + 1,
                         active: active)
        }
        var payload = TeamCatalogJSON(contractVersion: contractVersion, lane: lane?.rawValue, teams: entries)
        if entries.isEmpty {
            let (counsel, nextActions) = AgentFrontDoor.emptyTeamsCounsel()
            payload.counsel = counsel
            payload.nextActions = nextActions
        }
        return payload
    }
}

/// The lane-scoped skill catalog summary returned by `alln skills --json` and the
/// MCP `skills_list` tool (no prompt templates — those belong to `skills show`).
public struct SkillCatalogJSON: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var displayName: String
        public var lane: String
        public var purpose: String
        public var builtIn: Bool

        public init(id: String, displayName: String, lane: String, purpose: String, builtIn: Bool) {
            self.id = id; self.displayName = displayName; self.lane = lane
            self.purpose = purpose; self.builtIn = builtIn
        }
    }
    public var schemaVersion: Int
    public var contractVersion: String
    public var lane: String?
    public var skills: [Entry]

    public init(schemaVersion: Int = 1, contractVersion: String, lane: String? = nil, skills: [Entry]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.lane = lane; self.skills = skills
    }

    public static func project(_ skills: [Skill], lane: WorkLane?, contractVersion: String) -> SkillCatalogJSON {
        SkillCatalogJSON(contractVersion: contractVersion, lane: lane?.rawValue, skills: skills.map {
            Entry(id: $0.id, displayName: $0.displayName, lane: $0.lane.rawValue,
                  purpose: $0.purpose.rawValue, builtIn: $0.builtIn)
        })
    }
}
