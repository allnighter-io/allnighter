import Foundation
import AllnighterCore
import AllnighterEngine

/// Setup card mapping and cached setup state helpers for `AppModel`.
enum AppSetupModel {
    /// Per-driver invocations from probe records — shared by `AppModel` runners and `ThreadsViewModel`.
    /// Keys by driver id (image invoker) and by manifest `invoke.command` (spawn resolver).
    static func invocations(
        from records: [ToolProbeRecord],
        registry: DriverRegistry = DefaultConfig.registry
    ) -> [String: ToolInvocation] {
        var map: [String: ToolInvocation] = [:]
        for record in records {
            guard let inv = record.invocation else { continue }
            map[record.driverId] = inv
            if let command = registry.manifest(id: record.driverId)?.invoke?.command, !command.isEmpty {
                map[command] = inv
            }
        }
        return map
    }

    static func setupCards(
        registry: DriverRegistry,
        toolStatuses: [ToolProbeRecord],
        models: [Model],
        parkedDriverIds: Set<String> = [],
        isDetecting: Bool = false,
        probingDriverId: String? = nil,
        now: Date = Date()
    ) -> [SetupCardModel] {
        // Read once for the whole list, never per card — one disk read, not N.
        let vendorResets = CapacityResetLookup.bySource(now: now)
        return registry.all
            .filter { $0.kind == .headlessCLI }
            // List CLIs A→Z by display name (founder) — stable order in the doctor hover
            // and the CLI setup page; consumers partition READY/not-ready but keep order.
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { manifest in
            let rec = toolStatuses.first { $0.driverId == manifest.id }
            let seats = models.filter { $0.driverId == manifest.id }.map {
                SetupCardModel.WorkerSeat(id: $0.id, name: $0.displayName, modelLabel: $0.modelLabel, isPlanWriter: $0.canWritePlan)
            }
            let route = "via " + manifest.id.replacingOccurrences(of: "_", with: "-")
            let state: SetupCardState
            var shim: String?
            var reason: String?
            if parkedDriverIds.contains(manifest.id) {
                state = .parked
            } else if isDetecting && (probingDriverId == nil || probingDriverId == manifest.id) {
                state = .reprobing
            } else {
            switch rec?.status {
            case .ready?: state = .ready
            case .installedNotSignedIn?: state = .needsLogin
            case .shimmedNeedsConfirm(let r)?: state = .needsPath; shim = r.rawCommandV
            case .probeFailed(let r)?: state = .probeFailed; reason = r
            case .rateLimited(let observation)?:
                state = .rateLimited
                reason = DoctorReport.rateLimitedDetail(
                    observation: observation,
                    vendorReset: vendorResets[manifest.id],
                    now: now
                )
            case .notInstalled?: state = .notInstalled
            case .installedNotProbed?: state = .installedNotProbed
            case nil: state = .notChecked
            }
            }
            return SetupCardModel(
                driverId: manifest.id, name: manifest.displayName, route: route, version: rec?.version,
                state: state, workers: seats,
                loginCommand: manifest.setup?.loginFlow?.interactiveCommand,
                installHint: manifest.setup?.installHint, docsURL: manifest.setup?.docsURL,
                loginDocsURL: manifest.setup?.loginFlow?.docsURL,
                shimCommand: shim, probeReason: reason,
                headlessTrust: manifest.setup?.headlessTrust)
        }
    }
}
