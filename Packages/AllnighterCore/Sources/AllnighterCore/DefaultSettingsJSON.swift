import Foundation

/// Public CLI/MCP contract for `alln defaults …` (Default model & Substitutions).
/// One projection the CLI, MCP, and the Mac "Default model" screen all render — none
/// derives Auto/tier/readiness locally. Carries LIVE readiness so `auto` always shows
/// what Auto resolves to right now.
public struct DefaultSettingsJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    /// Which tier Auto draws from.
    public var defaultTier: String
    public var allowHealthySubstitutions: Bool
    /// Always three views, ordered Frontier → Balanced → Economy.
    public var tiers: [TierView]
    /// On (available) models in zero tiers — hand-pickable, never used by Auto.
    public var unassigned: [ModelRef]
    /// What Auto resolves to against current readiness.
    public var auto: AutoResolution

    public struct ModelRef: Codable, Sendable, Equatable {
        public var id: ModelID
        public var displayName: String
        public var driverId: String
        public var driverName: String
        /// On-bench AND its source is ready (a runnable substitute right now).
        public var ready: Bool
        /// On-bench (turned on in CLI Setup). A tier member that's off shows here as a
        /// potential substitute — enable it to make it live.
        public var enabled: Bool
        /// True only when this ref is the index-0 model of the tier it's listed under.
        public var isTierDefault: Bool
        /// Every tier this model belongs to (membership is many-to-many).
        public var tiers: [String]

        public init(id: ModelID, displayName: String, driverId: String, driverName: String,
                    ready: Bool, enabled: Bool, isTierDefault: Bool, tiers: [String]) {
            self.id = id; self.displayName = displayName; self.driverId = driverId
            self.driverName = driverName; self.ready = ready; self.enabled = enabled
            self.isTierDefault = isTierDefault; self.tiers = tiers
        }
    }

    public struct TierView: Codable, Sendable, Equatable {
        public var tier: String
        public var displayName: String
        /// True when this tier == defaultTier (the Auto badge lives here).
        public var isDefaultTier: Bool
        /// Index-0 model id, or nil when the tier is empty.
        public var defaultModelId: ModelID?
        /// Ordered members; index 0 is the tier default.
        public var members: [ModelRef]
        public var readyCount: Int
        /// members.count - 1 (how many can stand in for the default).
        public var substituteCount: Int

        public init(tier: String, displayName: String, isDefaultTier: Bool,
                    defaultModelId: ModelID?, members: [ModelRef], readyCount: Int, substituteCount: Int) {
            self.tier = tier; self.displayName = displayName; self.isDefaultTier = isDefaultTier
            self.defaultModelId = defaultModelId; self.members = members
            self.readyCount = readyCount; self.substituteCount = substituteCount
        }
    }

    public struct AutoResolution: Codable, Sendable, Equatable {
        public var tier: String
        public var resolvedModelId: ModelID?
        public var resolvedModelName: String?
        /// True when Auto fell back from the tier default to another ready member.
        public var substituted: Bool
        /// True when nothing in the tier is ready (or the tier is empty) → chat waits.
        public var blocked: Bool
        public var blockedReason: String?
        /// Owner-facing one-liner for the empty/wait state, e.g. "No model on Frontier — waits".
        public var waitsMessage: String?

        public init(tier: String, resolvedModelId: ModelID?, resolvedModelName: String?,
                    substituted: Bool, blocked: Bool, blockedReason: String?, waitsMessage: String?) {
            self.tier = tier; self.resolvedModelId = resolvedModelId; self.resolvedModelName = resolvedModelName
            self.substituted = substituted; self.blocked = blocked
            self.blockedReason = blockedReason; self.waitsMessage = waitsMessage
        }
    }

    public init(schemaVersion: Int = 1, contractVersion: String, defaultTier: String,
                allowHealthySubstitutions: Bool, tiers: [TierView], unassigned: [ModelRef], auto: AutoResolution) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.defaultTier = defaultTier; self.allowHealthySubstitutions = allowHealthySubstitutions
        self.tiers = tiers; self.unassigned = unassigned; self.auto = auto
    }
}

/// Pure builder: `DefaultModelSettings` + the live model list → the rendered contract.
/// No IO; CLI and MCP gather the inputs and call this so both project identically.
public enum DefaultSettingsProjector {
    public static func build(
        settings: DefaultModelSettings,
        models: [ModelListJSON.Entry],
        contractVersion: String
    ) -> DefaultSettingsJSON {
        let byId = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // "Live" = a runnable substitute right now: ON the Bench AND its source ready.
        // Upstream `ready` only means the driver is installed/signed-in (independent of
        // enablement), so an OFF model with a ready driver must NOT count — otherwise
        // Auto/substitution could resolve to a model the user turned off.
        func isLive(_ e: ModelListJSON.Entry) -> Bool { e.ready && e.enabled }
        let readyIds = Set(models.filter(isLive).map(\.id))

        func ref(_ id: ModelID, isTierDefault: Bool) -> DefaultSettingsJSON.ModelRef? {
            guard let e = byId[id] else { return nil }   // stale id (deleted custom) — drop
            return DefaultSettingsJSON.ModelRef(
                id: e.id,
                displayName: ModelDisplayName.format(
                    baseName: e.displayName, modelId: e.id, driverId: e.driverId),
                driverId: e.driverId, driverName: e.driverName,
                ready: isLive(e), enabled: e.enabled, isTierDefault: isTierDefault,
                tiers: settings.tiers.tiers(of: id).map(\.rawValue))
        }

        let tierViews: [DefaultSettingsJSON.TierView] = SubstitutionTier.allCases.map { tier in
            let ids = settings.tiers[tier]
            let members = ids.enumerated().compactMap { ref($0.element, isTierDefault: $0.offset == 0) }
            return DefaultSettingsJSON.TierView(
                tier: tier.rawValue, displayName: tier.displayName,
                isDefaultTier: tier == settings.defaultTier,
                defaultModelId: members.first?.id,
                members: members,
                readyCount: members.filter(\.ready).count,
                substituteCount: max(0, members.count - 1))
        }

        let unassigned = models
            .filter { $0.enabled && settings.tiers.isUnassigned($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { e in
                DefaultSettingsJSON.ModelRef(
                    id: e.id,
                    displayName: ModelDisplayName.format(
                        baseName: e.displayName, modelId: e.id, driverId: e.driverId),
                    driverId: e.driverId, driverName: e.driverName,
                    ready: isLive(e), enabled: e.enabled, isTierDefault: false, tiers: [])
            }

        let r = SubstitutionResolver.resolveAuto(settings: settings, readyModelIds: readyIds)
        let auto = DefaultSettingsJSON.AutoResolution(
            tier: settings.defaultTier.rawValue,
            resolvedModelId: r.resolvedModelId,
            resolvedModelName: r.resolvedModelId.flatMap { id in
                byId[id].map {
                    ModelDisplayName.format(baseName: $0.displayName, modelId: $0.id, driverId: $0.driverId)
                }
            },
            substituted: r.substituted,
            blocked: r.isBlocked,
            blockedReason: r.blockedReason?.rawValue,
            waitsMessage: r.isBlocked ? "No model on \(settings.defaultTier.displayName) — waits" : nil)

        return DefaultSettingsJSON(
            contractVersion: contractVersion,
            defaultTier: settings.defaultTier.rawValue,
            allowHealthySubstitutions: settings.allowHealthySubstitutions,
            tiers: tierViews, unassigned: unassigned, auto: auto)
    }

    /// Convenience for callers that hold raw `[Model]` rather than pre-built
    /// `ModelListJSON.Entry` rows (e.g. the Mac app, which imports Core but not the
    /// CLI's `ModelListProjector`). `sourceReadyModelIds` = ids whose SOURCE CLI is
    /// installed + signed-in (independent of enablement); the projector still gates a
    /// model's "live" status on enablement. Produces the same projection as `build`.
    public static func build(
        settings: DefaultModelSettings,
        benchModels: [Model],
        sourceReadyModelIds: Set<ModelID>,
        driverDisplayName: (String) -> String,
        contractVersion: String
    ) -> DefaultSettingsJSON {
        // Map [Model] → Entry, setting Entry.ready = SOURCE-ready (driver up). The
        // canonical "live" gate (ready AND enabled) is applied ONCE inside the [Entry]
        // build (isLive); do not re-gate enablement here, so "ready" has a single
        // definition across both overloads.
        let entries = benchModels.map { m in
            ModelListJSON.Entry(
                id: m.id, displayName: m.displayName, modelLabel: m.modelLabel,
                driverId: m.driverId, driverName: driverDisplayName(m.driverId),
                role: m.role.rawValue, origin: "builtIn", enabled: m.enabled,
                ready: sourceReadyModelIds.contains(m.id),
                status: sourceReadyModelIds.contains(m.id) ? "ready" : "notReady",
                state: m.enabled ? "onBench" : "available",
                capabilities: ModelCatalog.capabilities(m.id))
        }
        return build(settings: settings, models: entries, contractVersion: contractVersion)
    }
}
