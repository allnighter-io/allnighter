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
        /// Executable seats including lead/scout and crew-row multiplicity (Law 8).
        public var seatCount: Int
        /// User-facing on/off state: `false` when the team has been switched OFF
        /// (`TeamVisibility`). Inactive teams are dropped from listings by default
        /// and only appear when `includeInactive` is requested. Resolution by id
        /// (`team_start`, default-run team, a thread's chosen team) is unaffected.
        public var active: Bool
        public var disabledReason: String?

        public init(id: String, displayName: String, lane: String, outputKind: String,
                    defaultEffort: String, mutating: Bool, builtIn: Bool,
                    isDefaultForLane: Bool, seatCount: Int, active: Bool = true,
                    disabledReason: String? = nil) {
            self.id = id; self.displayName = displayName; self.lane = lane; self.outputKind = outputKind
            self.defaultEffort = defaultEffort; self.mutating = mutating
            self.builtIn = builtIn; self.isDefaultForLane = isDefaultForLane
            self.seatCount = seatCount; self.active = active; self.disabledReason = disabledReason
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

    /// Projects the lane-scoped catalog from the same `MenuCatalog` team rows that
    /// `alln menu --json` exposes (MR-S05 / Law 2). Domain fields (lane, effort,
    /// builtIn) come from `TeamPreset`; selection identity/state come from the menu.
    /// Teams switched OFF are dropped unless `includeInactive` is true.
    public static func project(_ teams: [TeamPreset], lane: WorkLane?, contractVersion: String,
                               includeInactive: Bool = false) -> TeamCatalogJSON {
        let scoped = lane.map { l in teams.filter { $0.lane == l } } ?? teams
        let byId = Dictionary(uniqueKeysWithValues: scoped.map { ($0.id, $0) })
        let menu = MenuCatalog.project(teams: scoped.filter { !$0.isLabTeam })
        let entries = menu.teams.compactMap { row -> Entry? in
            // `active` is emitted only when FALSE, so absent means active.
            guard (row.active ?? true) || includeInactive else { return nil }
            guard let team = byId[row.id] else { return nil }
            return Entry(
                id: row.id,
                displayName: row.displayName,
                lane: team.lane.rawValue,
                outputKind: team.outputKind.rawValue,
                defaultEffort: team.defaultEffort.rawValue,
                mutating: row.mutating,
                builtIn: team.builtIn,
                isDefaultForLane: team.isDefaultForLane,
                seatCount: row.seatCount,
                active: row.active ?? true,
                disabledReason: row.blockedReason
            )
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
        public var origin: String
        public var seedId: String?
        public var restoreAvailable: Bool

        public init(
            id: String, displayName: String, lane: String, purpose: String, builtIn: Bool,
            origin: String, seedId: String?, restoreAvailable: Bool
        ) {
            self.id = id; self.displayName = displayName; self.lane = lane
            self.purpose = purpose; self.builtIn = builtIn
            self.origin = origin; self.seedId = seedId; self.restoreAvailable = restoreAvailable
        }
    }
    public var schemaVersion: Int
    public var contractVersion: String
    public var lane: String?
    public var skills: [Entry]

    public init(schemaVersion: Int = 2, contractVersion: String, lane: String? = nil, skills: [Entry]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.lane = lane; self.skills = skills
    }

    public static func project(_ skills: [Skill], lane: WorkLane?, contractVersion: String) -> SkillCatalogJSON {
        SkillCatalogJSON(contractVersion: contractVersion, lane: lane?.rawValue, skills: skills.map {
            let origin = SkillCatalog.origin(of: $0.id) ?? .custom
            return Entry(
                id: $0.id, displayName: $0.displayName, lane: $0.lane.rawValue,
                purpose: $0.purpose.rawValue,
                builtIn: origin == .seed,
                origin: origin.rawValue,
                seedId: SkillCatalog.seedId(for: $0.id),
                restoreAvailable: SkillCatalog.hasOverride($0.id)
            )
        })
    }
}

/// One skill detail projection for `skills show`, `skills edit`, `skills new`, and
/// `skills duplicate` JSON receipts.
public struct SkillDetailJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var id: String
    public var displayName: String
    public var lane: String
    public var purpose: String
    public var builtIn: Bool
    public var origin: String
    public var seedId: String?
    public var restoreAvailable: Bool
    public var template: String
    public var createdAt: String?
    public var updatedAt: String?

    public static func project(_ skill: Skill, contractVersion: String) -> SkillDetailJSON {
        let origin = SkillCatalog.origin(of: skill.id) ?? .custom
        let iso = ISO8601DateFormatter()
        return SkillDetailJSON(
            schemaVersion: 2,
            contractVersion: contractVersion,
            id: skill.id,
            displayName: skill.displayName,
            lane: skill.lane.rawValue,
            purpose: skill.purpose.rawValue,
            builtIn: origin == .seed,
            origin: origin.rawValue,
            seedId: SkillCatalog.seedId(for: skill.id),
            restoreAvailable: SkillCatalog.hasOverride(skill.id),
            template: skill.template,
            createdAt: skill.createdAt.map { iso.string(from: $0) },
            updatedAt: skill.updatedAt.map { iso.string(from: $0) }
        )
    }
}

/// Restore acknowledgement for `alln skills restore`.
public struct SkillRestoreJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var id: String
    public var restored: Bool
    public var origin: String

    public init(schemaVersion: Int = 1, contractVersion: String, id: String, restored: Bool, origin: String) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.id = id
        self.restored = restored
        self.origin = origin
    }
}

// MARK: - teams show

/// One-team inspection projection for `alln teams show --json`. Crew, optional
/// scout, and lead carry role / skill / count / models / capabilities /
/// triangulation so callers need not open `teams definition` for size or
/// staffing. `teams definition` remains the full round-trippable `TeamPreset`.
public struct TeamShowJSON: Codable, Sendable, Equatable {
    public struct CrewSeat: Codable, Sendable, Equatable {
        public var role: String
        public var id: String
        public var skillId: String
        public var purpose: String
        public var count: Int
        public var preferredModelId: String?
        public var fallbackModelIds: [String]?
        public var allowedModelIds: [String]
        public var requiredCapabilityTags: [String]
        public var triangulate: Bool
        public var triangulatePreferenceIds: [String]
        public var required: Bool

        public init(
            role: String, id: String, skillId: String, purpose: String, count: Int,
            preferredModelId: String?, fallbackModelIds: [String]?, allowedModelIds: [String],
            requiredCapabilityTags: [String], triangulate: Bool, triangulatePreferenceIds: [String],
            required: Bool
        ) {
            self.role = role; self.id = id; self.skillId = skillId; self.purpose = purpose
            self.count = count; self.preferredModelId = preferredModelId
            self.fallbackModelIds = fallbackModelIds; self.allowedModelIds = allowedModelIds
            self.requiredCapabilityTags = requiredCapabilityTags
            self.triangulate = triangulate; self.triangulatePreferenceIds = triangulatePreferenceIds
            self.required = required
        }

        public static func from(_ row: TeamAgentSpec, role: String) -> CrewSeat {
            CrewSeat(
                role: role, id: row.id, skillId: row.skillId, purpose: row.purpose.rawValue,
                count: max(1, row.count), preferredModelId: row.preferredModelId,
                fallbackModelIds: row.fallbackModelIds, allowedModelIds: row.allowedModelIds,
                requiredCapabilityTags: row.requiredCapabilityTags.map(\.rawValue),
                triangulate: row.triangulate, triangulatePreferenceIds: row.triangulatePreferenceIds,
                required: row.required
            )
        }
    }

    public struct LeadSeat: Codable, Sendable, Equatable {
        public var role: String
        public var skillId: String
        public var count: Int
        public var preferredModelId: String?
        public var fallbackModelIds: [String]?
        public var allowedModelIds: [String]
        public var requiredCapabilityTags: [String]
        public var triangulate: Bool
        public var dissentPolicy: String

        public init(
            role: String = "lead", skillId: String, count: Int = 1,
            preferredModelId: String?, fallbackModelIds: [String]?,
            allowedModelIds: [String] = [], requiredCapabilityTags: [String],
            triangulate: Bool = false, dissentPolicy: String
        ) {
            self.role = role; self.skillId = skillId; self.count = count
            self.preferredModelId = preferredModelId; self.fallbackModelIds = fallbackModelIds
            self.allowedModelIds = allowedModelIds
            self.requiredCapabilityTags = requiredCapabilityTags
            self.triangulate = triangulate; self.dissentPolicy = dissentPolicy
        }

        public static func from(_ lead: TeamLeadSpec, count: Int = 1) -> LeadSeat {
            LeadSeat(
                skillId: lead.skillId, count: count, preferredModelId: lead.preferredModelId,
                fallbackModelIds: lead.fallbackModelIds,
                requiredCapabilityTags: lead.requiredCapabilityTags.map(\.rawValue),
                dissentPolicy: lead.dissentPolicy.rawValue
            )
        }
    }

    public var schemaVersion: Int
    public var contractVersion: String
    public var id: String
    public var displayName: String
    public var lane: String
    public var outputKind: String
    public var defaultEffort: String
    public var mutating: Bool
    public var builtIn: Bool
    public var isDefaultForLane: Bool
    public var description: String
    /// Executable seats including lead/scout and crew-row multiplicity.
    public var seatCount: Int
    public var scout: CrewSeat?
    public var crew: [CrewSeat]
    public var lead: LeadSeat
    public var origin: String
    public var seedId: String?
    public var restoreAvailable: Bool
    public var isDefaultForRun: Bool

    public init(
        schemaVersion: Int = 1, contractVersion: String,
        id: String, displayName: String, lane: String, outputKind: String,
        defaultEffort: String, mutating: Bool, builtIn: Bool, isDefaultForLane: Bool,
        description: String, seatCount: Int, scout: CrewSeat?, crew: [CrewSeat], lead: LeadSeat,
        origin: String, seedId: String?, restoreAvailable: Bool, isDefaultForRun: Bool
    ) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.id = id; self.displayName = displayName; self.lane = lane; self.outputKind = outputKind
        self.defaultEffort = defaultEffort; self.mutating = mutating; self.builtIn = builtIn
        self.isDefaultForLane = isDefaultForLane; self.description = description
        self.seatCount = seatCount; self.scout = scout; self.crew = crew; self.lead = lead
        self.origin = origin; self.seedId = seedId; self.restoreAvailable = restoreAvailable
        self.isDefaultForRun = isDefaultForRun
    }

    /// Projects a complete, inspectable team read. Seat sum of scout + crew counts
    /// + lead equals `team.catalogSeatCount` (and list/menu `seatCount`).
    public static func project(
        _ team: TeamPreset,
        contractVersion: String,
        origin: String,
        seedId: String?,
        restoreAvailable: Bool,
        isDefaultForRun: Bool
    ) -> TeamShowJSON {
        let scout = team.scout.map { CrewSeat.from($0, role: "scout") }
        let crew = team.agentSpecs.map { CrewSeat.from($0, role: "crew") }
        // Solo answer teams (`code_doc_review`, `default_chat`) run the lead's
        // skill as the same seat as the one crew worker — no separate synthesis
        // pass, so no extra lead seat (`TeamPreset.isSoloAnswerTeam`).
        let lead = LeadSeat.from(team.lead, count: team.isSoloAnswerTeam ? 0 : 1)
        return TeamShowJSON(
            contractVersion: contractVersion,
            id: team.id, displayName: team.disclosedDisplayName, lane: team.lane.rawValue,
            outputKind: team.outputKind.rawValue, defaultEffort: team.defaultEffort.rawValue,
            mutating: team.mutating, builtIn: team.builtIn, isDefaultForLane: team.isDefaultForLane,
            description: team.description, seatCount: team.catalogSeatCount,
            scout: scout, crew: crew, lead: lead,
            origin: origin, seedId: seedId, restoreAvailable: restoreAvailable,
            isDefaultForRun: isDefaultForRun
        )
    }

    /// Structural seat sum from the projected rows (multiplicity included).
    public var projectedSeatSum: Int {
        (scout?.count ?? 0) + crew.reduce(0) { $0 + $1.count } + lead.count
    }
}
