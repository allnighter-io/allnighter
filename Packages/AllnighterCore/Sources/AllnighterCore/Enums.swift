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

/// Why a terminal team run ended (`docs/phases/Process_Ownership.md` PO-S01 v2).
/// Stamped by the actor that knows — never inferred from status after the fact.
public enum RunEndReason: String, Codable, Sendable, CaseIterable {
    case completed
    case failed
    case cancelled
    /// Explicit reconcile: identity-verified dead owner.
    case reconciledOrphan
    case killed
    /// Honest "we do not know" — itself a bug report when seen in production.
    case unknown
}

/// Why a relay/pilot **dev turn** ended (`docs/phases/Process_Ownership.md` PO-S02).
/// Stamped by the actor that ends the turn — never inferred after the fact.
public enum DevTurnEndReason: String, Codable, Sendable, CaseIterable {
    /// Dev finished and reported usable output.
    case reported
    /// Watchdog / stall-retry budget exhausted.
    case stalled
    /// Explicit group kill (reconcile after relay death, deadline stop mid-turn, etc.).
    case killed
    /// Harness proof of record timed out (PO-S04; stamped when the harness kills a proof).
    case proofTimeout
    /// Execution lane held by another identity (PO-S03 turn acquire, or PO-S04 proof acquire).
    case laneBusy
    /// Honest "we do not know" — itself a bug report when seen in production.
    case unknown
}

/// Durable process-group identity record for Core models (relay rounds, wire JSON).
/// Engine maps to/from `ProcessOwnership.OwnerIdentity` — never a second kill identity.
public struct ProcessOwnerRecord: Codable, Sendable, Equatable {
    public var pid: Int32
    public var pgid: Int32?
    public var startTimeTicks: Int64
    /// `ProcessOwnership.OwnerKind` raw value (`devTurn`, `detachedRunner`, …).
    public var kind: String

    public init(pid: Int32, pgid: Int32?, startTimeTicks: Int64, kind: String) {
        self.pid = pid
        self.pgid = pgid
        self.startTimeTicks = startTimeTicks
        self.kind = kind
    }
}
