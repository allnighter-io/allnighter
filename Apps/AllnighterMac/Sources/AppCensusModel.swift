import Foundation
import AllnighterCore
import AllnighterEngine

/// Census discovery gap detection and tool-status merge policy for `AppModel`.
enum AppCensusModel {
    static func unresolvedSupported(registry: DriverRegistry, toolStatuses: [ToolProbeRecord]) -> [String] {
        let byId = Dictionary(toolStatuses.map { ($0.driverId, $0) }, uniquingKeysWith: { a, _ in a })
        return registry.all
            .filter { $0.kind == .headlessCLI }
            .map(\.id)
            .filter { id in
                switch byId[id]?.status {
                case .none, .some(.notInstalled): return true
                default: return false
                }
            }
    }

    static func mergedToolStatuses(existing: [ToolProbeRecord], discovered: [ToolProbeRecord]) -> [ToolProbeRecord] {
        var byId = Dictionary(existing.map { ($0.driverId, $0) }, uniquingKeysWith: { a, _ in a })
        for rec in discovered {
            if byId[rec.driverId]?.status.isSmokeReady == true {
                // Never downgrade ready — but allow a same-ready refresh so a
                // retained-ready diagnostic (failureCode / lastDetectedAt) lands.
                if rec.status.isSmokeReady { byId[rec.driverId] = rec }
                continue
            }
            if rec.status.isSmokeReady || rec.invocation != nil { byId[rec.driverId] = rec }
        }
        var order = existing.map(\.driverId)
        for rec in discovered where !order.contains(rec.driverId) { order.append(rec.driverId) }
        return order.compactMap { byId[$0] }
    }
}
