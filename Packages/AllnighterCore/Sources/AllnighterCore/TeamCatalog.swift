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
// EffortLevel moved to AgentOSCLI (AgentOS runtime seam, roadmap P1.2); it
// resolves here via `@_exported import AgentOSCLI` in AgentOSReexports.swift.

/// What a team produces. `outputKind` chooses the synthesis profile, result
/// renderer, and default stage shape so a Security Review is never forced into a
/// generic code plan and a Design/Copy board never pretends to be a plan.
public enum TeamOutputKind: String, Codable, Sendable, CaseIterable {
    case plan
    case bugPacket
    case securityRegister
    case specReview
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
    /// Ordered cross-source substitutes tried after `preferredModelId` and before
    /// the broad fallback policy. `nil` preserves catalogs written before ordered
    /// fallback chains shipped.
    public var fallbackModelIds: [String]?
    /// Empty means any ready model matching required capability and lane tags.
    public var allowedModelIds: [String]
    public var requiredCapabilityTags: [ModelCapabilityTag]
    /// Optional capability tags that REORDER candidates within a caliber band
    /// (CN-S06 / Law 3): among ready candidates of the same caliber, one carrying
    /// ALL of these sorts ahead of one that doesn't. This NEVER filters (a row
    /// still resolves whenever it resolves today) and NEVER lets a lower-caliber
    /// specialist displace a higher-caliber generalist — it is a pure tie-break
    /// within equal rank. Empty means no preference; resolution is byte-identical
    /// to a run without it. Decode-tolerant: catalogs persisted before this field
    /// shipped decode as empty.
    public var preferredCapabilityTags: [ModelCapabilityTag]
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
        fallbackModelIds: [String]? = nil,
        allowedModelIds: [String] = [],
        requiredCapabilityTags: [ModelCapabilityTag] = [],
        preferredCapabilityTags: [ModelCapabilityTag] = [],
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
        self.fallbackModelIds = fallbackModelIds
        self.allowedModelIds = allowedModelIds
        self.requiredCapabilityTags = requiredCapabilityTags
        self.preferredCapabilityTags = preferredCapabilityTags
        self.count = count
        self.fallbackPolicy = fallbackPolicy
        self.required = required
        self.triangulate = triangulate
        self.triangulatePreferenceIds = triangulatePreferenceIds
    }

    // Custom Codable so catalogs persisted before `preferredCapabilityTags`
    // shipped still decode (the field defaults to empty). Every other field keeps
    // its prior strictness — only the already-optional identity substitutes and
    // the new preference key are decode-tolerant, matching the struct's existing
    // pattern (`fallbackModelIds` was optional for the same reason).
    private enum CodingKeys: String, CodingKey {
        case id, skillId, purpose, preferredModelId, fallbackModelIds, allowedModelIds
        case requiredCapabilityTags, preferredCapabilityTags, count, fallbackPolicy
        case required, triangulate, triangulatePreferenceIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        skillId = try c.decode(String.self, forKey: .skillId)
        purpose = try c.decode(TeamWorkerPurpose.self, forKey: .purpose)
        preferredModelId = try c.decodeIfPresent(String.self, forKey: .preferredModelId)
        fallbackModelIds = try c.decodeIfPresent([String].self, forKey: .fallbackModelIds)
        allowedModelIds = try c.decode([String].self, forKey: .allowedModelIds)
        requiredCapabilityTags = try c.decode([ModelCapabilityTag].self, forKey: .requiredCapabilityTags)
        preferredCapabilityTags = try c.decodeIfPresent([ModelCapabilityTag].self, forKey: .preferredCapabilityTags) ?? []
        count = try c.decode(Int.self, forKey: .count)
        fallbackPolicy = try c.decode(ModelFallbackPolicy.self, forKey: .fallbackPolicy)
        required = try c.decode(Bool.self, forKey: .required)
        triangulate = try c.decode(Bool.self, forKey: .triangulate)
        triangulatePreferenceIds = try c.decode([String].self, forKey: .triangulatePreferenceIds)
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
    /// Ordered cross-source substitutes tried before rank-based fallback.
    /// Optional so existing saved team catalogs continue to decode.
    public var fallbackModelIds: [String]?
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var fallbackPolicy: ModelFallbackPolicy
    /// How the Lead treats disagreement among the crew when it synthesizes.
    public var dissentPolicy: DissentPolicy

    public init(
        skillId: String,
        preferredModelId: String? = nil,
        fallbackModelIds: [String]? = nil,
        requiredCapabilityTags: [ModelCapabilityTag] = [],
        fallbackPolicy: ModelFallbackPolicy = .strongestReady,
        dissentPolicy: DissentPolicy = .preserveDissent
    ) {
        self.skillId = skillId
        self.preferredModelId = preferredModelId
        self.fallbackModelIds = fallbackModelIds
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
    /// Optional Stage-0 scout that runs FIRST and distills the raw source (e.g. an
    /// X-capable model grabbing a post's content) into neutral context the rest of
    /// the team reads. nil = no scout (the team reads the prompt directly). Used by
    /// Signal teams so workers reason over the same distilled source.
    public var scout: TeamWorkerSpec?
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
        scout: TeamWorkerSpec? = nil,
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
        self.scout = scout
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

    /// Team-lab experiment teams carry `typeTags` containing `"lab"`. Hidden from
    /// Send-to-team and Team Studio browse; never promoted without founder review.
    public var isLabTeam: Bool { typeTags.contains(Self.labTypeTag) }

    public static let labTypeTag = "lab"

    /// Advertised seat count for catalog/list/show/menu (SH-S06 / Law 8): scout
    /// (0|1) + Σ crew-row `count` (row multiplicity) + Team Lead. Matches the
    /// structural seats preflight expands when every row resolves. One truth;
    /// do not re-derive at call sites. Public field name is `seatCount`.
    public var catalogSeatCount: Int {
        let scoutSeats = scout == nil ? 0 : 1
        let crewSeats = workerSpecs.reduce(0) { $0 + max(1, $1.count) }
        return scoutSeats + crewSeats + 1
    }
}

// MARK: - Default-per-lane integrity

public extension Array where Element == TeamPreset {
    /// Teams in one lane.
    func teams(in lane: WorkLane) -> [TeamPreset] {
        filter { $0.lane == lane }
    }

    /// The default team for a lane: the explicit `isDefaultForLane`, else the
    /// first team in the lane. (`isDefaultForLane` + the single-default invariant
    /// own lane defaults now — the old `"<lane>_core"` fallback is dead post-rename.)
    func defaultTeam(for lane: WorkLane) -> TeamPreset? {
        let inLane = teams(in: lane)
        return inLane.first { $0.isDefaultForLane }
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
/// under `Catalogs/teams/<id>.json`. Lab experiment teams (`typeTags` contains `"lab"`)
/// never live in the product catalog — they are redirected to `Catalogs/lab-teams/`
/// (AE-S02 / Law 7).
public enum TeamCatalog {
    public static var all: [TeamDefinition] {
        migrateStrayLabTeamsFromProductCatalog()
        return mergeCustom(CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.teams, as: TeamPreset.self))
    }

    public static func list(lane: WorkLane) -> [TeamDefinition] { all.teams(in: lane) }

    public static func get(_ id: TeamID) -> TeamDefinition? {
        migrateStrayLabTeamsFromProductCatalog()
        // A saved file ALWAYS wins — for a built-in id that's the user's edited version
        // (the "override"); the shipped team stays hidden as the restore source. So
        // editing any team edits it in place; there is never a duplicate "(custom)" row.
        if let file = CatalogFileIO.loadOne(id: id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self) {
            let normalized = normalizedOverride(file)
            // Stray lab copies must not remain in the product root.
            if normalized.isLabTeam {
                try? LabTeamCatalog.save(normalized)
                try? CatalogFileIO.delete(id: id, root: CatalogRoots.teams)
                return LabTeamCatalog.get(id) ?? normalized
            }
            return normalized
        }
        if let lab = LabTeamCatalog.get(id) { return lab }
        return BuiltInTeams.team(id)
    }

    /// A saved file with a built-in id is the user's edited version of that team. Force
    /// `builtIn = false` so every reader treats it as editable-with-restore, never as the
    /// immutable seed.
    private static func normalizedOverride(_ team: TeamPreset) -> TeamPreset {
        guard BuiltInTeams.team(team.id) != nil else { return team }
        var t = team
        t.builtIn = false
        return t
    }

    /// True when `id` is a built-in team the user has edited (a saved file masks the seed),
    /// so a Restore affordance should appear.
    public static func hasOverride(_ id: TeamID) -> Bool {
        guard BuiltInTeams.team(id) != nil else { return false }
        return CatalogFileIO.loadOne(id: id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self) != nil
    }

    /// Restore a built-in team to its shipped seed by removing the user's edited version.
    /// Idempotent: returns the effective team and whether an edit was actually removed.
    @discardableResult
    public static func restore(_ id: TeamID) throws -> (team: TeamDefinition, removedOverride: Bool) {
        guard BuiltInTeams.team(id) != nil else { throw CatalogError.restoreUnsupported }
        let had = hasOverride(id)
        if had { try CatalogFileIO.delete(id: id, root: CatalogRoots.teams) }
        guard let team = get(id) else { throw CatalogError.teamNotFound }
        return (team, had)
    }

    public static func defaultTeam(for lane: WorkLane) -> TeamDefinition? {
        let inLane = list(lane: lane)
        if let customDefault = inLane.first(where: { !$0.builtIn && $0.isDefaultForLane }) {
            return customDefault
        }
        return inLane.first { $0.isDefaultForLane }
            ?? inLane.first
    }

    /// The global default for `alln run` and default chat — one worker, mutating-allowed.
    /// Resolves through the same effective lookup as everything else (edit wins, else seed).
    public static func defaultRunTeam() -> TeamDefinition? {
        get("default_chat") ?? BuiltInTeams.defaultChat
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
        // AE-S02 / Law 7: lab teams never enter the product catalog. Match on
        // `typeTags` containing `"lab"` (not id prefix — `code_core` is lab-tagged).
        if team.isLabTeam {
            try LabTeamCatalog.save(team)
            if CatalogFileIO.loadOne(id: team.id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self) != nil {
                try? CatalogFileIO.delete(id: team.id, root: CatalogRoots.teams)
            }
            return
        }
        // Any team saves in place. A built-in id writes the user's edited version (the
        // "override") at that same id — no duplicate. A new id is an ordinary custom team.
        let editsBuiltIn = BuiltInTeams.team(team.id) != nil
        if !editsBuiltIn {
            guard CatalogIDValidator.isValid(team.id) else { throw CatalogError.idInvalid }
        }
        guard !team.workerSpecs.isEmpty else { throw CatalogError.teamInvalid("team must have at least one worker row") }
        // Cap description so custom-team menu fallbacks stay bounded.
        let descriptionBound = MenuSelectionCopy.useWhenMax * 8
        if team.description.count > descriptionBound {
            throw CatalogError.teamInvalid(
                "description length \(team.description.count) exceeds selection metadata bound \(descriptionBound)"
            )
        }
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
        // Deleting a built-in just restores its shipped seed (removes the user's edit).
        // With no edit present there is nothing to delete — the product team stays.
        if BuiltInTeams.team(id) != nil {
            guard hasOverride(id) else { throw CatalogError.builtInImmutable }
            try CatalogFileIO.delete(id: id, root: CatalogRoots.teams)
            return
        }
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
        // An edited built-in REPLACES its seed in place (shipped order preserved), so each
        // built-in id appears exactly once — edited version or seed, never both. Ordinary
        // custom teams (non-built-in ids) follow. Lab-tagged customs are never product.
        let overridesById = Dictionary(
            customs.compactMap { BuiltInTeams.team($0.id) != nil && !$0.isLabTeam ? ($0.id, normalizedOverride($0)) : nil },
            uniquingKeysWith: { first, _ in first })
        let merged = BuiltInTeams.all.map { overridesById[$0.id] ?? $0 }
        let builtInIds = Set(BuiltInTeams.all.map(\.id))
        let ordinaryCustoms = customs.filter { !builtInIds.contains($0.id) && !$0.isLabTeam }
        return merged + ordinaryCustoms
    }

    /// Move any lab-tagged files that landed in the product `Catalogs/teams/` root
    /// into lab storage. Idempotent. Match on `typeTags`, never id prefix (AE-S02).
    private static func migrateStrayLabTeamsFromProductCatalog() {
        let strays = CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.teams, as: TeamPreset.self)
            .filter(\.isLabTeam)
        guard !strays.isEmpty else { return }
        for team in strays {
            try? LabTeamCatalog.save(team)
            try? CatalogFileIO.delete(id: team.id, root: CatalogRoots.teams)
        }
    }
}

// MARK: - Lab team storage (AE-S02)

/// Team Lab experiment teams. Champions and candidates live here (and under
/// `docs/team-lab/champions/`), never in the product `TeamCatalog` list.
public enum LabTeamCatalog {
    public static var all: [TeamDefinition] {
        CatalogFileIO.loadAll(kind: .team, root: CatalogRoots.labTeams, as: TeamPreset.self)
    }

    public static func get(_ id: TeamID) -> TeamDefinition? {
        CatalogFileIO.loadOne(id: id, kind: .team, root: CatalogRoots.labTeams, as: TeamPreset.self)
    }

    public static func save(_ team: TeamDefinition) throws {
        guard team.isLabTeam else {
            throw CatalogError.teamInvalid("lab storage requires typeTags to include \"\(TeamPreset.labTypeTag)\"")
        }
        guard CatalogIDValidator.isValid(team.id) else {
            throw CatalogError.idInvalid
        }
        guard !team.workerSpecs.isEmpty else {
            throw CatalogError.teamInvalid("team must have at least one worker row")
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
        var custom = team
        custom.builtIn = false
        custom.isDefaultForLane = false
        try CatalogFileIO.save(custom, id: custom.id, kind: .team, root: CatalogRoots.labTeams)
    }

    public static func delete(_ id: TeamID) throws {
        guard get(id) != nil else { throw CatalogError.teamNotFound }
        try CatalogFileIO.delete(id: id, root: CatalogRoots.labTeams)
    }
}
