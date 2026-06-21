import Foundation

/// What a model is allowed to do in a team run.
/// A model may answer only (`answerer`), write the plan (`planWriter`),
/// or both (e.g. Opus 4.8 answers the prompt *and* writes the plan).
public enum ModelRole: String, Codable, Sendable, CaseIterable {
    case answerer
    case planWriter
    case both
}

/// How a worker's CLI is invoked.
/// MVP supports two; the constitution's richer set (protocol, ide_handoff,
/// local_model) attaches later without changing existing manifests.
public enum DriverKind: String, Codable, Sendable, CaseIterable {
    case headlessCLI = "headless_cli"
    case manualPaste = "manual_paste"
}

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

/// Lifecycle of one member (one worker answering the prompt).
public enum WorkerAnswerStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case done
    case failed
    case timedOut = "timed_out"
    case cancelled
    /// A `manual_paste` worker awaiting a pasted answer.
    case skipped
}

/// Why a member did not produce a usable answer. Surfaced to the user verbatim
/// so a churned/unauthenticated CLI fails loudly rather than silently.
public enum WorkerAnswerErrorKind: String, Codable, Sendable, CaseIterable {
    case missingCLI = "missing_cli"
    case authRequired = "auth_required"
    case timedOut = "timed_out"
    case nonzeroExit = "nonzero_exit"
    case emptyOutput = "empty_output"
    case cancelled
}

/// How a team run was started. The tool surface (RB6) sets cli/mcp/http;
/// the GUI sets gui (the default).
public enum RunOrigin: String, Codable, Sendable, CaseIterable {
    case gui
    case cli
    case mcp
    case http
    case ios
}
