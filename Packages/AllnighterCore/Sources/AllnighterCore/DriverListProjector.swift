import Foundation

/// Single projection for `alln drivers` human + `--json`. Parked rows sort last.
public enum DriverListProjector {
    public static func build(
        registry: DriverRegistry,
        probeRecords: [ToolProbeRecord],
        models: [Model],
        parkedDriverIds: Set<String>,
        contractVersion: String = ContractRegistry.contractVersion
    ) -> DriverListJSON {
        let recordsByDriver = Dictionary(uniqueKeysWithValues: probeRecords.map { ($0.driverId, $0) })
        let onCount = Dictionary(grouping: models.filter(\.enabled), by: \.driverId)
            .mapValues(\.count)

        var entries: [DriverListJSON.Entry] = registry.all
            .filter { $0.kind == .headlessCLI }
            .map { manifest in
                let parked = parkedDriverIds.contains(manifest.id)
                let record = recordsByDriver[manifest.id]
                let status: String
                let detail: String?
                if parked {
                    status = "parked"
                    detail = nil
                } else if let record {
                    if record.status.isSmokeReady {
                        status = "ready"
                        detail = nil
                    } else {
                        status = "notReady"
                        detail = shortProbeDetail(record.status)
                    }
                } else {
                    status = "notChecked"
                    detail = nil
                }
                return DriverListJSON.Entry(
                    driverId: manifest.id,
                    displayName: manifest.displayName,
                    status: status,
                    parked: parked,
                    version: record?.version,
                    modelsOn: onCount[manifest.id] ?? 0,
                    probeDetail: detail,
                    idleTimeoutSeconds: manifest.invoke?.timeoutSeconds
                )
            }

        // Active first (A→Z), parked last (A→Z) — capacity/status strips reuse this.
        entries.sort { a, b in
            if a.parked != b.parked { return !a.parked && b.parked }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        return DriverListJSON(contractVersion: contractVersion, drivers: entries)
    }

    private static func shortProbeDetail(_ status: ModelSetupStatus) -> String? {
        switch status {
        case .installedNotSignedIn: return "Needs sign-in"
        case .shimmedNeedsConfirm: return "Needs a path"
        case .probeFailed: return "Probe failed"
        case .notInstalled: return "Not installed"
        case .installedNotProbed: return "Installed, not checked"
        case .rateLimited(let observation):
            return DoctorReport.rateLimitedDetail(observation: observation)
        case .ready: return nil
        }
    }
}
