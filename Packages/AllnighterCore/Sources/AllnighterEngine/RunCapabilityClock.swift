import Foundation
import AllnighterCore
import AgentOSCLI

/// The run path writes the capability clock (`Probe_Freshness.md` §"the writer
/// that was missing"). `SourceProbeService`'s cheap path cannot honestly advance
/// `lastProbeAt` — a version check without smoke proves nothing about
/// capability. A REAL run is the missing writer: it already invoked the vendor,
/// and `WorkerAnswerErrorKind` already tells us, fail-closed, whether that
/// invocation says anything about readiness.
///
/// A probe is a simulated run; a real run is better evidence and costs nothing
/// extra — a user can invoke a seat fifty times and, before this, the bench
/// still "doesn't know" whether it works.
///
/// Taxonomy (deliberately narrow — everything not named here yields NO write):
///   - a successful answer (`status == .done`, no `errorKind`) → capability
///     CONFIRMED now (`.ready`)
///   - `.missingCLI`   → negative: not installed (`.notInstalled`)
///   - `.authRequired` → negative: installed, not usable (`.installedNotSignedIn`
///     when the manifest declares a login flow, else `.probeFailed`)
///   - `.timedOut`, `.nonzeroExit`, `.emptyOutput`, `.cancelled`,
///     `.permissionRequired` → NOT readiness evidence. A bad prompt or a user
///     cancel says nothing about whether the seat works. No write.
///
/// Deliberately does NOT touch `Probe_Freshness.md`'s `unassertableNegatives`
/// gate or `status`-driven `blockedReason` machinery — those are PF-S00/S02 and
/// must not change here. This only ever WRITES the persisted probe cache; a
/// call site wraps the whole thing in `try?` so a persistence failure can never
/// slow, block, or fail the run that produced the evidence (constraint from
/// the packet: "must never slow down, block, or fail a run").
public enum RunCapabilityClock {

    /// The attribution stamped into `ToolProbeRecord.resolvedBy` for a
    /// run-sourced write — `ProbeFreshnessDisclosure` reads this to label
    /// `evidenceSource: "run"` rather than `"probe"`.
    public static let resolvedBy = "RunService"

    /// Computes the merged record set for `records`, or `nil` when this
    /// outcome carries no readiness evidence at all (fail closed — no write).
    /// Pure and synchronous so it is trivially unit-testable without a live
    /// `RunService`; the caller owns persistence (`SetupStore`) and the
    /// `try?` swallow.
    public static func apply(
        driverId: String,
        manifest: DriverManifest?,
        result: WorkerRunResult,
        now: Date,
        records: [ToolProbeRecord]
    ) -> [ToolProbeRecord]? {
        let existing = records.first { $0.driverId == driverId }
        guard let status = confirmedStatus(result: result, manifest: manifest, existing: existing) else {
            return nil
        }
        var merged = existing ?? ToolProbeRecord(driverId: driverId, status: status, lastProbeAt: now)
        merged.status = status
        merged.lastProbeAt = now
        merged.lastDetectedAt = now
        merged.resolvedBy = resolvedBy
        if case .ready = status { merged.failureCode = nil }
        var out = records
        ProbeRecordMerge.upsert(merged, into: &out)
        return out
    }

    private static func confirmedStatus(
        result: WorkerRunResult, manifest: DriverManifest?, existing: ToolProbeRecord?
    ) -> ModelSetupStatus? {
        if result.status == .done, result.errorKind == nil {
            if case .ready(let version) = existing?.status { return .ready(version: version) }
            return .ready(version: existing?.version ?? "")
        }
        switch result.errorKind {
        case .missingCLI:
            return .notInstalled
        case .authRequired:
            if let flow = manifest?.setup?.loginFlow { return .installedNotSignedIn(flow) }
            return .probeFailed(reason: "auth required")
        default:
            // timedOut, nonzeroExit, emptyOutput, cancelled, permissionRequired,
            // or a still-nil errorKind on a non-done status: none of these speak
            // to whether the seat works. Fail closed — no observation.
            return nil
        }
    }
}
