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

/// How a model is selected for the synthetic plan/output writer (preferred, then
/// capability-filtered fallback by rank).
public struct ModelSelectionPolicy: Codable, Sendable, Equatable {
    public var preferredModelId: String?
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var fallbackPolicy: ModelFallbackPolicy

    public init(
        preferredModelId: String? = nil,
        requiredCapabilityTags: [ModelCapabilityTag] = [],
        fallbackPolicy: ModelFallbackPolicy = .strongestReady
    ) {
        self.preferredModelId = preferredModelId
        self.requiredCapabilityTags = requiredCapabilityTags
        self.fallbackPolicy = fallbackPolicy
    }
}

/// The synthetic plan/output writer stage for one effort: which skill writes the
/// output, how its model is selected, analysis depth, and how dissent is kept.
public struct TeamSynthesisPolicy: Codable, Sendable, Equatable {
    public var outputKind: TeamOutputKind
    public var planWriterSkillId: String
    public var modelPolicy: ModelSelectionPolicy
    public var analysisDepth: AnalysisDepth
    public var dissentPolicy: DissentPolicy

    public init(
        outputKind: TeamOutputKind,
        planWriterSkillId: String,
        modelPolicy: ModelSelectionPolicy = ModelSelectionPolicy(),
        analysisDepth: AnalysisDepth = .combined,
        dissentPolicy: DissentPolicy = .preserveDissent
    ) {
        self.outputKind = outputKind
        self.planWriterSkillId = planWriterSkillId
        self.modelPolicy = modelPolicy
        self.analysisDepth = analysisDepth
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
    public var synthesisPolicyByEffort: [EffortLevel: TeamSynthesisPolicy]
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
        synthesisPolicyByEffort: [EffortLevel: TeamSynthesisPolicy] = [:],
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
        self.synthesisPolicyByEffort = synthesisPolicyByEffort
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

    /// The synthesis policy for `effort`, falling back to the nearest lower effort
    /// that defines one, then any defined policy.
    public func synthesisPolicy(at effort: EffortLevel) -> TeamSynthesisPolicy? {
        if let exact = synthesisPolicyByEffort[effort] { return exact }
        for level in EffortLevel.allCases.sorted(by: >) where level <= effort {
            if let p = synthesisPolicyByEffort[level] { return p }
        }
        // No lower match — return the lowest defined policy so a team with one
        // shared policy still resolves at every effort.
        return EffortLevel.allCases.compactMap { synthesisPolicyByEffort[$0] }.first
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
