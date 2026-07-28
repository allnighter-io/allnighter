import Foundation

// Substitution Bench / Default-model settings (SBDS-S01). The SSOT for "Auto" and
// healthy substitution. The global default is ALWAYS Auto-on-a-tier — there is NO
// pinned concrete default. The Default-model screen, CLI, MCP, and every model
// picker render this one contract; none derives Auto/tier locally.

/// A substitution tier — the shared concept under Auto and healthy substitution.
/// A tier is a ROSTER (an ordered membership list), never a property of a model.
public enum SubstitutionTier: String, Codable, Sendable, CaseIterable {
    case frontier, balanced, economy

    public var displayName: String {
        switch self {
        case .frontier: "Frontier"
        case .balanced: "Balanced"
        case .economy: "Economy"
        }
    }

  /// Parse CLI / persisted tier ids, including legacy `flagship` and `fast`.
  public static func parse(_ raw: String) -> SubstitutionTier? {
    switch raw.lowercased() {
    case "frontier", "flagship": return .frontier
    case "balanced": return .balanced
    case "economy", "fast": return .economy
    default: return nil
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard let tier = SubstitutionTier.parse(raw) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "unknown substitution tier: \(raw)")
    }
    self = tier
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Ordered model-id membership per tier. **Index 0 of each list is that tier's
/// DEFAULT** — what Auto runs and what substitutes lead with. Membership is
/// **many-to-many**: a model may belong to any number of tiers (0–3). Putting one
/// model in all three tiers is a first-class move — it's how you soak up a plan with
/// compute to burn (e.g. a ChatGPT-max or unused-Opus month). A model in **zero**
/// tiers is **Unassigned** (hand-pickable, never used by Auto, never a substitute).
public struct TierMembership: Codable, Sendable, Equatable {
    public var frontier: [ModelID]
    public var balanced: [ModelID]
    public var economy: [ModelID]

    public init(frontier: [ModelID] = [], balanced: [ModelID] = [], economy: [ModelID] = []) {
        self.frontier = frontier
        self.balanced = balanced
        self.economy = economy
    }

    private enum CodingKeys: String, CodingKey {
        case frontier, balanced, economy
        case flagship, fast
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frontier = try c.decodeIfPresent([ModelID].self, forKey: .frontier)
            ?? c.decodeIfPresent([ModelID].self, forKey: .flagship) ?? []
        balanced = try c.decodeIfPresent([ModelID].self, forKey: .balanced) ?? []
        economy = try c.decodeIfPresent([ModelID].self, forKey: .economy)
            ?? c.decodeIfPresent([ModelID].self, forKey: .fast) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frontier, forKey: .frontier)
        try c.encode(balanced, forKey: .balanced)
        try c.encode(economy, forKey: .economy)
    }

    public subscript(_ tier: SubstitutionTier) -> [ModelID] {
        get {
            switch tier {
            case .frontier: frontier
            case .balanced: balanced
            case .economy: economy
            }
        }
        set {
            switch tier {
            case .frontier: frontier = newValue
            case .balanced: balanced = newValue
            case .economy: economy = newValue
            }
        }
    }

    /// Every tier a model belongs to, ordered Frontier → Balanced → Economy. Empty =
    /// Unassigned. (Membership is many-to-many — a model can be in several tiers.)
    public func tiers(of modelId: ModelID) -> [SubstitutionTier] {
        SubstitutionTier.allCases.filter { self[$0].contains(modelId) }
    }

    /// The highest-quality tier a model belongs to (Frontier > Balanced > Economy), or
    /// nil if Unassigned. Used to substitute a down pinned model without downgrading.
    public func highestTier(of modelId: ModelID) -> SubstitutionTier? {
        tiers(of: modelId).first
    }

    public func isUnassigned(_ modelId: ModelID) -> Bool { tiers(of: modelId).isEmpty }

    public var assignedModelIds: Set<ModelID> { Set(frontier + balanced + economy) }

    /// Add `id` to `tier` at `position` (clamped; nil = append), or move it within the
    /// tier if already present. Other tiers are untouched — membership is many-to-many.
    /// `position == 0` makes it that tier's default.
    public mutating func assign(_ id: ModelID, to tier: SubstitutionTier, position: Int? = nil) {
        var list = self[tier].filter { $0 != id }
        let idx = position.map { Swift.max(0, Swift.min($0, list.count)) } ?? list.count
        list.insert(id, at: idx)
        self[tier] = list
    }

    /// Remove `id` from one tier, or from every tier (`tier == nil`). Removing from all
    /// tiers benches the model from Auto & substitution (back to Unassigned).
    public mutating func unassign(_ id: ModelID, from tier: SubstitutionTier? = nil) {
        if let tier {
            self[tier] = self[tier].filter { $0 != id }
        } else {
            for t in SubstitutionTier.allCases { self[t] = self[t].filter { $0 != id } }
        }
    }

    /// Cleans only **intra-tier** duplicates (a model listed twice in the *same* tier
    /// — first occurrence wins). Cross-tier membership is intentionally preserved: a
    /// model may live in several tiers. Returns the cleaned membership plus the ids
    /// that were de-duplicated within a tier, for diagnostics.
    public func normalized() -> (membership: TierMembership, duplicates: [ModelID]) {
        var duplicates: [ModelID] = []
        func dedupeWithinTier(_ ids: [ModelID]) -> [ModelID] {
            var seen = Set<ModelID>()
            var out: [ModelID] = []
            for id in ids {
                if seen.contains(id) { duplicates.append(id) } else { seen.insert(id); out.append(id) }
            }
            return out
        }
        return (TierMembership(frontier: dedupeWithinTier(frontier),
                               balanced: dedupeWithinTier(balanced),
                               economy: dedupeWithinTier(economy)), duplicates)
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
        defaultTier: SubstitutionTier = .frontier,
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

    /// Fresh-install seed: ordered membership per tier across multiple CLIs so
    /// substitution always has somewhere to go even when a user has only one or two
    /// CLIs. Each tier's default (index 0) is on-by-default, so Auto works day-one.
    /// Frontier: Fable 5 + ChatGPT 5.6 Sol. Balanced starts with the
    /// medium ChatGPT 5.6 Terra seat, then orders Opus, Cursor Grok, Kimi K3,
    /// CLI Grok, Sonnet, Composer, then Gemini. Economy holds cheap/auto seats plus
    /// Kimi K2.7 Code as the low-tier Kimi fallback.
    /// Economy stays cheap/auto. Seed only — fully user-overridable.
    public static let fresh = DefaultModelSettings(
        defaultTier: .frontier,
        allowHealthySubstitutions: true,
        tiers: TierMembership(
            frontier: ["model_fable", "model_chatgpt"],
            balanced: [
                "model_chatgpt_terra", "model_opus", "model_cursor_grok_45", "model_kimi_k3",
                "model_grok", "model_sonnet", "model_cursor_composer_25", "model_gemini"
            ],
            economy: ["model_cursor_auto", "model_gemini", "model_kimi_k27"]))

    /// The tier's default model id (index 0), or nil when the tier is empty.
    public func tierDefault(_ tier: SubstitutionTier) -> ModelID? { tiers[tier].first }
}

/// Resolves Auto and healthy substitution against the tiers + ready Bench. NEVER
/// crosses tiers. Determinism comes from the user's intra-tier order, not rank.
public enum SubstitutionResolver {
    public enum BlockReason: String, Sendable, Equatable {
        /// No runnable model for the required slot → wait. Either the tier's ready
        /// members are exhausted, OR — with substitutions OFF — the tier's default model
        /// itself is down (other ready members are deliberately not used).
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
    /// team worker). Ready → run it. Down + substitutions ON + assigned → first ready
    /// model in the requested model's **highest** tier (so a down pin never
    /// downgrades, and a multi-tier model resolves deterministically). Down +
    /// substitutions OFF, or Unassigned → wait. Never crosses into a lower tier.
    public static func resolveRequested(modelId: ModelID, settings: DefaultModelSettings, readyModelIds: Set<ModelID>) -> Resolution {
        let highest = settings.tiers.highestTier(of: modelId)
        if readyModelIds.contains(modelId) {
            return Resolution(resolvedModelId: modelId, requestedModelId: modelId, substituted: false, tier: highest, blockedReason: nil)
        }
        guard settings.allowHealthySubstitutions else {
            return Resolution(resolvedModelId: nil, requestedModelId: modelId, substituted: false, tier: highest, blockedReason: .shelfEmpty)
        }
        guard let highest else {
            return Resolution(resolvedModelId: nil, requestedModelId: modelId, substituted: false, tier: nil, blockedReason: .unassigned)
        }
        if let ready = settings.tiers[highest].first(where: { readyModelIds.contains($0) }) {
            return Resolution(resolvedModelId: ready, requestedModelId: modelId, substituted: true, tier: highest, blockedReason: nil)
        }
        return Resolution(resolvedModelId: nil, requestedModelId: modelId, substituted: false, tier: highest, blockedReason: .shelfEmpty)
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

    /// Load saved settings (normalized), or the fresh seed. A MISSING file is the normal
    /// first-run path (silent seed). A PRESENT-but-undecodable file is NOT silently
    /// discarded — it's backed up to `<file>.corrupt` and a warning is emitted, so a
    /// corrupt config can't quietly wipe the user's tiers on the next save.
    public func load() -> DefaultModelSettings {
        guard let data = try? Data(contentsOf: fileURL) else { return .fresh }   // missing → seed
        guard var settings = try? CoreJSON.decode(DefaultModelSettings.self, from: data) else {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? data.write(to: backup, options: .atomic)
            FileHandle.standardError.write(Data(
                "warning: \(fileURL.lastPathComponent) is unreadable; backed up to \(backup.lastPathComponent), using defaults\n".utf8))
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
