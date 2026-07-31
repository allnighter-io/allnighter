import Foundation

// ModelRole and DriverKind moved to AgentOSCLI (AgentOS runtime seam, roadmap
// P1.2); they resolve here via `@_exported import AgentOSCLI` in
// AgentOSReexports.swift.

/// Lifecycle of one team run. See `TeamRun.canTransition(to:)`.
///
/// The durable journal truth. Carries the canonical public lifecycle cases
/// (`queued`/`running`/`done`/`timedOut`, RLR-L3) alongside the multi-worker
/// stage names (`fanning_out`/`answers_in`/…). Every surface converges via the
/// total `lifecycle` projection below.
public enum RunStatus: String, Codable, Sendable, CaseIterable {
    case draft
    /// Accepted, journal durable, not yet executing (RLR-L3).
    case queued
    /// A worker's OS identity is recorded and it is executing (RLR-L3). The
    /// one-worker replacement for `fanning_out` — a single worker never fans out.
    case running
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
    /// Canonical public terminal-success (RLR-L3). `complete`/`partial` also
    /// project here; nothing sets `done` directly in P0.
    case done
    /// A clock fired (RLR-L3/L8). Nothing sets it before RLR-S05.
    case timedOut
    case cancelled
    case failed
    /// The owning process stopped before the run reached a terminal state — an
    /// orphaned/crashed run, resolved on read (never left falsely `running`).
    case interrupted
}

public extension RunStatus {
    /// Total projection onto the frozen public lifecycle (RLR-L3). Plan-aware
    /// nuance (`partial` with no plan → failed) stays in `AsyncTeamStatusMapper`,
    /// not this bare projection.
    var lifecycle: RunLifecycle {
        switch self {
        case .queued, .draft:
            return .queued
        case .running, .fanningOut, .answersIn, .planning, .reviewing, .finalizing:
            return .running
        case .done, .complete, .partial:
            return .done
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case .failed, .interrupted:
            return .failed
        }
    }
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
    /// The broker durably accepted the run but no detached runner ever claimed
    /// its bounded startup lease. No vendor process was started by this run.
    case startFailed
    case killed
    /// A named run clock fired (RLR-L8 / S05). Distinct from operator `killed`:
    /// the deadline itself is the terminal truth (operator-vs-clock asymmetry).
    case timedOut
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
    /// QABC-S01: run parked on a vendor quota wait. The agent process exited cleanly on
    /// its own (not killed) — the wait is tracked in `LoopState.capacityPark`.
    case capacityParked
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

/// RLR-L5 `runtimeOwnership`: a durable worker OS-identity receipt keyed by
/// worker id. Persisted at `workers/<safeStem(workerId)>.owner.json` in the run
/// dir (the coordinator stays at the run-dir-root `owner.json` — a separate
/// owner). The `record` is the worker's own process group (`pgid == pid`,
/// recorded atomically at spawn) so a killer signals exactly the recorded tree.
public struct RuntimeOwnership: Codable, Sendable, Equatable {
    public var workerId: String
    public var record: ProcessOwnerRecord

    public init(workerId: String, record: ProcessOwnerRecord) {
        self.workerId = workerId
        self.record = record
    }
}
