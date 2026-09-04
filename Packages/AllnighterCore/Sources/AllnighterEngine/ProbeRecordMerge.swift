import Foundation
import AgentOSCLI

/// Shared probe-record merge policy for every SetupStore writer.
///
/// A pass that resolves no path must not overwrite a prior `.ready` record when
/// that record's recorded executable path still exists and is executable.
/// Absence of a path in *this* pass is not evidence of uninstall — project law:
/// absence of a declared signal yields no observation, never an inferred one.
///
/// Lives here (not in `CensusIngest` alone) so `SourceProbeService`, App setup
/// probe, census ingest, and run-capability writes cannot reintroduce the lie
/// at the next call site. AgentOS `DriverProbeRecords.upsert` stays a dumb
/// replace; Allnighter owns the product rule.
public enum ProbeRecordMerge {

    /// Diagnostic stamped on a retained ready record when a pass asserted
    /// `.notInstalled` while the prior path was still executable. Closest
    /// durable field on `ToolProbeRecord` (AgentOS has no `lastError`).
    public static let retainedReadyFailureCode = "path_unresolved_prior_ready_retained"

    /// Apply one incoming pass result against an optional prior record.
    public static func apply(
        incoming: ToolProbeRecord,
        prior: ToolProbeRecord?,
        isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> ToolProbeRecord {
        if shouldRetainReady(incoming: incoming, prior: prior, isExecutable: isExecutable) {
            var kept = prior!
            kept.lastDetectedAt = incoming.lastProbeAt
            kept.failureCode = retainedReadyFailureCode
            return kept
        }
        return incoming
    }

    /// A flaky or mismatched smoke pass must not erase a prior confirmed-ready
    /// record when the executable is still on disk.
    private static func shouldRetainReady(
        incoming: ToolProbeRecord,
        prior: ToolProbeRecord?,
        isExecutable: @Sendable (String) -> Bool
    ) -> Bool {
        guard let prior, case .ready = prior.status,
              let path = prior.invocation?.resolvedPath,
              isExecutable(path) else {
            return false
        }
        switch incoming.status {
        case .notInstalled, .probeFailed:
            return true
        default:
            return false
        }
    }

    /// Upsert with the notInstalled-over-ready guard.
    public static func upsert(
        _ incoming: ToolProbeRecord,
        into records: inout [ToolProbeRecord],
        isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        let prior = records.first { $0.driverId == incoming.driverId }
        let applied = apply(incoming: incoming, prior: prior, isExecutable: isExecutable)
        DriverProbeRecords.upsert(applied, into: &records)
    }

    /// Merge a full incoming pass into prior records (by driverId). Drivers
    /// only present in `prior` are retained; each incoming record goes through
    /// `apply` against its prior peer.
    public static func merge(
        prior: [ToolProbeRecord],
        incoming: [ToolProbeRecord],
        isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> [ToolProbeRecord] {
        var out = prior
        for rec in incoming {
            upsert(rec, into: &out, isExecutable: isExecutable)
        }
        return out
    }
}
