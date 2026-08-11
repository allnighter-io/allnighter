import Foundation

/// Single projection for `alln drivers` human + `--json`. Parked rows sort last.
public enum DriverListProjector {
    public static func build(
        registry: DriverRegistry,
        probeRecords: [ToolProbeRecord],
        now: Date = Date(),
        models: [Model],
        parkedDriverIds: Set<String>,
        vendorResetsBySource: [String: Date] = [:],
        contractVersion: String = ContractRegistry.contractVersion
    ) -> DriverListJSON {
        // PF-S00/S02: read-time projection. A negative verdict that is past its
        // own retry window, or that no vendor ever stated, is not evidence — so
        // it is not asserted and the seat reads as unknown rather than
        // unavailable. The stored record is never rewritten.
        let unassertable = ProbeFreshnessGate.unassertableNegatives(probeRecords, now: now)
        let recordsByDriver = Dictionary(uniqueKeysWithValues:
            probeRecords.map { ($0.driverId, $0) })
        let onCount = Dictionary(grouping: models.filter(\.enabled), by: \.driverId)
            .mapValues(\.count)

        var entries: [DriverListJSON.Entry] = registry.all
            .filter { $0.kind == .headlessCLI }
            .map { manifest in
                let parked = parkedDriverIds.contains(manifest.id)
                let record = recordsByDriver[manifest.id]
                let status: String
                let detail: String?
                var recoveryNext: AgentSurfaceNextAction?
                if parked {
                    status = "parked"
                    detail = nil
                } else if let record {
                    if record.status.isSmokeReady {
                        status = "ready"
                        detail = nil
                    } else if let reason = unassertable[manifest.id] {
                        // The verdict may not be asserted. Both reasons project
                        // as unknown; the copy differs because the facts do —
                        // "not checked recently" would itself be false about a
                        // record probed two minutes ago whose limit we invented.
                        // The fabricated version of this printed "Rate limited —
                        // resets Aug 14" for a Kimi seat answering prompts.
                        status = "notChecked"
                        switch reason {
                        case .expired: detail = "Not checked recently"
                        case .inferred: detail = "Capacity unknown"
                        }
                    } else {
                        status = "notReady"
                        let recovery = SetupRecoveryCopy.recovery(for: record, manifest: manifest)
                        // Inform-only probeDetail stays short; recovery.detail carries
                        // install/sign-in prose on freshness.nextAction instead.
                        detail = shortProbeDetail(
                            record.status,
                            vendorReset: vendorResetsBySource[manifest.id],
                            driverId: manifest.id
                        )
                        recoveryNext = recovery.nextAction
                    }
                } else {
                    status = "notChecked"
                    detail = nil
                }
                var freshness = ProbeFreshnessDisclosure.forDriver(record, driverId: manifest.id, now: now)
                // Prefer disease fix (e.g. `kimi login`) over a generic re-probe.
                if let recoveryNext {
                    freshness.nextAction = recoveryNext
                }
                return DriverListJSON.Entry(
                    driverId: manifest.id,
                    displayName: manifest.displayName,
                    status: status,
                    parked: parked,
                    version: record?.version,
                    modelsOn: onCount[manifest.id] ?? 0,
                    probeDetail: detail,
                    idleTimeoutSeconds: manifest.invoke?.timeoutSeconds,
                    freshness: freshness
                )
            }

        // Active first (A→Z), parked last (A→Z) — capacity/status strips reuse this.
        entries.sort { a, b in
            if a.parked != b.parked { return !a.parked && b.parked }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        return DriverListJSON(contractVersion: contractVersion, drivers: entries)
    }

    private static func shortProbeDetail(_ status: ModelSetupStatus, vendorReset: Date?, driverId: String) -> String? {
        switch status {
        case .installedNotSignedIn:
            return SetupRecoveryCopy.attentionDetail(driverId: driverId, state: .needsLogin, probeReason: nil)
        case .shimmedNeedsConfirm:
            return SetupRecoveryCopy.attentionDetail(driverId: driverId, state: .needsPath, probeReason: nil)
        case .probeFailed(let reason):
            return SetupRecoveryCopy.attentionDetail(driverId: driverId, state: .probeFailed, probeReason: reason)
        case .notInstalled:
            return SetupRecoveryCopy.attentionDetail(driverId: driverId, state: .notInstalled, probeReason: nil)
        case .installedNotProbed:
            return SetupRecoveryCopy.attentionDetail(driverId: driverId, state: .installedNotProbed, probeReason: nil)
        case .rateLimited(let observation):
            return DoctorReport.rateLimitedDetail(observation: observation, vendorReset: vendorReset)
        case .ready: return nil
        }
    }
}
