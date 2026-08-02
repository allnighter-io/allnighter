import Foundation
import AgentOSCLI

/// ORS-P0-DEGRADE / founder law: unreadable or stale derived readiness must
/// NEVER pre-emptively block dispatch. Hard refuse only on positive facts
/// (unknown model, disabled, parked, binary genuinely not installed). A cache
/// that merely says `notReady` is unknown — attempt and let the vendor fail
/// loudly at the real boundary.
public enum DispatchReadiness {
    /// Downgrade a probe record whose cached version no longer matches the
    /// currently observed binary version. Self-heals the mid-session CLI
    /// self-update case (e.g. grok 0.2.117 → 0.2.118) that otherwise leaves a
    /// stale negative verdict blocking a working CLI.
    public static func invalidateStaleVersions(
        records: [ToolProbeRecord],
        currentVersions: [String: String]
    ) -> [ToolProbeRecord] {
        records.map { record in
            guard let current = currentVersions[record.driverId], !current.isEmpty else {
                return record
            }
            let cached = record.version ?? versionString(from: record.status)
            guard let cached, !cached.isEmpty, cached != current else {
                return record
            }
            var healed = record
            healed.status = .installedNotProbed(version: current)
            healed.version = current
            return healed
        }
    }

    /// Positive hard-block reason for an explicit `--model` pin, or nil when
    /// dispatch must be attempted. Does not consult smoke-ready caches.
    public static func hardBlockReason(
        model: Model,
        record: ToolProbeRecord?,
        parkedDriverIds: Set<String>
    ) -> String? {
        if parkedDriverIds.contains(model.driverId) {
            return "\(model.id) driver \(model.driverId) is parked — run `alln drivers unpark \(model.driverId)`, then retry; see `alln menu --json`."
        }
        if let record, case .notInstalled = record.status {
            return "\(model.id) driver \(model.driverId) is not installed — run `alln detect` (refreshes the probe cache), then `alln doctor --full`; see `alln menu --json`."
        }
        return nil
    }

    /// True when a blocked-dispatch reason names a remediation that can change the
    /// outcome (detect / unpark / enable). Menu-only and doctor-only footers are
    /// dead ends — they re-read state and do not clear the block.
    public static func blockedReasonNamesWorkingRemediation(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        // Working: a command that mutates readiness/selection state.
        // Not working: `alln menu` / `alln doctor` alone (informational loop).
        let commands = [
            "alln detect",
            "alln drivers unpark",
            "alln models enable",
        ]
        return commands.contains { lower.contains($0) }
    }

    private static func versionString(from status: ModelSetupStatus) -> String? {
        switch status {
        case .ready(let v), .installedNotProbed(let v):
            return v
        default:
            return nil
        }
    }
}
