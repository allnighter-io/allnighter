import Foundation

/// Single projection funnel for `alln models` human + `--json` (Agent_Front_Door.md §F3).
public enum ModelListProjector {
    public static func build(
        registry: DriverRegistry,
        definitions: [ModelDefinition],
        probeRecords: [ToolProbeRecord],
        diagnostics: [ModelCatalogDiagnostic],
        benchOnly: Bool = false,
        driverId: String? = nil
    ) -> ModelListJSON {
        let recordsByDriver = Dictionary(uniqueKeysWithValues: probeRecords.map { ($0.driverId, $0) })
        let manifestIDs = Set(registry.all.map(\.id))
        let resolved = ModelCatalog.resolvedModels(registry: registry)
        let enabledMap = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0.enabled) })
        let entries = definitions.sorted { $0.id < $1.id }.map { def -> ModelListJSON.Entry in
            let enabled = enabledMap[def.id] ?? def.defaultEnabled
            let driverMissing = !manifestIDs.contains(def.driverId)
            let record = recordsByDriver[def.driverId]
            let ready = !driverMissing && (record?.status.isReady ?? false)
            let status: String
            if driverMissing {
                status = "driverMissing"
            } else if let record {
                status = record.status.isReady ? "ready" : "notReady"
            } else {
                status = "notChecked"
            }
            let driverName = registry.manifest(id: def.driverId)?.displayName ?? def.driverId
            let headlessTrust = registry.manifest(id: def.driverId)?.setup?.headlessTrust
            return ModelListJSON.Entry(
                id: def.id,
                displayName: def.displayName,
                modelLabel: def.modelLabel,
                driverId: def.driverId,
                driverName: driverName,
                role: def.role.rawValue,
                origin: def.origin.rawValue,
                enabled: enabled,
                ready: ready,
                status: status,
                state: enabled ? "onBench" : "available",
                capabilities: ModelCatalog.capabilities(def.id),
                headlessTrust: headlessTrust
            )
        }
        var payload = ModelListJSON(
            contractVersion: ContractRegistry.contractVersion,
            models: entries,
            diagnostics: diagnostics
        )
        if entries.isEmpty {
            let catalogCount = ModelCatalog.list(driverId: driverId).count
            let (counsel, nextActions) = AgentFrontDoor.emptyModelsCounsel(
                benchOnly: benchOnly, driverId: driverId, catalogCount: catalogCount)
            payload.counsel = counsel
            payload.nextActions = nextActions
        }
        return payload
    }
}
