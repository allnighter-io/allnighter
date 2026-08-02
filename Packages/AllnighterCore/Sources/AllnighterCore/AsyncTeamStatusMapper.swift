import Foundation

/// Lifecycle projection for cancel / reconcile / `StalledWorkDetector`.
/// Not a public product read surface — agents read via `alln show` / `TeamRunJSON`.
public enum AsyncTeamStatusMapper {
    /// Journal `RunStatus` → frozen public `RunLifecycle` (RLR-L3). Mostly the
    /// bare `RunStatus.lifecycle` projection, with two run-aware refinements the
    /// bare projection deliberately omits: a no-plan `partial` reads as `failed`,
    /// and a `fanning_out` run with no active worker yet reads as `queued`.
    ///
    /// Package-internal only (ORS-S03b): not a public dual status schema.
    package static func liveStatus(for run: TeamRun) -> RunLifecycle {
        switch run.status {
        case .partial:
            return run.plan != nil ? .done : .failed
        case .fanningOut:
            let active = run.answers.contains { $0.result.status == .running || $0.result.status == .done || $0.result.status == .failed }
            return active ? .running : .queued
        default:
            return run.status.lifecycle
        }
    }
}
