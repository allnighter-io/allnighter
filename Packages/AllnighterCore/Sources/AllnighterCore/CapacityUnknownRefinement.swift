import Foundation

/// Promote a placeholder unknown to a cause we already know without
/// inventing a capacity number. Applied after acquisition so a targeted
/// `--source` refresh cannot leave sibling dashboard/CLI seats as
/// "not checked yet" when the credential file is missing or the binary
/// is not on PATH.
///
/// Install state wins over credential state. Configuring a quota reader
/// for an absent CLI cannot produce a number, so a recorded
/// `.notInstalled` remaps `notConfigured` (and placeholders) to
/// `.notInstalled`. A missing or unknown probe record never invents
/// that claim — fall back to today's credential / PATH checks.
public enum CapacityUnknownRefinement {

    public static func overlayKnownCauses(
        _ windows: [CapacityWindow],
        now: Date,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        probeRecords: [ToolProbeRecord]? = nil
    ) -> [CapacityWindow] {
        let records = probeRecords ?? loadDefaultProbeRecords()
        return windows.map { window in
            let install = recordedInstallState(for: window.source, probeRecords: records)
            if install == .notInstalled, isRemappableUnknown(window.unknownReason) {
                return remapped(window, reason: .notInstalled, now: now)
            }
            guard isPlaceholder(window.unknownReason) else { return window }
            if let reason = dashboardNotConfiguredReason(for: window.source) {
                return remapped(window, reason: reason, now: now)
            }
            if install == .unknown,
               CapacityAcquisition.ptySourceOrder.contains(window.source),
               CapacityProbe.resolveExecutable(
                   source: window.source,
                   pathEnvironment: pathEnvironment,
                   homeDirectory: homeDirectory
               ) == nil {
                return remapped(window, reason: .notInstalled, now: now)
            }
            return window
        }
    }

    private enum RecordedInstallState {
        case notInstalled
        case installed
        case unknown
    }

    private static func recordedInstallState(
        for source: String,
        probeRecords: [ToolProbeRecord]
    ) -> RecordedInstallState {
        let driverId = CapacityUnknownRemedy.driverId(forCapacitySource: source)
        guard let record = probeRecords.first(where: { $0.driverId == driverId }) else {
            return .unknown
        }
        switch record.status {
        case .notInstalled:
            return .notInstalled
        case .shimmedNeedsConfirm, .installedNotSignedIn, .rateLimited,
             .probeFailed, .ready, .installedNotProbed:
            return .installed
        }
    }

    /// Unknowns whose named next step can still be wrong. Honest probe
    /// failures and real numbers stay as-is.
    private static func isRemappableUnknown(_ reason: CapacityUnknownReason?) -> Bool {
        switch reason {
        case .neverSampled, .spawnFailed, .notConfigured: return true
        default: return false
        }
    }

    private static func isPlaceholder(_ reason: CapacityUnknownReason?) -> Bool {
        switch reason {
        case .neverSampled: return true
        case .spawnFailed: return true
        default: return false
        }
    }

    /// Mirrors `SetupStore.State.records` without importing AllnighterEngine.
    private static func loadDefaultProbeRecords() -> [ToolProbeRecord] {
        struct SetupState: Codable { var records: [ToolProbeRecord] }
        let url = AllnighterSupportRoot.config.appendingPathComponent("cli_setup.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? CoreJSON.decode(SetupState.self, from: data) else {
            return []
        }
        return state.records
    }

    private static func dashboardNotConfiguredReason(for source: String) -> CapacityUnknownReason? {
        switch source {
        case CapacityAcquisition.dogfoodSourceId:
            switch OpenCodeGoCredentialStore.load() {
            case .success, .failure(.decryptFailed):
                return nil
            case .failure:
                return .notConfigured
            }
        case CapacityAcquisition.bailianTokenPlanSourceId:
            switch BailianTokenPlanCredentialStore.load() {
            case .success, .failure(.decryptFailed):
                return nil
            case .failure:
                return .notConfigured
            }
        default:
            return nil
        }
    }

    private static func remapped(
        _ window: CapacityWindow,
        reason: CapacityUnknownReason,
        now: Date
    ) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: reason,
            source: window.source,
            scope: window.scope,
            observedAt: now,
            sourceTier: window.sourceTier,
            poolLabel: window.poolLabel,
            planTier: window.planTier
        )
    }
}
