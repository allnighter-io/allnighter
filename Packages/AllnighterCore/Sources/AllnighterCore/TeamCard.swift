import Foundation

// MARK: - Team Card (docs/phases/Team_Delegation_Surface.md)

/// A read-only projection of a `TeamPreset` for the Send-to-team browse surface.
/// NOT a new team — every field is projected from the existing team plus a little
/// card-facing state. No "promise"/marketing line (cut as fluff); `requirements`
/// are DERIVED readiness facts, never authored "attach X" input asks.
public struct TeamCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var teamId: String
    public var displayName: String
    /// Public family / craft (`signal|code|design|copy`).
    public var family: String
    public var mutating: Bool
    public var executionSourceId: String?
    public var outputKind: String
    public var agentCount: Int
    public var starterPrompts: [String]
    /// Derived gates that must hold before a run — not user-authored input asks.
    public var requirements: [String]
    public var recommendedFor: [String]
    public var pinned: Bool
    public var pinnedReason: String?
    public var lastRunAt: Date?

    public init(id: String, teamId: String, displayName: String, family: String,
                mutating: Bool, executionSourceId: String? = nil, outputKind: String, agentCount: Int,
                starterPrompts: [String] = [],
                requirements: [String] = [], recommendedFor: [String] = [], pinned: Bool = false,
        pinnedReason: String? = nil, lastRunAt: Date? = nil) {
        self.id = id; self.teamId = teamId; self.displayName = displayName; self.family = family
        self.mutating = mutating; self.executionSourceId = executionSourceId
        self.outputKind = outputKind
        self.agentCount = agentCount; self.starterPrompts = starterPrompts
        self.requirements = requirements; self.recommendedFor = recommendedFor
        self.pinned = pinned; self.pinnedReason = pinnedReason; self.lastRunAt = lastRunAt
    }

    /// Project one team into a card. `pinned`/`lastRunAt` come from user-state /
    /// history (supplied by the caller); live worker-readiness requirements are
    /// layered in by preflight (T-S03) — this is the structural baseline.
    public static func project(_ team: TeamPreset, pinned: Bool = false, pinnedReason: String? = nil,
                               lastRunAt: Date? = nil) -> TeamCard {
        TeamCard(
            id: team.id, teamId: team.id, displayName: team.displayName, family: team.lane.rawValue,
            mutating: team.mutating,
            executionSourceId: team.executionSourceId,
            outputKind: team.outputKind.rawValue,
            agentCount: team.runShape == .execution ? 1 : team.agentSpecs.count,
            starterPrompts: team.starterPrompts,
            requirements: derivedRequirements(team), recommendedFor: team.typeTags + team.purposeTags,
            pinned: pinned, pinnedReason: pinnedReason, lastRunAt: lastRunAt)
    }

    /// Structural run gates derived from the team — never an authored input ask.
    static func derivedRequirements(_ team: TeamPreset) -> [String] {
        var reqs = ["Needs at least one ready \(team.lane.rawValue) agent."]
        if team.mutating {
            reqs.append("Runs one mutating agent in the repo root.")
            if let source = team.executionSourceId {
                reqs.append("Runs on \(source) only.")
            }
        }
        return reqs
    }
}

/// The Send-to-team card catalog, grouped by public family. The browse surface
/// renders this; cards never carry GUI-local content.
public struct TeamCardCatalogJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var family: String?
    public var cards: [TeamCard]

    public init(schemaVersion: Int = 1, contractVersion: String, family: String? = nil, cards: [TeamCard]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.family = family; self.cards = cards
    }

    public static func project(_ teams: [TeamPreset], family: WorkLane?, contractVersion: String,
                               pinned: Set<String> = []) -> TeamCardCatalogJSON {
        TeamCardCatalogJSON(contractVersion: contractVersion, family: family?.rawValue,
                            cards: teams.map { TeamCard.project($0, pinned: pinned.contains($0.id)) })
    }
}
