import Foundation

// Substitution Bench / Default-model settings (SBDS-S01). The SSOT for "Auto" and
// healthy substitution. The global default is ALWAYS Auto-on-a-tier — there is NO
// pinned concrete default. The Default-model screen, CLI, MCP, and every model
// picker render this one contract; none derives Auto/tier locally.

/// A substitution tier — the shared concept under Auto and healthy substitution.
/// A tier is a ROSTER (an ordered membership list), never a property of a model.
public enum SubstitutionTier: String, Codable, Sendable, CaseIterable {
    case flagship, balanced, fast

    public var displayName: String {
        switch self {
        case .flagship: "Flagship"
        case .balanced: "Balanced"
        case .fast: "Fast"
        }
    }
}

/// Ordered model-id membership per tier. **Index 0 of each list is that tier's
/// DEFAULT** — what Auto runs and what substitutes lead with. A model absent from
/// all three lists is **Unassigned** (hand-pickable, never used by Auto, never a
/// substitute).
public struct TierMembership: Codable, Sendable, Equatable {
    public var flagship: [ModelID]
    public var balanced: [ModelID]
    public var fast: [ModelID]

    public init(flagship: [ModelID] = [], balanced: [ModelID] = [], fast: [ModelID] = []) {
        self.flagship = flagship
        self.balanced = balanced
        self.fast = fast
    }

    public subscript(_ tier: SubstitutionTier) -> [ModelID] {
        get {
            switch tier {
            case .flagship: flagship
            case .balanced: balanced
            case .fast: fast
            }
        }
        set {
            switch tier {
            case .flagship: flagship = newValue
            case .balanced: balanced = newValue
            case .fast: fast = newValue
            }
        }
    }

    /// The tier a model is assigned to, or nil if Unassigned.
    public func tier(of modelId: ModelID) -> SubstitutionTier? {
        SubstitutionTier.allCases.first { self[$0].contains(modelId) }
    }

    public var assignedModelIds: Set<ModelID> { Set(flagship + balanced + fast) }

    /// Enforces the invariant that a model appears in at most one tier and not twice
    /// within a tier — first occurrence wins. Returns the cleaned membership plus the
    /// ids that were de-duplicated, for diagnostics.
    public func normalized() -> (membership: TierMembership, duplicates: [ModelID]) {
        var seen = Set<ModelID>()
        var duplicates: [ModelID] = []
        func clean(_ ids: [ModelID]) -> [ModelID] {
            ids.filter { id in
                if seen.contains(id) { duplicates.append(id); return false }
                seen.insert(id); return true
            }
        }
        return (TierMembership(flagship: clean(flagship), balanced: clean(balanced), fast: clean(fast)), duplicates)
    }
}

/// Default-model + substitution settings (SSOT). No pinned concrete default — the
/// global default is always Auto-on-a-tier.
public struct DefaultModelSettings: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Which tier Auto draws from.
    public var defaultTier: SubstitutionTier
    /// ON: a down model falls back to another ready model on the SAME tier (across
    /// CLIs). OFF: Auto uses only the tier default and waits if it's down. Default ON
    /// (cross-CLI utilization is a product Power).
    public var allowHealthySubstitutions: Bool
    /// Ordered per-tier membership; index 0 = tier default. Unlisted = Unassigned.
    public var tiers: TierMembership
    public var updatedAt: Date?

    public init(
        schemaVersion: Int = DefaultModelSettings.currentSchemaVersion,
        defaultTier: SubstitutionTier = .flagship,
        allowHealthySubstitutions: Bool = true,
        tiers: TierMembership = TierMembership(),
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.defaultTier = defaultTier
        self.allowHealthySubstitutions = allowHealthySubstitutions
        self.tiers = tiers
        self.updatedAt = updatedAt
    }

    /// Fresh-install seed: a FEW sensible models tiered (so Auto-on-Flagship works on
    /// day 1), everything else Unassigned. Seed only — fully user-overridable; the
    /// intra-tier order is the default order (index 0 runs first).
    public static let fresh = DefaultModelSettings(
        defaultTier: .flagship,
        allowHealthySubstitutions: true,
        tiers: TierMembership(
            flagship: ["model_opus", "model_chatgpt"],
            balanced: ["model_sonnet"],
            fast: ["model_gemini"]))

    /// The tier's default model id (index 0), or nil when the tier is empty.
    public func tierDefault(_ tier: SubstitutionTier) -> ModelID? { tiers[tier].first }
}

/// Resolves Auto and healthy substitution against the tiers + ready Bench. NEVER
/// crosses tiers. Determinism comes from the user's intra-tier order, not rank.
public enum SubstitutionResolver {
    public enum BlockReason: String, Sendable, Equatable {
        /// The required tier has assigned models, but none is ready → wait.
        case shelfEmpty
        /// The required tier has no assigned models at all → wait.
        case tierEmpty
        /// The requested model is Unassigned and down → no substitution, wait.
        case unassigned
    }

    public struct Resolution: Sendable, Equatable {
        public var resolvedModelId: ModelID?   // nil = wait
        public var requestedModelId: ModelID?
        public var substituted: Bool
        public var tier: SubstitutionTier?
        public var blockedReason: BlockReason?
        public var isBlocked: Bool { resolvedModelId == nil }
    }

    /// What Auto resolves to for the default tier.
    /// - substitutions OFF: the tier DEFAULT (index 0) if ready; else wait.
    /// - substitutions ON:  the first READY model in tier order; else wait.
    public static func resolveAuto(settings: DefaultModelSettings, readyModelIds: Set<ModelID>) -> Resolution {
        let tier = settings.defaultTier
        let members = settings.tiers[tier]
        guard let tierDefault = members.first else {
            return Resolution(resolvedModelId: nil, requestedModelId: nil, substituted: false, tier: tier, blockedReason: .tierEmpty)
        }
        if settings.allowHealthySubstitutions {
            if let ready = members.first(where: { readyModelIds.contains($0) }) {
                return Resolution(resolvedModelId: ready, requestedModelId: tierDefault,
                                  substituted: ready != tierDefault, tier: tier, blockedReason: nil)
            }
            return Resolution(resolvedModelId: nil, requestedModelId: tierDefault, substituted: false, tier: tier, blockedReason: .shelfEmpty)
        }
        if readyModelIds.contains(tierDefault) {
            return Resolution(resolvedModelId: tierDefault, requestedModelId: tierDefault, substituted: false, tier: tier, blockedReason: nil)
        }
        return Resolution(resolvedModelId: nil, requestedModelId: tierDefault, substituted: false, tier: tier, blockedReason: .shelfEmpty)
    }

    /// Healthy substitution for an explicitly-requested model (a per-chat pick or a
    /// team worker). Ready → run it. Down + substitutions ON + in a tier → first
    /// ready model in that SAME tier. Down + substitutions OFF, or Unassigned →
    /// wait. Never crosses tiers/shelves.
    public static func resolveRequested(modelId: ModelID, settings: DefaultModelSettings, readyModelIds: Set<ModelID>) -> Resolution {
        let tier = settings.tiers.tier(of: modelId)
        if readyModelIds.contains(modelId) {
            return Resolution(resolvedModelId: modelId, requestedModelId: modelId, substituted: false, tier: tier, blockedReason: nil)
        }
        guard settings.allowHealthySubstitutions else {
            return Resolution(resolvedModelId: nil, requestedModelId: modelId, substituted: false, tier: tier, blockedReason: .shelfEmpty)
        }
        guard let tier else {
            return Resolution(resolvedModelId: nil, requestedModelId: modelId, substituted: false, tier: nil, blockedReason: .unassigned)
        }
        if let ready = settings.tiers[tier].first(where: { readyModelIds.contains($0) }) {
            return Resolution(resolvedModelId: ready, requestedModelId: modelId, substituted: true, tier: tier, blockedReason: nil)
        }
        return Resolution(resolvedModelId: nil, requestedModelId: modelId, substituted: false, tier: tier, blockedReason: .shelfEmpty)
    }
}

/// Persists `DefaultModelSettings` to `Config/default_model_settings.json`. IO is
/// behind a plain persistence helper (no public "Store" vocabulary, per the SSOT
/// directive). Load returns the fresh seed when no file exists.
public struct DefaultModelSettingsPersistence {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ModelCatalogPaths.config.appendingPathComponent("default_model_settings.json")
    }

    /// Load saved settings (normalized) or the fresh-install seed when absent/unreadable.
    public func load() -> DefaultModelSettings {
        guard let data = try? Data(contentsOf: fileURL),
              var settings = try? CoreJSON.decode(DefaultModelSettings.self, from: data) else {
            return .fresh
        }
        settings.tiers = settings.tiers.normalized().membership
        return settings
    }

    public func save(_ settings: DefaultModelSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var settings = settings
        settings.tiers = settings.tiers.normalized().membership
        settings.updatedAt = Date()
        try CoreJSON.encode(settings).write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func reset() throws -> DefaultModelSettings {
        try save(.fresh)
        return load()
    }
}
