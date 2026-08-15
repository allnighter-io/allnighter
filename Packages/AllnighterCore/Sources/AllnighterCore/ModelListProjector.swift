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
        parkedDriverIds: Set<String> = [],
        ollamaLocal: OllamaLocalRuntimeObserver.Snapshot? = nil
    ) -> ModelListJSON {
        // PF-S00/S02: read-time projection. A negative verdict that is past its
        // own retry window, or that no vendor ever stated, is not evidence — so
        // it is not asserted and the seat reads as unknown rather than
        // unavailable. The stored record is never rewritten.
        let unassertable = ProbeFreshnessGate.unassertableNegatives(probeRecords, now: now)
        let recordsByDriver = Dictionary(uniqueKeysWithValues:
            probeRecords.map { ($0.driverId, $0) })
        let manifestIDs = Set(registry.all.map(\.id))
        let overlayDefs = overlayDefinitions(
            from: ollamaLocal, seated: definitions, now: now)
        let overlayIDs = Set(overlayDefs.map(\.id))
        let allDefinitions = definitions + overlayDefs
        if allDefinitions.isEmpty {
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
        let visibleTags = ollamaLocal.map { snap in
            Dictionary(uniqueKeysWithValues: snap.localTags.map { ($0.name, $0) })
        } ?? [:]
        let entries = allDefinitions.sorted { $0.id < $1.id }.map { def -> ModelListJSON.Entry in
            let isOverlay = overlayIDs.contains(def.id)
            let enabled = isOverlay ? false : (enabledMap[def.id] ?? def.defaultEnabled)
            let driverMissing = !manifestIDs.contains(def.driverId)
            let parked = parkedDriverIds.contains(def.driverId)
            let record = recordsByDriver[def.driverId]
            let localOllamaSeat = OpenCodeLocalSeatReadiness.isLocalOpenCodeSeat(
                driverId: def.driverId, modelLabel: def.modelLabel)
                || ClaudeLocalIsolation.isLocalSeat(
                    driverId: def.driverId, modelLabel: def.modelLabel)
            let ready: Bool
            let status: String
            if isOverlay {
                // Overlay is visibility, not a seat. Never driverMissing on
                // ollama_local — that source is not a body manifest.
                ready = false
                status = "notChecked"
            } else if driverMissing {
                ready = false
                status = "driverMissing"
            } else if parked {
                ready = false
                status = "parked"
            } else if localOllamaSeat {
                // Local Ollama seats: binary + tag. Never Zen/Go or Claude invoke smoke.
                let binary = OpenCodeLocalSeatReadiness.installedBinaryPath(
                    from: record, driverId: def.driverId)
                if binary == nil {
                    ready = false
                    status = record == nil ? "notChecked" : "notReady"
                } else if ollamaLocal == nil {
                    ready = false
                    status = "notChecked"
                } else {
                    let localReady = OpenCodeLocalSeatReadiness.isLocallyReady(
                        modelLabel: def.modelLabel,
                        binaryPath: binary,
                        snapshot: ollamaLocal
                    )
                    ready = localReady
                    status = localReady ? "ready" : "notReady"
                }
            } else {
                ready = record?.status.isSmokeReady ?? false
                if let record, unassertable[def.driverId] == nil {
                    status = record.status.isSmokeReady ? "ready" : "notReady"
                } else {
                    // No record, or a negative verdict that outlived its evidence or
                    // never had any: all are "we don't currently know", which
                    // already renders as "Source not checked" rather than "Source
                    // not ready". The distinction matters — an agent reading
                    // `notReady` stops considering the seat.
                    status = "notChecked"
                }
            }
            let driverName = registry.manifest(id: def.driverId)?.displayName ?? def.driverId
            let headlessTrust = registry.manifest(id: def.driverId)?.setup?.headlessTrust
            let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: def.modelLabel)
            let observedTag = tag.flatMap { visibleTags[$0] }
            let readiness: String?
            if isOverlay {
                readiness = nil
            } else if localOllamaSeat, let snap = ollamaLocal {
                // Law Available is per seated row only (§3 rule 2).
                readiness = OllamaLocalDoctorReport.readinessWord(
                    from: snap,
                    modelLabel: def.modelLabel
                )
            } else {
                readiness = nil
            }
            let discovered: Bool?
            let seated: Bool?
            let enableCommand: String?
            let capabilityUnknown: Bool?
            if isOverlay {
                discovered = true
                seated = false
                enableCommand = OllamaLocalModelDiscoveryProvider.enableCommand(
                    candidateID: def.id,
                    bodyDriverId: LocalRuntimeDefaultBody.resolved())
                capabilityUnknown = observedTag?.capabilityUnknown == true ? true : nil
            } else if localOllamaSeat {
                seated = true
                discovered = ollamaLocal == nil ? nil : (observedTag?.isCompletionCandidate == true)
                enableCommand = nil
                capabilityUnknown = nil
            } else {
                discovered = nil
                seated = nil
                enableCommand = nil
                capabilityUnknown = nil
            }
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
                capabilities: isOverlay ? ModelCapabilities() : ModelCatalog.capabilities(def.id),
                headlessTrust: headlessTrust,
                stale: ProbeFreshnessDisclosure.forModel(record, driverId: def.driverId, now: now).stale,
                resolvesTo: def.resolvedPinId,
                readiness: readiness,
                discovered: discovered,
                seated: seated,
                enableCommand: enableCommand,
                capabilityUnknown: capabilityUnknown
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
        let menuModelsById = Dictionary(uniqueKeysWithValues: menuModels.map { ($0.id, $0) })
        let byId = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let reconciled: [ModelListJSON.Entry] = entries.map { base in
            guard let row = menuModelsById[base.id], let mergedBase = byId[base.id] else {
                return base
            }
            return ModelListJSON.Entry(
                id: row.id,
                displayName: row.displayName,
                modelLabel: mergedBase.modelLabel,
                driverId: row.driverId,
                driverName: mergedBase.driverName,
                role: mergedBase.role,
                origin: mergedBase.origin,
                enabled: row.enabled,
                ready: row.ready,
                status: mergedBase.status,
                state: row.enabled ? "onBench" : "available",
                capabilities: mergedBase.capabilities,
                headlessTrust: mergedBase.headlessTrust,
                stale: mergedBase.stale,
                resolvesTo: mergedBase.resolvesTo,
                readiness: mergedBase.readiness,
                discovered: mergedBase.discovered,
                seated: mergedBase.seated,
                enableCommand: mergedBase.enableCommand,
                capabilityUnknown: mergedBase.capabilityUnknown
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

    /// Discovered-not-seated tags from the list's existing snapshot. Never
    /// calls async `discover()` (second socket). Never persists.
    static func overlayDefinitions(
        from snapshot: OllamaLocalRuntimeObserver.Snapshot?,
        seated: [ModelDefinition],
        now: Date
    ) -> [ModelDefinition] {
        let seatedTags = Set(seated.compactMap {
            OpenCodeLocalSeatReadiness.ollamaTag(from: $0.modelLabel)
        })
        let seatedIDs = Set(seated.map(\.id))
        return OllamaLocalModelDiscoveryProvider.result(from: snapshot, discoveredAt: now)
            .candidates
            .filter { candidate in
                guard !seatedIDs.contains(candidate.id) else { return false }
                guard let tag = OpenCodeLocalSeatReadiness.ollamaTag(from: candidate.modelLabel)
                else { return true }
                return !seatedTags.contains(tag)
            }
    }
}
