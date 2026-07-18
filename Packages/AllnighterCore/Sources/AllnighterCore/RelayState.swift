import Foundation

/// One round of a PM Relay (docs/phases/PM_Relay.md §2, §6 R-S04). A round pins the repo
/// HEAD before the PM turn, threads exactly that plus the dev's HEAD after their turn into
/// the review range for the FOLLOWING round's PM prompt (`RelayPMPrompt.Context`), and
/// records durable coordination facts only — the actual PM/dev transcripts live in
/// `RunStore` under `pmRunId`/`devRunId`; this is never a second copy of run-truth.
public struct RelayRound: Sendable, Codable, Equatable {
    /// How this round settled. `continued` is the only outcome that leads to another round;
    /// every other case ends the relay (the coordinator persists the terminal `RelayState`
    /// alongside it).
    public enum Outcome: String, Sendable, Codable, CaseIterable {
        case continued
        case done
        case escalated
        case stopped
    }

    public var roundNumber: Int
    /// git HEAD pinned via `GitObserver` immediately before the PM turn dispatches.
    public var baselineHead: String?
    /// git HEAD pinned immediately after the dev turn completes. `nil` when the round never
    /// reached (or finished) a dev turn — e.g. `done`/`escalate`/an error before then.
    public var headAfterDev: String?
    /// `RunStore` id for the PM turn — the LAST PM run this round. A verdict-parse re-ask
    /// (§4.1) supersedes the first attempt's id here; the first attempt is still durably
    /// recorded under `RunStore`, just not linked from this round.
    public var pmRunId: String?
    /// `RunStore` id for the dev turn. `nil` when the round never reached the dev turn.
    public var devRunId: String?
    public var verdict: RelayVerdict?
    /// `HandoverGate.evaluate` result for this round's handover, when one was checked.
    public var gate: RelayGateSummary?
    public var startedAt: Date
    public var finishedAt: Date?
    public var outcome: Outcome?
    /// Pilot only (`pmMode == .external`, `docs/phases/Pilot_Relay.md` §2 "round log
    /// truth"): the piloting session's raw markdown submission for this round,
    /// verbatim — the PM turn's run-truth when there is no `pmRunId`/`RunStore` entry
    /// to point at (there was no PM dispatch; the submission itself IS the record).
    /// `nil` for a spawned round.
    public var externalSubmission: String?
    /// Pilot only: `GitObserver.dirtyFiles` snapshot taken at `handoff` time (§2.1
    /// "the write-lock boundary" — honesty over ceremony: the piloting session may
    /// have edited the repo between rounds, and this records exactly what was dirty
    /// when the round began, rather than hiding it). `nil` for a spawned round.
    public var dirtyFiles: [String]?
    /// PO-S02: process-group identity of the last dev-turn worker CLI for this round
    /// (recorded at spawn; used for total turn kill + orphan reconcile). `nil` when
    /// the round never reached a dev turn, or the spawn path did not record identity
    /// (e.g. unit-test mock runners).
    public var devTurnOwner: ProcessOwnerRecord?
    /// PO-S02: stamped by the actor that ends the dev turn — never inferred.
    public var devTurnEndReason: DevTurnEndReason?
    /// PO-S04: harness-owned proof-of-record results for this round's dev turn.
    /// Empty when no `proofCommands` were declared or the turn never delivered.
    public var proofResults: [HarnessProofResult]
    /// PO-S04: declared proof commands for this turn (from turn state or parsed
    /// from the dev report tail). Durable so status JSON / resume can re-surface
    /// what the harness was asked to run — never a second subprocess path.
    public var proofCommands: [String]
    /// PO-S06: declared write scope + build-lane flag for this turn (from turn
    /// state or parsed from the dev report). Absent/`nil` = legacy full-scope +
    /// build lane. Durable for status / resume.
    public var writeScope: TurnWriteScope?
    /// PO-S06: fail-closed commit-diff violation when the turn wrote outside
    /// `writeScope`. `endReason` stays `reported`; PM decides — no auto-revert.
    public var scopeViolation: ScopeViolation?
    /// PO-F4: standing invariant ids that failed this turn (e.g. `contractDrift`).
    /// Absent/`nil` when all standing invariants passed or none ran. Marks the
    /// turn not-clean; `endReason` stays as reported (analogous to scopeViolation).
    public var standingFailed: [String]?

    public init(
        roundNumber: Int,
        baselineHead: String? = nil,
        headAfterDev: String? = nil,
        pmRunId: String? = nil,
        devRunId: String? = nil,
        verdict: RelayVerdict? = nil,
        gate: RelayGateSummary? = nil,
        startedAt: Date,
        finishedAt: Date? = nil,
        outcome: Outcome? = nil,
        externalSubmission: String? = nil,
        dirtyFiles: [String]? = nil,
        devTurnOwner: ProcessOwnerRecord? = nil,
        devTurnEndReason: DevTurnEndReason? = nil,
        proofResults: [HarnessProofResult] = [],
        proofCommands: [String] = [],
        writeScope: TurnWriteScope? = nil,
        scopeViolation: ScopeViolation? = nil,
        standingFailed: [String]? = nil
    ) {
        self.roundNumber = roundNumber
        self.baselineHead = baselineHead
        self.headAfterDev = headAfterDev
        self.pmRunId = pmRunId
        self.devRunId = devRunId
        self.verdict = verdict
        self.gate = gate
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.externalSubmission = externalSubmission
        self.dirtyFiles = dirtyFiles
        self.devTurnOwner = devTurnOwner
        self.devTurnEndReason = devTurnEndReason
        self.proofResults = proofResults
        self.proofCommands = proofCommands
        self.writeScope = writeScope
        self.scopeViolation = scopeViolation
        self.standingFailed = standingFailed
    }

    // Lenient decode: relays persisted before PO-S04/S06/F4 lack later fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roundNumber = try c.decode(Int.self, forKey: .roundNumber)
        baselineHead = try c.decodeIfPresent(String.self, forKey: .baselineHead)
        headAfterDev = try c.decodeIfPresent(String.self, forKey: .headAfterDev)
        pmRunId = try c.decodeIfPresent(String.self, forKey: .pmRunId)
        devRunId = try c.decodeIfPresent(String.self, forKey: .devRunId)
        verdict = try c.decodeIfPresent(RelayVerdict.self, forKey: .verdict)
        gate = try c.decodeIfPresent(RelayGateSummary.self, forKey: .gate)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        outcome = try c.decodeIfPresent(Outcome.self, forKey: .outcome)
        externalSubmission = try c.decodeIfPresent(String.self, forKey: .externalSubmission)
        dirtyFiles = try c.decodeIfPresent([String].self, forKey: .dirtyFiles)
        devTurnOwner = try c.decodeIfPresent(ProcessOwnerRecord.self, forKey: .devTurnOwner)
        devTurnEndReason = try c.decodeIfPresent(DevTurnEndReason.self, forKey: .devTurnEndReason)
        proofResults = try c.decodeIfPresent([HarnessProofResult].self, forKey: .proofResults) ?? []
        proofCommands = try c.decodeIfPresent([String].self, forKey: .proofCommands) ?? []
        writeScope = try c.decodeIfPresent(TurnWriteScope.self, forKey: .writeScope)
        scopeViolation = try c.decodeIfPresent(ScopeViolation.self, forKey: .scopeViolation)
        standingFailed = try c.decodeIfPresent([String].self, forKey: .standingFailed)
    }
}

/// `HandoverGate.Decision` flattened to a durable, `Codable` summary (PM_Relay.md §5 item
/// 1) — a small mirror of the live `Decision` enum, which itself isn't `Codable` (its
/// associated values are exactly what a round needs to persist, so this simply names them
/// as stored fields instead of re-deriving a wire format for the enum itself).
public struct RelayGateSummary: Sendable, Codable, Equatable {
    public var allowed: Bool
    public var dangerClass: String?
    public var code: String?
    public var reason: String?
    public var snippet: String?

    public init(
        allowed: Bool, dangerClass: String? = nil, code: String? = nil,
        reason: String? = nil, snippet: String? = nil
    ) {
        self.allowed = allowed
        self.dangerClass = dangerClass
        self.code = code
        self.reason = reason
        self.snippet = snippet
    }

    public init(decision: HandoverGate.Decision) {
        switch decision {
        case .allowed:
            self.init(allowed: true)
        case .blocked(let dangerClass, let code, let reason, let snippet):
            self.init(allowed: false, dangerClass: dangerClass.rawValue, code: code, reason: reason, snippet: snippet)
        }
    }
}

/// Who holds the PM seat for a relay (`docs/phases/Pilot_Relay.md` §1 decision 1).
/// `spawned` is the shipped PM Relay — Allnighter dispatches a PM model each round.
/// `external` is Pilot — a live human/agent session outside Allnighter IS the PM;
/// Allnighter only ever dispatches the dev seat, driven by `RelayCoordinator.
/// runExternalRound`. Same `RelayState`, same rounds, same thread — this field is the
/// only fork ("one substrate, two entries").
public enum PMMode: String, Sendable, Codable, CaseIterable {
    case spawned
    case external
}

/// One PM↔dev relay (docs/phases/PM_Relay.md) — the durable ledger `RelayCoordinator`
/// reads/writes after every state change so the loop is resumable from disk at any point,
/// never held only in memory (R-S04).
public struct RelayState: Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        case running
        case done
        case escalated
        /// A ceiling fired (`--max-rounds`, `--until`, or stagnation) — always carries
        /// `stoppedReason`.
        case stopped
        /// Pilot only (`pmMode == .external`, `docs/phases/Pilot_Relay.md` §2): parked
        /// between rounds, waiting on the piloting session's next `pilot handoff`. A
        /// **parked, UNOWNED** state — no process lives here, `RelayStateStore.save`
        /// never writes an `owner.pid` marker for it (only `.running` does), and
        /// `RelayCoordinator.reconcileOrphan`'s `.running`-only guard means orphan
        /// reconciliation always skips it. A pilot relay can sit `awaitingPM` for days;
        /// that is the mode's definition, not a bug.
        case awaitingPM
    }

    public var id: String
    public var projectRoot: String
    public var docPath: String
    public var pmWorkerId: String
    public var devWorkerId: String
    public var status: Status
    /// `spawned` (default) or `external` (Pilot). Legacy relays persisted before this
    /// field existed decode as `spawned` — the only mode that ever ran.
    public var pmMode: PMMode
    public var rounds: [RelayRound]
    public var createdAt: Date
    public var finishedAt: Date?
    /// The founder-facing text: the PM's closing summary when `done`, or the specific
    /// question the founder must answer when `escalated` — verbatim from
    /// `RelayVerdict.note` (or a coordinator-authored explanation for a structural failure
    /// that never reached a PM verdict, e.g. a dispatch error or a blocked handover).
    public var note: String?
    /// Set only when `status == .stopped` — which ceiling fired and why.
    public var stoppedReason: String?
    /// Injected via `--resume`: the founder's answer to an escalation, carried into the
    /// next PM turn's prompt context (`RelayPMPrompt.Context.founderNote`), then cleared
    /// once consumed.
    public var founderNote: String?
    /// Pilot only (`pmMode == .external`): the round ceiling set once at `pilot start`
    /// and re-read at every later `pilot handoff`. A spawned relay gets its ceiling
    /// fresh from `RelayCoordinator.Config` on every `run`/`resume` call (one
    /// long-lived process holds it); a pilot relay has no such process — each
    /// `handoff` is a brand-new CLI invocation — so the ceiling has to be durable.
    /// `nil` reads as the house default (20), matching `Config.maxRounds`'s default.
    public var pilotMaxRounds: Int?
    /// Pilot only: the stagnation cap set once at `pilot start`, same reasoning as
    /// `pilotMaxRounds`. `nil` reads as the house default (3), matching
    /// `Config.stagnationRoundCap`'s default.
    public var pilotStagnationRoundCap: Int?
    /// Pilot only (PO-F7): the dev-turn idle-timeout override set once at `pilot start`,
    /// same reasoning as `pilotMaxRounds` — each `pilot handoff` is a fresh CLI
    /// invocation with no long-lived `Config` to re-supply it. `nil` leaves the driver
    /// manifest's idle timeout untouched, matching `Config.devTurnIdleTimeoutSeconds`.
    public var pilotDevTurnIdleTimeoutSeconds: Int?
    /// PO-S03: set while this relay's dev turn is blocked on the per-root
    /// execution lane (FIFO ticket). Cleared when the lane is acquired or the
    /// wait ends. Status JSON surfaces this as `laneBlocked`.
    public var laneBlocked: ExecutionLaneTicket?

    public init(
        id: String,
        projectRoot: String,
        docPath: String,
        pmWorkerId: String,
        devWorkerId: String,
        status: Status,
        pmMode: PMMode = .spawned,
        rounds: [RelayRound] = [],
        createdAt: Date,
        finishedAt: Date? = nil,
        note: String? = nil,
        stoppedReason: String? = nil,
        founderNote: String? = nil,
        pilotMaxRounds: Int? = nil,
        pilotStagnationRoundCap: Int? = nil,
        pilotDevTurnIdleTimeoutSeconds: Int? = nil,
        laneBlocked: ExecutionLaneTicket? = nil
    ) {
        self.id = id
        self.projectRoot = projectRoot
        self.docPath = docPath
        self.pmWorkerId = pmWorkerId
        self.devWorkerId = devWorkerId
        self.status = status
        self.pmMode = pmMode
        self.rounds = rounds
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.note = note
        self.stoppedReason = stoppedReason
        self.founderNote = founderNote
        self.pilotMaxRounds = pilotMaxRounds
        self.pilotStagnationRoundCap = pilotStagnationRoundCap
        self.pilotDevTurnIdleTimeoutSeconds = pilotDevTurnIdleTimeoutSeconds
        self.laneBlocked = laneBlocked
    }

    /// Pilot only: the sentinel `pmWorkerId` stamped on an `external`-mode relay —
    /// there is no PM model to dispatch (the piloting session IS the PM), so this
    /// documents the field's meaning rather than leaving it a real, dispatchable
    /// worker id. Never resolved through `RunService`.
    public static let externalPMWorkerId = "external"

    // Lenient decode: tolerates relays persisted before later fields existed
    // (mirrors `FixPacket.init(from:)`'s partial-model tolerance).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectRoot = try c.decode(String.self, forKey: .projectRoot)
        docPath = try c.decode(String.self, forKey: .docPath)
        pmWorkerId = try c.decode(String.self, forKey: .pmWorkerId)
        devWorkerId = try c.decode(String.self, forKey: .devWorkerId)
        status = try c.decode(Status.self, forKey: .status)
        // Legacy decode: every relay persisted before Pilot existed only ever ran
        // `spawned` (Pilot_Relay.md §1 decision 1, PL-S01).
        pmMode = try c.decodeIfPresent(PMMode.self, forKey: .pmMode) ?? .spawned
        rounds = try c.decodeIfPresent([RelayRound].self, forKey: .rounds) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        stoppedReason = try c.decodeIfPresent(String.self, forKey: .stoppedReason)
        founderNote = try c.decodeIfPresent(String.self, forKey: .founderNote)
        pilotMaxRounds = try c.decodeIfPresent(Int.self, forKey: .pilotMaxRounds)
        pilotStagnationRoundCap = try c.decodeIfPresent(Int.self, forKey: .pilotStagnationRoundCap)
        pilotDevTurnIdleTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .pilotDevTurnIdleTimeoutSeconds)
        laneBlocked = try c.decodeIfPresent(ExecutionLaneTicket.self, forKey: .laneBlocked)
    }

    // MARK: - Orphan reconciliation (works-test hazard #1)

    /// Stamped as `stoppedReason` when a `.running` relay is reconciled after its
    /// owner process died mid-round (`RelayCoordinator.reconcileIfOrphaned`, mirroring
    /// `RunStore`'s owner.pid liveness signal + `PairCoordinator.reconcileStaleRunning`'s
    /// write-back-on-detection). A stable string, not a new field, so the wire contract
    /// (`RelayJSON.stoppedReason`) needs no shape change — CLI/MCP callers that only
    /// look at `status`/`stoppedReason` already see everything they need.
    public static let orphanReconciledReason = "owner process died mid-round (reconciled)"

    /// True for a relay reconciled by `reconcileIfOrphaned` rather than a ceiling
    /// (`--max-rounds`/`--until`/stagnation) firing — the ONLY kind of `.stopped` relay
    /// `relay-resume` accepts (PM_Relay.md works-test hazard #1: "escalated-only was
    /// too narrow" for `relay-resume`, but a ceiling stop is still a deliberate stop,
    /// never silently resumable).
    public var isReconciledStopped: Bool {
        status == .stopped && stoppedReason == Self.orphanReconciledReason
    }

    /// `relay-resume`'s eligibility gate: an `.escalated` relay (a real founder
    /// question) or a reconciled-stopped one (the process died — resuming continues
    /// from the last durable round). `.done` and a ceiling-`.stopped` relay are never
    /// resumable.
    public var isResumable: Bool {
        status == .escalated || isReconciledStopped
    }
}
