import Foundation
import AgentOSCLI

enum CatalogMerge {
    static func builtInDefinitions(
        catalog: LoadedCatalog,
        overlay: CatalogOverlay
    ) throws -> [ModelDefinition] {
        try catalog.models.compactMap { record in
            let overlayRow = overlay.models[record.id]
            if overlayRow?.hidden == true { return nil }
            let materialized = try catalog.materializeModel(record, enabled: overlayRow?.defaultOn ?? false)
            let capabilities = overlayRow?.caliber ?? ModelCapabilities(strengthRank: ModelCatalog.unratedModelRank)
            return ModelDefinition(
                id: record.id,
                displayName: ModelDisplayName.format(
                    baseName: record.displayName,
                    modelId: record.id,
                    driverId: record.driver),
                modelLabel: materialized.modelLabel,
                driverId: record.driver,
                role: record.role,
                origin: .builtIn,
                defaultEnabled: overlayRow?.defaultOn ?? false,
                defaultEffort: overlayRow?.defaultEffort.flatMap(EffortLevel.init(rawValue:)),
                capabilities: capabilities,
                effortVariants: materialized.effortVariants
            )
        }
    }

    static func unknownOverlayDiagnostics(overlay: CatalogOverlay, catalog: LoadedCatalog) -> [ModelCatalogDiagnostic] {
        let catalogIDs = Set(catalog.models.map(\.id))
        return overlay.models.keys
            .filter { !catalogIDs.contains($0) }
            .sorted()
            .map { id in
                ModelCatalogDiagnostic(
                    code: "CATALOG_OVERLAY_UNKNOWN_MODEL",
                    modelId: id,
                    message: "Overlay references model '\(id)' that is absent from the AgentOS catalog; ignoring."
                )
            }
    }

    static func hiddenRosterDiagnostics(
        overlay: CatalogOverlay,
        roster: ModelRosterState
    ) -> [ModelCatalogDiagnostic] {
        let hidden = Set(overlay.models.compactMap { entry in
            entry.value.hidden == true ? entry.key : nil
        })
        return roster.enabledModelIds
            .filter { hidden.contains($0) }
            .map { id in
                ModelCatalogDiagnostic(
                    code: "MODEL_ROSTER_STALE_ID",
                    modelId: id,
                    message: "Roster enabled set references hidden built-in '\(id)'; excluding from bench."
                )
            }
    }
}
