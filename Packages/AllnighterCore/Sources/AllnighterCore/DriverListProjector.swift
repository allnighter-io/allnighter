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
        // PF-S00: read-time freshness. A negative verdict past its own retry
        // window (or the 30m clock) is no longer evidence, so it is not asserted
        // — the seat reads as not-recently-checked instead of unavailable. The
        // stored record is never rewritten.
        let expiredNegative = ProbeFreshnessGate.expiredNegativeDriverIds(probeRecords, now: now)
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
                if parked {
                    status = "parked"
                    detail = nil
                } else if let record {
                    if record.status.isSmokeReady {
                        status = "ready"
                        detail = nil
                    } else if expiredNegative.contains(manifest.id) {
                        // PF-S00: the verdict outlived its evidence. Say when it
                        // was last checked instead of restating a limit the
                        // vendor may no longer be imposing — the fabricated
                        // version of this printed "Rate limited — resets Aug 14"
                        // for a Kimi seat that was answering prompts.
                        status = "notChecked"
                        detail = "Not checked recently"
                    } else {
                        status = "notReady"
                        detail = shortProbeDetail(record.status, vendorReset: vendorResetsBySource[manifest.id])
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

    private static func shortProbeDetail(_ status: ModelSetupStatus, vendorReset: Date?) -> String? {
        switch status {
        case .installedNotSignedIn: return "Needs sign-in"
        case .shimmedNeedsConfirm: return "Needs a path"
        case .probeFailed: return "Probe failed"
        case .notInstalled: return "Not installed"
        case .installedNotProbed: return "Installed, not checked"
        case .rateLimited(let observation):
            return DoctorReport.rateLimitedDetail(observation: observation, vendorReset: vendorReset)
        case .ready: return nil
        }
    }
}
