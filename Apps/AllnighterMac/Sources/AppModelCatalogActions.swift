import Foundation
import AllnighterCore
import AllnighterEngine

extension AppModel {
    func reloadModelsFromCatalog() {
        models = ModelCatalog.resolvedModels(registry: registry)
        reloadPresets()
    }

    func setModelEnabled(modelId: String, enabled: Bool) throws {
        try ModelCatalog.setEnabled(modelId, enabled)
        reloadModelsFromCatalog()
    }

    func addCustomModel(driverId: String, displayName: String, modelLabel: String, role: ModelRole = .answerer) throws {
        _ = try ModelCatalog.createCustom(
            driverId: driverId, displayName: displayName, modelLabel: modelLabel,
            role: role, enabled: true, registry: registry)
        reloadModelsFromCatalog()
    }

    func deleteCustomModel(modelId: String) throws {
        _ = try LocalRuntimeSeatDelete.delete(id: modelId)
        reloadModelsFromCatalog()
    }
}
