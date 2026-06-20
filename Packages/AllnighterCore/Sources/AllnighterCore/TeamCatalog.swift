import Foundation

// MARK: - Catalog identifiers

/// Stable machine identifier for one team definition (global namespace across lanes).
public typealias TeamID = String

/// Stable machine identifier for one skill definition (global namespace across lanes).
public typealias SkillID = String

/// Catalog entry for one built-in or custom lane team (`TeamPreset` is the persisted shape).
public typealias TeamDefinition = TeamPreset

// MARK: - Team lane / effort / output

/// The four peer crafts (public families). A team always declares an explicit
/// craft — Allnighter never infers it from the prompt. `signal` is the
/// outside-world scout craft: it runs on the SAME team-run substrate as the
/// creation crafts, it is not a second system (see
/// `docs/phases/Team_Delegation_Surface.md`). The public UX calls these
/// "families"; the backend calls one a `WorkLane`/craft.
public enum WorkLane: String, Codable, Sendable, CaseIterable {
    case code
    case design
    case copy
    case signal
}

/// The model's reasoning level for a run. Canonical machine values are
/// `low | med | high` (no `medium`, never `quick/standard/deep`). Effort sets each
/// worker model's reasoning effort where the source supports it; it NEVER changes
/// worker count, review depth, or team shape — a bigger pass is a different (named)
/// team. Never a runtime/cost forecast.
public enum EffortLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case med
    case high

    /// Ordering for display/comparison only (low < med < high). Effort never gates
    /// worker activation.
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
/// generic code plan and a Design/Copy board never pretends to be a plan.
public enum TeamOutputKind: String, Codable, Sendable, CaseIterable {
    case plan
    case bugPacket
    case securityRegister
    case architectureVerdict
    case proofPacket
    case designBoard
    case polishBoard
    case copyBoard
    /// Signal craft output: a Project-aware interpretation of outside-world signal
    /// with source receipts, freshness, skeptic pass, and recommended next actions
    /// (the typed `SignalInsight`, not a generic plan).
    case insight
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
    public var preferredModelId: String?
    /// Empty means any ready model matching required capability and lane tags.
    public var allowedModelIds: [String]
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var count: Int
    public var fallbackPolicy: ModelFallbackPolicy
    /// Required rows must resolve or the team is disabled for that effort;
    /// optional rows may be disabled with a warning.
    public var required: Bool
    /// When true, this row's `count` workers are spread across **distinct CLI
    /// drivers** (triangulation) instead of `count` instances of one model — so a
    /// signal is read by several different minds. Workers prefer cheaper models
    /// (the strongest is reserved for the Lead); if fewer distinct drivers are
    /// ready than `count`, the resolver returns what it can and warns (never
    /// silently collapses to one mind).
    public var triangulate: Bool
    /// Ordered model-id preference for triangulation fill (e.g. Grok, GPT, Gemini).
    /// Present-and-ready ids are taken first, in order; remaining slots fill from
    /// the ready bench cheapest-first. Ignored when `triangulate == false`.
    public var triangulatePreferenceIds: [String]

    public init(
        id: String,
        skillId: String,
        purpose: TeamWorkerPurpose = .answer,
        preferredModelId: String? = nil,
        allowedModelIds: [String] = [],
        requiredCapabilityTags: [ModelCapabilityTag] = [],
        count: Int = 1,
        fallbackPolicy: ModelFallbackPolicy = .strongestReady,
        required: Bool = true,
        triangulate: Bool = false,
        triangulatePreferenceIds: [String] = []
    ) {
        self.id = id
        self.skillId = skillId
        self.purpose = purpose
        self.preferredModelId = preferredModelId
        self.allowedModelIds = allowedModelIds
        self.requiredCapabilityTags = requiredCapabilityTags
        self.count = count
        self.fallbackPolicy = fallbackPolicy
        self.required = required
        self.triangulate = triangulate
        self.triangulatePreferenceIds = triangulatePreferenceIds
    }
}

// MARK: - Team Lead

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

/// A saved team preset the user can pick for a run. Built-in teams ship as
/// product assets; users duplicate them to customize. Every team declares
/// exactly one lane and one `outputKind`.
public struct TeamPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var lane: WorkLane
    public var description: String
    public var outputKind: TeamOutputKind
    /// Whether running this team can make real changes (write files, post
    /// externally, edit state). Mutating teams run exactly one worker under the
    /// repo-root write lock; non-mutating teams can run read-only workers in parallel.
    public var mutating: Bool
    /// For source-scoped execution teams, the single CLI driver this team runs on.
    public var executionSourceId: String?
    public var defaultEffort: EffortLevel
    public var isDefaultForLane: Bool
    public var workerSpecs: [TeamWorkerSpec]
    /// The mandatory Team Lead (synthesizer). Exactly one.
    public var lead: TeamLeadSpec
    public var typeTags: [String]
    public var purposeTags: [String]
    /// Best-shot example prompts to seed the composer on the Send-to-team card.
    /// Placeholder product copy — refined before release. Additive (default empty).
    public var starterPrompts: [String]
    public var builtIn: Bool
    public var version: Int

    public init(
        id: String,
        displayName: String,
        lane: WorkLane,
        description: String = "",
        outputKind: TeamOutputKind,
        mutating: Bool = false,
        executionSourceId: String? = nil,
        defaultEffort: EffortLevel = .med,
        isDefaultForLane: Bool = false,
        workerSpecs: [TeamWorkerSpec],
        lead: TeamLeadSpec,
        typeTags: [String] = [],
        purposeTags: [String] = [],
        starterPrompts: [String] = [],
        builtIn: Bool = false,
        version: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.lane = lane
        self.description = description
        self.outputKind = outputKind
        self.mutating = mutating
        self.executionSourceId = executionSourceId
        self.defaultEffort = defaultEffort
        self.isDefaultForLane = isDefaultForLane
        self.workerSpecs = workerSpecs
        self.lead = lead
        self.typeTags = typeTags
        self.purposeTags = purposeTags
        self.starterPrompts = starterPrompts
        self.builtIn = builtIn
        self.version = version
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

    /// The global default for `alln run` and default chat — one worker, mutating-allowed.
    public static func defaultRunTeam() -> TeamDefinition? {
        if let custom = CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.teams, as: TeamPreset.self)
            .first(where: { $0.id == "default_chat" && !$0.builtIn }) {
            return custom
        }
        return BuiltInTeams.defaultChat
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

    /// A fresh, collision-free custom team id for a lane — used when creating a
    /// brand-new team (Add team) rather than duplicating an existing one.
    public static func freshCustomId(lane: WorkLane, displayName: String) -> TeamID {
        var newId = CatalogIDGenerator.customID(lane: lane, displayName: displayName)
        while get(newId) != nil {
            newId = CatalogIDGenerator.customID(lane: lane, displayName: displayName, suffix: String(Int.random(in: 1000...9999)))
        }
        return newId
    }

    public static func saveCustom(_ team: TeamDefinition) throws {
        guard !team.builtIn else { throw CatalogError.builtInImmutable }
        if BuiltInTeams.team(team.id) != nil { throw CatalogError.idCollision }
        guard CatalogIDValidator.isValid(team.id) else { throw CatalogError.idInvalid }
        guard !team.workerSpecs.isEmpty else { throw CatalogError.teamInvalid("team must have at least one worker row") }
        if team.mutating {
            guard team.workerSpecs.count == 1, team.workerSpecs.first?.count == 1 else {
                throw CatalogError.teamInvalid("mutating teams run exactly one worker")
            }
        }
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
        try validateExecutionSourceGate(team)
        var custom = team
        custom.builtIn = false
        try CatalogFileIO.save(custom, id: custom.id, kind: .team, root: CatalogRoots.teams)
    }

    /// Reject custom mutating teams whose resolved workers cross CLI sources.
    public static func validateExecutionSourceGate(_ team: TeamPreset) throws {
        guard team.mutating else { return }
        let bench = catalogBenchModels()
        let resolved = TeamResolver.resolve(
            team: team, requestLane: team.lane, requestEffort: team.defaultEffort, readyModels: bench)
        let gate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: bench)
        if let blocker = gate.sourceGateBlocker {
            throw CatalogError.teamInvalid(blocker.message)
        }
    }

    private static func catalogBenchModels() -> [Model] {
        ModelCatalog.list().map {
            Model(id: $0.id, displayName: $0.displayName, modelLabel: $0.modelLabel,
                  driverId: $0.driverId, role: $0.role, enabled: true)
        }
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
