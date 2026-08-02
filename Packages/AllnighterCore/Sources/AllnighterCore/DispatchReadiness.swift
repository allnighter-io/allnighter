import Foundation
import AgentOSCLI

/// ORS-P0-DEGRADE / founder law: unreadable or stale derived readiness must
/// NEVER pre-emptively block dispatch. Hard refuse only on user intent /
/// identity / safety invariants (parked driver, disabled model, unknown id,
/// per-root write lock). A probe cache — including cached `.notInstalled` —
/// only INFORM selection; dispatch attempts and the real spawn boundary fails
/// loudly (`command not found: …` / `errorKind: .missingCLI`) when the binary
/// is genuinely absent.
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
    /// dispatch must be attempted. Does not consult probe caches (including
    /// `.notInstalled`) — those inform menu/models/drivers and free selection
    /// only. Parked is user intent and remains a hard refuse here.
    public static func hardBlockReason(
        model: Model,
        parkedDriverIds: Set<String>
    ) -> String? {
        if parkedDriverIds.contains(model.driverId) {
            return "\(model.id) driver \(model.driverId) is parked — run `alln drivers unpark \(model.driverId)`, then retry; see `alln menu --json`."
        }
        return nil
    }

    /// True when a blocked-dispatch reason names a remediation that can change
    /// the outcome. Surviving pre-dispatch refusals and their remediations:
    /// parked → `alln drivers unpark`; disabled → `alln models enable`;
    /// unknown id → `alln models --json` (pick a real model_*); write lock →
    /// `alln ps` / `alln kill`. Menu-only and doctor-only footers are dead ends
    /// — they re-read state and do not clear the block.
    public static func blockedReasonNamesWorkingRemediation(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        let commands = [
            "alln drivers unpark",
            "alln models enable",
            "alln models --json",
            "alln kill",
            "alln ps",
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
