import Foundation

// ModelRole and DriverKind moved to AgentOSCLI (AgentOS runtime seam, roadmap
// P1.2); they resolve here via `@_exported import AgentOSCLI` in
// AgentOSReexports.swift.

/// Lifecycle of one team run. See `TeamRun.canTransition(to:)`.
public enum RunStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case fanningOut = "fanning_out"
    case answersIn = "answers_in"
    /// Spans the analysis + plan reduces (Phase 06).
    case planning
    /// Review-board presets only (RB2).
    case reviewing
    /// Final-spec reduce (RB3).
    case finalizing
    case complete
    /// Members are readable but a later stage did not complete.
    case partial
    case cancelled
    case failed
    /// The owning process stopped before the run reached a terminal state — an
    /// orphaned/crashed run, resolved on read (never left falsely `running`).
    case interrupted
}

// WorkerAnswerStatus and WorkerAnswerErrorKind moved to AgentOSCLI (roadmap P1.5c);
// they resolve here via the `@_exported import AgentOSCLI` re-export.

/// How a team run was started. The tool surface (RB6) sets cli/mcp/http;
/// the GUI sets gui (the default).
public enum RunOrigin: String, Codable, Sendable, CaseIterable {
    case gui
    case cli
    case mcp
    case http
    case ios
}

/// Why a terminal team run ended (`docs/phases/Process_Ownership.md` PO-S01).
/// Never empty on a terminal run once stamped.
public enum RunEndReason: String, Codable, Sendable, CaseIterable {
    case completed
    case failed
    case cancelled
    /// Reconcile: heartbeat stale AND owner pid dead.
    case reconciledOrphan
    case killed

    /// Best-effort map from terminal `RunStatus` when a writer did not stamp
    /// an explicit reason. `interrupted` defaults to `reconciledOrphan`.
    public static func inferred(from status: RunStatus) -> RunEndReason? {
        switch status {
        case .complete, .partial: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .interrupted: return .reconciledOrphan
        case .draft, .fanningOut, .answersIn, .planning, .reviewing, .finalizing:
            return nil
        }
    }
}
