import Foundation
import AllnighterCore
import AllnighterEngine

/// Setup card mapping and cached setup state helpers for `AppModel`.
enum AppSetupModel {
    /// Per-driver invocations from probe records — shared by `AppModel` runners and `ThreadsViewModel`.
    static func invocations(from records: [ToolProbeRecord]) -> [String: ToolInvocation] {
        var map: [String: ToolInvocation] = [:]
        for record in records where record.invocation != nil {
            map[record.driverId] = record.invocation
        }
        return map
    }

    static func setupCards(
        registry: DriverRegistry,
        toolStatuses: [ToolProbeRecord],
        models: [Model],
        parkedDriverIds: Set<String> = [],
        isDetecting: Bool = false,
        probingDriverId: String? = nil
    ) -> [SetupCardModel] {
        registry.all
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
            case .rateLimited(let observation)?: state = .rateLimited; reason = DoctorReport.rateLimitedDetail(observation: observation)
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
                shimCommand: shim, probeReason: reason,
                headlessTrust: manifest.setup?.headlessTrust)
        }
    }
}
