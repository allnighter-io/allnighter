import SwiftUI
import AllnighterCore

/// Drives the **Default model** settings screen. Holds no durable truth of its own:
/// it loads `DefaultModelSettings` (the Core SSOT), renders it through the SAME
/// `DefaultSettingsProjector` the CLI/MCP use, and every mutation goes back through
/// Core (`TierMembership` + persistence) and re-projects. The screen is a pure
/// projection of `DefaultSettingsJSON` — identical to `alln defaults --json`.
@Observable
@MainActor
final class DefaultModelViewModel {
    private(set) var projection: DefaultSettingsJSON =
        DefaultSettingsProjector.build(settings: .fresh, models: [], contractVersion: ContractRegistry.contractVersion)

    private let persistence = DefaultModelSettingsPersistence()
    private var benchModels: [Model] = []
    private var sourceReadyIds: Set<ModelID> = []
    private var driverName: (String) -> String = { $0 }

    /// Feed in the app's live bench + readiness. Recompute whenever they change.
    func load(benchModels: [Model], sourceReadyIds: Set<ModelID>, driverName: @escaping (String) -> String) {
        self.benchModels = benchModels
        self.sourceReadyIds = sourceReadyIds
        self.driverName = driverName
        reproject()
    }

    private func reproject() { project(from: persistence.load()) }

    private func project(from settings: DefaultModelSettings) {
        projection = DefaultSettingsProjector.build(
            settings: settings,
            benchModels: benchModels,
            sourceReadyModelIds: sourceReadyIds,
            driverDisplayName: driverName,
            contractVersion: ContractRegistry.contractVersion)
    }

    private func mutate(_ change: (inout DefaultModelSettings) -> Void) {
        var s = persistence.load()
        change(&s)
        try? persistence.save(s)
        project(from: s)   // reuse the in-memory settings; no second disk read
    }

    // MARK: - Mutations (mirror `alln defaults …`)

    func setDefaultTier(_ tier: SubstitutionTier) { mutate { $0.defaultTier = tier } }
    func setSubstitutions(_ on: Bool) { mutate { $0.allowHealthySubstitutions = on } }

    /// Drag-to-top equivalent: make this model the tier's default (index 0).
    func makeDefault(_ id: ModelID, in tier: SubstitutionTier) { mutate { $0.tiers.assign(id, to: tier, position: 0) } }
    /// Add a model to a tier (append). Many-to-many: never removes it from others.
    func assign(_ id: ModelID, to tier: SubstitutionTier) { mutate { $0.tiers.assign(id, to: tier) } }
    /// Remove from one tier (or all tiers when `tier == nil`).
    func unassign(_ id: ModelID, from tier: SubstitutionTier?) { mutate { $0.tiers.unassign(id, from: tier) } }
    func reset() { try? persistence.reset(); reproject() }

    // MARK: - View helpers

    var defaultTier: SubstitutionTier { SubstitutionTier(rawValue: projection.defaultTier) ?? .flagship }
    func tierView(_ tier: SubstitutionTier) -> DefaultSettingsJSON.TierView? {
        projection.tiers.first { $0.tier == tier.rawValue }
    }
}
