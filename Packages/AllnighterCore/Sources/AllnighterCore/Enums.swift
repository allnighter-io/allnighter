import Foundation

/// What a worker is allowed to do in a council run.
/// A worker may answer (`member`), synthesize the master plan (`synthesizer`),
/// or both (e.g. Opus 4.8 answers the prompt *and* writes the master plan).
public enum WorkerRole: String, Codable, Sendable, CaseIterable {
    case member
    case synthesizer
    case both
}

/// How a worker's CLI is invoked.
/// MVP supports two; the constitution's richer set (protocol, ide_handoff,
/// local_model) attaches later without changing existing manifests.
public enum DriverKind: String, Codable, Sendable, CaseIterable {
    case headlessCLI = "headless_cli"
    case manualPaste = "manual_paste"
}

/// Lifecycle of one council run. See `CouncilRun.canTransition(to:)`.
public enum RunStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case fanningOut = "fanning_out"
    case answersIn = "answers_in"
    /// Spans the analysis + plan reduces (Phase 06).
    case synthesizing
    /// Review-board presets only (RB2).
    case reviewing
    /// Final-spec reduce (RB3).
    case finalizing
    case complete
    /// Members are readable but a later stage did not complete.
    case partial
    case cancelled
    case failed
}

/// Lifecycle of one member (one worker answering the prompt).
public enum MemberStatus: String, Codable, Sendable, CaseIterable {
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
public enum MemberErrorKind: String, Codable, Sendable, CaseIterable {
    case missingCLI = "missing_cli"
    case authRequired = "auth_required"
    case timedOut = "timed_out"
    case nonzeroExit = "nonzero_exit"
    case emptyOutput = "empty_output"
    case cancelled
}

/// How a council run was started. The tool surface (RB6) sets cli/mcp/http;
/// the GUI sets gui (the default).
public enum RunOrigin: String, Codable, Sendable, CaseIterable {
    case gui
    case cli
    case mcp
    case http
}
