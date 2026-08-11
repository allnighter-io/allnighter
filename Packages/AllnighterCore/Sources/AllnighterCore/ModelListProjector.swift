import Foundation

/// Single projection funnel for `alln models` human + `--json` (Agent_Front_Door.md §F3).
public enum ModelListProjector {
    public static func build(
        registry: DriverRegistry,
        definitions: [ModelDefinition],
        probeRecords: [ToolProbeRecord],
        now: Date = Date(),
        diagnostics: [ModelCatalogDiagnostic],
        benchOnly: Bool = false,
        driverId: String? = nil,
        parkedDriverIds: Set<String> = []
    ) -> ModelListJSON {
        // PF-S00/S02: read-time projection. A negative verdict that is past its
        // own retry window, or that no vendor ever stated, is not evidence — so
        // it is not asserted and the seat reads as unknown rather than
        // unavailable. The stored record is never rewritten.
        let unassertable = ProbeFreshnessGate.unassertableNegatives(probeRecords, now: now)
        let recordsByDriver = Dictionary(uniqueKeysWithValues:
            probeRecords.map { ($0.driverId, $0) })
        let manifestIDs = Set(registry.all.map(\.id))
        if definitions.isEmpty {
            let catalogCount = ModelCatalog.list(driverId: driverId).count
            let (counsel, nextActions) = AgentFrontDoor.emptyModelsCounsel(
                benchOnly: benchOnly, driverId: driverId, catalogCount: catalogCount)
            return ModelListJSON(
                contractVersion: ContractRegistry.contractVersion,
                models: [],
                diagnostics: diagnostics,
                counsel: counsel,
                nextActions: nextActions
            )
        }
        let resolved = ModelCatalog.resolvedModels(registry: registry)
        let enabledMap = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0.enabled) })
        let entries = definitions.sorted { $0.id < $1.id }.map { def -> ModelListJSON.Entry in
            let enabled = enabledMap[def.id] ?? def.defaultEnabled
            let driverMissing = !manifestIDs.contains(def.driverId)
            let parked = parkedDriverIds.contains(def.driverId)
            let record = recordsByDriver[def.driverId]
            let ready = !driverMissing && !parked && (record?.status.isSmokeReady ?? false)
            let status: String
            if driverMissing {
                status = "driverMissing"
            } else if parked {
                status = "parked"
            } else if let record, unassertable[def.driverId] == nil {
                status = record.status.isSmokeReady ? "ready" : "notReady"
            } else {
                // No record, or a negative verdict that outlived its evidence or
                // never had any: all are "we don't currently know", which
                // already renders as "Source not checked" rather than "Source
                // not ready". The distinction matters — an agent reading
                // `notReady` stops considering the seat.
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
                headlessTrust: headlessTrust,
                stale: ProbeFreshnessDisclosure.forModel(record, driverId: def.driverId, now: now).stale
            )
        }
        // Selection identity/state share MenuCatalog records (MR-S05 / Law 2).
        // Probe/capability fields stay on the domain Entry; enabled/ready/display
        // align to the same menu rows `alln menu --json` exposes.
        // `detailed: true` is required, not cosmetic. MenuCatalog is the
        // SELECTION front door and drops disabled rows
        // (`selectableRows = detailed ? modelRows : modelRows.filter(isTierOneSelectable)`).
        // `alln models` is the CATALOG view — it must show off-Bench seats as
        // `state: "available"`, which is the whole point of the
        // `models add` → `models verify` → `models enable` flow. Borrowing the
        // menu's filter here made a freshly added custom model invisible in the
        // very command the user runs to confirm it exists. Bench filtering is
        // already applied upstream via `benchOnly`.
        let menuModels = MenuCatalog.project(modelEntries: entries, detailed: true).models
        let byId = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let reconciled: [ModelListJSON.Entry] = menuModels.compactMap { row in
            guard let base = byId[row.id] else { return nil }
            return ModelListJSON.Entry(
                id: row.id,
                displayName: row.displayName,
                modelLabel: base.modelLabel,
                driverId: row.driverId,
                driverName: base.driverName,
                role: base.role,
                origin: base.origin,
                enabled: row.enabled,
                ready: row.ready,
                status: base.status,
                state: row.enabled ? "onBench" : "available",
                capabilities: base.capabilities,
                headlessTrust: base.headlessTrust,
                stale: base.stale
            )
        }
        var payload = ModelListJSON(
            contractVersion: ContractRegistry.contractVersion,
            models: reconciled,
            diagnostics: diagnostics
        )
        if reconciled.isEmpty {
            let catalogCount = ModelCatalog.list(driverId: driverId).count
            let (counsel, nextActions) = AgentFrontDoor.emptyModelsCounsel(
                benchOnly: benchOnly, driverId: driverId, catalogCount: catalogCount)
            payload.counsel = counsel
            payload.nextActions = nextActions
        }
        return payload
    }
}
