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
        public var posture: String
        public var mutating: Bool
        public var builtIn: Bool
        public var isDefaultForLane: Bool
        public var workerCount: Int
        public var disabledReason: String?

        public init(id: String, displayName: String, lane: String, outputKind: String,
                    defaultEffort: String, posture: String, mutating: Bool, builtIn: Bool,
                    isDefaultForLane: Bool, workerCount: Int, disabledReason: String? = nil) {
            self.id = id; self.displayName = displayName; self.lane = lane; self.outputKind = outputKind
            self.defaultEffort = defaultEffort; self.posture = posture; self.mutating = mutating
            self.builtIn = builtIn; self.isDefaultForLane = isDefaultForLane
            self.workerCount = workerCount; self.disabledReason = disabledReason
        }
    }
    public var schemaVersion: Int
    public var contractVersion: String
    public var lane: String?
    public var teams: [Entry]

    public init(schemaVersion: Int = 1, contractVersion: String, lane: String? = nil, teams: [Entry]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.lane = lane; self.teams = teams
    }

    public static func project(_ teams: [TeamPreset], lane: WorkLane?, contractVersion: String) -> TeamCatalogJSON {
        TeamCatalogJSON(contractVersion: contractVersion, lane: lane?.rawValue, teams: teams.map {
            Entry(id: $0.id, displayName: $0.displayName, lane: $0.lane.rawValue,
                  outputKind: $0.outputKind.rawValue, defaultEffort: $0.defaultEffort.rawValue,
                  posture: $0.posture.rawValue, mutating: $0.mutating, builtIn: $0.builtIn,
                  isDefaultForLane: $0.isDefaultForLane, workerCount: $0.workerSpecs.count)
        })
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
