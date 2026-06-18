import Foundation

// MARK: - Catalog identifiers

/// Stable machine identifier for one team definition (global namespace across lanes).
public typealias TeamID = String

/// Stable machine identifier for one skill definition (global namespace across lanes).
public typealias SkillID = String

/// Catalog entry for one built-in or custom lane team (`TeamPreset` is the persisted shape).
public typealias TeamDefinition = TeamPreset

// MARK: - Fan out lane / effort / output

/// The three peer creation lanes. Fan out always requires an explicit lane —
/// Allnighter never infers it from the prompt (docs/phases/Fanout_Team_Catalog.md).
public enum WorkLane: String, Codable, Sendable, CaseIterable {
    case build
    case design
    case copy
}

/// Effort bundle for a team run. Canonical machine values are `low | med | high`
/// (no `medium`, never `quick/standard/deep`). Effort is an instruction bundle —
/// number of workers, review depth, synthesis policy — never a runtime/cost forecast.
public enum EffortLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case med
    case high

    /// Activation order: `low` activates `low` rows; `med` activates `low + med`;
    /// `high` activates all rows.
    public var rank: Int {
        switch self {
        case .low: return 0
        case .med: return 1
        case .high: return 2
        }
    }

    /// Display label (`Low` / `Med` / `High`).
    public var displayLabel: String {
        switch self {
        case .low: return "Low"
        case .med: return "Med"
        case .high: return "High"
        }
    }

    public static func < (lhs: EffortLevel, rhs: EffortLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// What a team produces. `outputKind` chooses the synthesis profile, result
/// renderer, and default stage shape so a Security Review is never forced into a
/// generic Build plan and a Design/Copy board never pretends to be a plan.
public enum TeamOutputKind: String, Codable, Sendable, CaseIterable {
    case plan
    case bugPacket
    case securityRegister
    case architectureVerdict
    case proofPacket
    case designBoard
    case polishBoard
    case copyBoard
}

/// Stage a worker row runs in. Answer workers run blind in parallel; review
/// workers run after answer workers and may see answer outputs.
public enum TeamWorkerPurpose: String, Codable, Sendable, CaseIterable {
    case answer
    case review
}

// MARK: - Model capability metadata

/// Capability tags a model can carry, used by capability-filtered fallback before
/// rank fallback. Until user-edited ranking exists, built-in metadata supplies
/// deterministic defaults.
public enum ModelCapabilityTag: String, Codable, Sendable, CaseIterable {
    case code
    case planner
    case review
    case security
    case design
    case image
    case copy
    case localContext
    case fast
}

/// Deterministic, Core-owned capability metadata for a model. Ties break by
/// stable model id; higher `strengthRank` is stronger.
public struct ModelCapabilities: Codable, Sendable, Equatable {
    public var laneTags: [WorkLane]
    public var capabilityTags: [ModelCapabilityTag]
    /// Higher is stronger. Ties break by stable model id.
    public var strengthRank: Int

    public init(laneTags: [WorkLane] = [], capabilityTags: [ModelCapabilityTag] = [], strengthRank: Int = 0) {
        self.laneTags = laneTags
        self.capabilityTags = capabilityTags
        self.strengthRank = strengthRank
    }
}

/// How a worker row falls back when its preferred model is not ready.
public enum ModelFallbackPolicy: String, Codable, Sendable, CaseIterable {
    /// Only the preferred/allowed model(s); no fallback.
    case exactOnly
    /// Prefer another ready model on the same source (driver).
    case sameSource
    /// Any ready model tagged for the team's lane.
    case laneCapable
    /// Any ready model that matches required capability tags.
    case anyReady
    /// The strongest ready model by rank.
    case strongestReady
}

/// How the synthetic plan/output writer treats disagreement among workers.
public enum DissentPolicy: String, Codable, Sendable, CaseIterable {
    case preserveDissent
    case compareOptions
    case riskRegister
}

// MARK: - Team worker row

/// One worker row in a lane-scoped team. References a `skillId`; resolved against
/// the ready bench at run start into one or more `Worker`s (self-fusion when one
/// model fills several rows). `count > 1` makes multiple workers with the same
/// skill and distinct `instanceIndex`.
public struct TeamWorkerSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var skillId: String
    public var purpose: TeamWorkerPurpose
    /// Activation gate: a row activates when `effort >= minEffort`.
    public var minEffort: EffortLevel
    public var preferredModelId: String?
    /// Empty means any ready model matching required capability and lane tags.
    public var allowedModelIds: [String]
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var count: Int
    public var fallbackPolicy: ModelFallbackPolicy
    /// Required rows must resolve or the team is disabled for that effort;
    /// optional rows may be disabled with a warning.
    public var required: Bool

    public init(
        id: String,
        skillId: String,
        purpose: TeamWorkerPurpose = .answer,
        minEffort: EffortLevel = .low,
        preferredModelId: String? = nil,
        allowedModelIds: [String] = [],
        requiredCapabilityTags: [ModelCapabilityTag] = [],
        count: Int = 1,
        fallbackPolicy: ModelFallbackPolicy = .strongestReady,
        required: Bool = true
    ) {
        self.id = id
        self.skillId = skillId
        self.purpose = purpose
        self.minEffort = minEffort
        self.preferredModelId = preferredModelId
        self.allowedModelIds = allowedModelIds
        self.requiredCapabilityTags = requiredCapabilityTags
        self.count = count
        self.fallbackPolicy = fallbackPolicy
        self.required = required
    }
}

// MARK: - Effort / synthesis policy

/// Effort homes for a team: default effort plus optional lane-specific output
/// count and partial-run allowance per effort. Never a forecast.
public struct TeamEffortPolicy: Codable, Sendable, Equatable {
    public var defaultEffort: EffortLevel
    public var outputCountByEffort: [EffortLevel: Int]
    public var allowPartialByEffort: [EffortLevel: Bool]

    public init(
        defaultEffort: EffortLevel = .med,
        outputCountByEffort: [EffortLevel: Int] = [:],
        allowPartialByEffort: [EffortLevel: Bool] = [:]
    ) {
        self.defaultEffort = defaultEffort
        self.outputCountByEffort = outputCountByEffort
        self.allowPartialByEffort = allowPartialByEffort
    }
}

/// The team's single **Team Lead** — the one role that reads the crew's output and
/// writes the answer that reports back. Exactly one per team, effort-independent
/// (effort scales the crew, never the Lead). Its prompt is the template of its
/// `skillId` (a `.planWriter` skill); editing that prompt forks a custom skill on
/// save like any worker. The model is picked by name (preferred, then
/// capability/lane fallback) — never "strongest" shown to the user.
public struct TeamLeadSpec: Codable, Sendable, Equatable {
    public var skillId: String
    public var preferredModelId: String?
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var fallbackPolicy: ModelFallbackPolicy
    /// How the Lead treats disagreement among the crew when it synthesizes.
    public var dissentPolicy: DissentPolicy

    public init(
        skillId: String,
        preferredModelId: String? = nil,
        requiredCapabilityTags: [ModelCapabilityTag] = [],
        fallbackPolicy: ModelFallbackPolicy = .strongestReady,
        dissentPolicy: DissentPolicy = .preserveDissent
    ) {
        self.skillId = skillId
        self.preferredModelId = preferredModelId
        self.requiredCapabilityTags = requiredCapabilityTags
        self.fallbackPolicy = fallbackPolicy
        self.dissentPolicy = dissentPolicy
    }
}

// MARK: - Lane-scoped team (catalog team)

/// A lane-scoped Fan out team — the canonical `TeamPreset` the user picks. Built-in
/// teams ship as product assets; users duplicate them to customize. Every team
/// declares exactly one lane and one `outputKind`. (The legacy council/workflow
/// panel-seat config is `PanelPreset`; see `PanelPreset.swift`.)
public struct TeamPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var lane: WorkLane
    public var description: String
    public var outputKind: TeamOutputKind
    public var defaultEffort: EffortLevel
    public var isDefaultForLane: Bool
    public var workerSpecs: [TeamWorkerSpec]
    public var effortPolicy: TeamEffortPolicy
    /// The mandatory Team Lead (synthesizer). Exactly one, effort-independent.
    public var lead: TeamLeadSpec
    public var typeTags: [String]
    public var purposeTags: [String]
    public var builtIn: Bool
    public var version: Int

    public init(
        id: String,
        displayName: String,
        lane: WorkLane,
        description: String = "",
        outputKind: TeamOutputKind,
        defaultEffort: EffortLevel = .med,
        isDefaultForLane: Bool = false,
        workerSpecs: [TeamWorkerSpec],
        effortPolicy: TeamEffortPolicy = TeamEffortPolicy(),
        lead: TeamLeadSpec,
        typeTags: [String] = [],
        purposeTags: [String] = [],
        builtIn: Bool = false,
        version: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.lane = lane
        self.description = description
        self.outputKind = outputKind
        self.defaultEffort = defaultEffort
        self.isDefaultForLane = isDefaultForLane
        self.workerSpecs = workerSpecs
        self.effortPolicy = effortPolicy
        self.lead = lead
        self.typeTags = typeTags
        self.purposeTags = purposeTags
        self.builtIn = builtIn
        self.version = version
    }

    /// Worker rows active at `effort` (those whose `minEffort <= effort`), in
    /// declared order.
    public func activeRows(at effort: EffortLevel) -> [TeamWorkerSpec] {
        workerSpecs.filter { $0.minEffort <= effort }
    }

    /// Worker count active at each effort — the catalog summary shape
    /// (answer + review rows; the synthetic writer is separate).
    public func workerCountByEffort() -> [EffortLevel: Int] {
        var out: [EffortLevel: Int] = [:]
        for effort in EffortLevel.allCases {
            out[effort] = activeRows(at: effort).reduce(0) { $0 + max(1, $1.count) }
        }
        return out
    }

    /// A custom, editable copy of this team. Built-ins are duplicate-to-edit: the
    /// copy gets a fresh id, `builtIn == false`, and is not a lane default until the
    /// user makes it one. The original (built-in) is never mutated.
    public func duplicated(newId: String, newName: String? = nil) -> TeamPreset {
        var copy = self
        copy.id = newId
        copy.displayName = newName ?? "\(displayName) (Custom)"
        copy.builtIn = false
        copy.isDefaultForLane = false
        copy.version = 1
        return copy
    }
}

// MARK: - Default-per-lane integrity

public extension Array where Element == TeamPreset {
    /// Teams in one lane.
    func teams(in lane: WorkLane) -> [TeamPreset] {
        filter { $0.lane == lane }
    }

    /// The default team for a lane: the explicit `isDefaultForLane`, else the
    /// built-in lane core team, else the first team in the lane.
    func defaultTeam(for lane: WorkLane) -> TeamPreset? {
        let inLane = teams(in: lane)
        return inLane.first { $0.isDefaultForLane }
            ?? inLane.first { $0.builtIn && $0.id == "\(lane.rawValue)_core" }
            ?? inLane.first
    }

    /// Enforces exactly one default team per non-empty lane. Returns the lanes that
    /// violate the invariant (0 or >1 defaults) — empty array means valid.
    func lanesViolatingSingleDefault() -> [WorkLane] {
        WorkLane.allCases.filter { lane in
            let inLane = teams(in: lane)
            guard !inLane.isEmpty else { return false }
            return inLane.filter(\.isDefaultForLane).count != 1
        }
    }
}

// MARK: - Team catalog API

/// Built-in and custom team definitions. Built-in ids are reserved; customs persist
/// under `Catalogs/teams/<id>.json`.
public enum TeamCatalog {
    public static var all: [TeamDefinition] {
        mergeCustom(CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.teams, as: TeamPreset.self))
    }

    public static func list(lane: WorkLane) -> [TeamDefinition] { all.teams(in: lane) }

    public static func get(_ id: TeamID) -> TeamDefinition? {
        BuiltInTeams.team(id) ?? CatalogFileIO.loadOne(id: id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self)
    }

    public static func defaultTeam(for lane: WorkLane) -> TeamDefinition? {
        let inLane = list(lane: lane)
        if let customDefault = inLane.first(where: { !$0.builtIn && $0.isDefaultForLane }) {
            return customDefault
        }
        return inLane.first { $0.isDefaultForLane }
            ?? inLane.first { $0.builtIn && $0.id == "\(lane.rawValue)_core" }
            ?? inLane.first
    }

    @discardableResult
    public static func duplicateBuiltIn(_ id: TeamID, name: String?) throws -> TeamDefinition {
        guard let source = BuiltInTeams.team(id) else { throw CatalogError.teamNotFound }
        var newId = CatalogIDGenerator.customID(lane: source.lane, displayName: name ?? source.displayName)
        while get(newId) != nil { newId = CatalogIDGenerator.customID(lane: source.lane, displayName: name ?? source.displayName, suffix: String(Int.random(in: 1000...9999))) }
        let copy = source.duplicated(newId: newId, newName: name)
        try saveCustom(copy)
        return copy
    }

    public static func saveCustom(_ team: TeamDefinition) throws {
        guard !team.builtIn else { throw CatalogError.builtInImmutable }
        if BuiltInTeams.team(team.id) != nil { throw CatalogError.idCollision }
        guard CatalogIDValidator.isValid(team.id) else { throw CatalogError.idInvalid }
        guard !team.workerSpecs.isEmpty else { throw CatalogError.teamInvalid("team must have at least one worker row") }
        for row in team.workerSpecs {
            guard let skill = SkillCatalog.get(row.skillId) else {
                throw CatalogError.teamInvalid("unknown skill \(row.skillId)")
            }
            guard skill.lane == team.lane else {
                throw CatalogError.skillLaneMismatch(skillId: row.skillId, teamId: team.id)
            }
        }
        guard let leadSkill = SkillCatalog.get(team.lead.skillId) else {
            throw CatalogError.teamInvalid("unknown Team Lead skill \(team.lead.skillId)")
        }
        guard leadSkill.lane == team.lane else {
            throw CatalogError.skillLaneMismatch(skillId: team.lead.skillId, teamId: team.id)
        }
        var custom = team
        custom.builtIn = false
        try CatalogFileIO.save(custom, id: custom.id, kind: .team, root: CatalogRoots.teams)
    }

    public static func deleteCustom(_ id: TeamID) throws {
        if BuiltInTeams.team(id) != nil { throw CatalogError.builtInImmutable }
        guard let existing = CatalogFileIO.loadOne(id: id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self) else {
            throw CatalogError.teamNotFound
        }
        if existing.isDefaultForLane {
            let remaining = list(lane: existing.lane).filter { $0.id != id }
            if remaining.defaultTeam(for: existing.lane) == nil {
                throw CatalogError.teamDefaultInvalid("deleting \(id) would leave \(existing.lane.rawValue) without a default team")
            }
        }
        try CatalogFileIO.delete(id: id, root: CatalogRoots.teams)
    }

    @discardableResult
    public static func setDefault(_ id: TeamID) throws -> TeamDefinition {
        guard let team = get(id) else { throw CatalogError.teamNotFound }
        try clearCustomDefaultFlags(in: team.lane)
        if team.builtIn { return team }
        var custom = team
        custom.isDefaultForLane = true
        try saveCustom(custom)
        return custom
    }

    private static func clearCustomDefaultFlags(in lane: WorkLane) throws {
        for var custom in CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.teams, as: TeamPreset.self) {
            guard custom.lane == lane, custom.isDefaultForLane else { continue }
            custom.isDefaultForLane = false
            try CatalogFileIO.save(custom, id: custom.id, kind: .team, root: CatalogRoots.teams)
        }
    }

    private static func mergeCustom(_ customs: [TeamPreset]) -> [TeamPreset] {
        let reserved = Set(BuiltInTeams.all.map(\.id))
        return BuiltInTeams.all + customs.filter { !reserved.contains($0.id) }
    }
}
