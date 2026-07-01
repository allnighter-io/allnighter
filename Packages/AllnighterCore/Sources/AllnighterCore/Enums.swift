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
