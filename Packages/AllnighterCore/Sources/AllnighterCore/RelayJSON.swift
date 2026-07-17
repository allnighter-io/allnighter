import Foundation

/// `RelayJSON` — the public machine contract for `alln pair relay` /
/// `pair relay-status` / `pair relay-resume` and their MCP projections
/// (docs/phases/PM_Relay.md §6 R-S05/R-S06, §7 works-test output shape). A thin,
/// versioned projection of `RelayState` — the durable truth stays in
/// `RelayState`/`RelayStateStore`; this is never a second copy of run-truth, only
/// its wire shape (mirrors `ProjectJSON`'s schemaVersion + contractVersion style).
public struct RelayJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var relayId: String
    /// `RelayState.Status` raw value: running | done | escalated | stopped | awaitingPM
    /// (`awaitingPM` is Pilot only — a parked relay between `pilot handoff` calls).
    public var status: String
    /// `RelayState.PMMode` raw value: spawned | external. `external` is Pilot
    /// (`docs/phases/Pilot_Relay.md`) — a live session outside Allnighter holds the
    /// PM seat; `spawned` is the shipped PM Relay.
    public var pmMode: String
    public var rounds: Int
    /// The last round's `RelayVerdict.Verdict` raw value (continue | done | escalate),
    /// or nil before any round has produced one.
    public var verdict: String?
    /// Founder-facing text: closing summary (`done`) or the question to answer
    /// (`escalated`) — verbatim from `RelayState.note`.
    public var note: String?
    public var roundLog: [RelayRoundLogEntry]
    public var docPath: String
    public var pmWorkerId: String
    public var devWorkerId: String
    /// Set only when `status == "stopped"` — which ceiling fired and why.
    public var stoppedReason: String?
    /// PO-S03: present while this relay's dev turn holds a FIFO ticket on the
    /// per-root execution lane (harness-owned wait; agents must not busy-loop).
    public var laneBlocked: ExecutionLaneTicket?

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        relayId: String,
        status: String,
        pmMode: String = "spawned",
        rounds: Int,
        verdict: String? = nil,
        note: String? = nil,
        roundLog: [RelayRoundLogEntry],
        docPath: String,
        pmWorkerId: String,
        devWorkerId: String,
        stoppedReason: String? = nil,
        laneBlocked: ExecutionLaneTicket? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.relayId = relayId
        self.status = status
        self.pmMode = pmMode
        self.rounds = rounds
        self.verdict = verdict
        self.note = note
        self.roundLog = roundLog
        self.docPath = docPath
        self.pmWorkerId = pmWorkerId
        self.devWorkerId = devWorkerId
        self.stoppedReason = stoppedReason
        self.laneBlocked = laneBlocked
    }

    /// Projects a durable `RelayState` to its wire shape. The one place CLI and MCP
    /// both call, so `alln pair relay` output and MCP `pair_relay` output can never
    /// drift (Agent-First Product Law: MCP never richer than the CLI).
    public static func project(_ state: RelayState, contractVersion: String) -> RelayJSON {
        RelayJSON(
            contractVersion: contractVersion,
            relayId: state.id,
            status: state.status.rawValue,
            pmMode: state.pmMode.rawValue,
            rounds: state.rounds.count,
            verdict: state.rounds.last?.verdict?.verdict.rawValue,
            note: state.note,
            roundLog: state.rounds.map(RelayRoundLogEntry.init),
            docPath: state.docPath,
            pmWorkerId: state.pmWorkerId,
            devWorkerId: state.devWorkerId,
            stoppedReason: state.stoppedReason,
            laneBlocked: state.laneBlocked
        )
    }
}

/// One round's wire shape (PM_Relay.md §7: `{ round, baseline, head, pmRunId,
/// devRunId, verdict, gate }`). A projection of `RelayRound` — never a second
/// durable copy.
public struct RelayRoundLogEntry: Codable, Equatable, Sendable {
    public var round: Int
    /// git HEAD pinned before this round's PM turn.
    public var baseline: String?
    /// git HEAD pinned after this round's dev turn (nil until the dev turn finishes).
    public var head: String?
    public var pmRunId: String?
    public var devRunId: String?
    /// This round's `RelayVerdict.Verdict` raw value, or nil if the round never
    /// reached a parsed verdict (e.g. a dispatch failure).
    public var verdict: String?
    public var gate: RelayGateSummary?
    /// Pilot only: count of `GitObserver.dirtyFiles` at `handoff` time
    /// (`RelayRound.dirtyFiles`) — a count, not the paths themselves, to keep the
    /// envelope small; `nil` for a spawned round (the field was never captured).
    public var dirtyFilesCount: Int?
    /// Pilot only: whether this round carries an `externalSubmission` (the piloting
    /// session's raw markdown, verbatim) — a presence flag, not the text itself, so
    /// the round log stays a compact log, not a second copy of run-truth. Always
    /// `false` for a spawned round.
    public var hasExternalSubmission: Bool
    /// PO-S02: `DevTurnEndReason` raw value stamped when the dev turn ended, or nil
    /// when the round never reached (or finished) a dev turn. Never inferred.
    public var endReason: String?
    /// PO-S04: harness-owned proof-of-record results (command, exit, durationMs, tail).
    /// Empty array when no proofs ran. Always present on the wire for stable shape.
    public var proofResults: [HarnessProofResult]
    /// PO-S06: declared write scope for the dev turn (`nil` = legacy full-scope + build).
    public var writeScope: TurnWriteScope?
    /// PO-S06: present when commit-diff found paths outside declared writeScope.
    /// `endReason` stays `reported`; PM decides — harness never auto-reverts.
    public var scopeViolation: ScopeViolation?

    public init(
        round: Int,
        baseline: String? = nil,
        head: String? = nil,
        pmRunId: String? = nil,
        devRunId: String? = nil,
        verdict: String? = nil,
        gate: RelayGateSummary? = nil,
        dirtyFilesCount: Int? = nil,
        hasExternalSubmission: Bool = false,
        endReason: String? = nil,
        proofResults: [HarnessProofResult] = [],
        writeScope: TurnWriteScope? = nil,
        scopeViolation: ScopeViolation? = nil
    ) {
        self.round = round
        self.baseline = baseline
        self.head = head
        self.pmRunId = pmRunId
        self.devRunId = devRunId
        self.verdict = verdict
        self.gate = gate
        self.dirtyFilesCount = dirtyFilesCount
        self.hasExternalSubmission = hasExternalSubmission
        self.endReason = endReason
        self.proofResults = proofResults
        self.writeScope = writeScope
        self.scopeViolation = scopeViolation
    }

    public init(_ round: RelayRound) {
        self.init(
            round: round.roundNumber,
            baseline: round.baselineHead,
            head: round.headAfterDev,
            pmRunId: round.pmRunId,
            devRunId: round.devRunId,
            verdict: round.verdict?.verdict.rawValue,
            gate: round.gate,
            dirtyFilesCount: round.dirtyFiles?.count,
            hasExternalSubmission: round.externalSubmission != nil,
            endReason: round.devTurnEndReason?.rawValue,
            proofResults: round.proofResults,
            writeScope: round.writeScope,
            scopeViolation: round.scopeViolation
        )
    }
}

/// NDJSON progress events emitted during `alln pair relay --json` before the final
/// `RelayJSON` envelope (mirrors `PairQueueProgressJSON`). The wire shape only —
/// the mapping from `RelayCoordinator.RelayEvent` lives in `AllnighterCLI` (that
/// type is Engine-only; this type is Core so CLI and MCP share one contract).
public struct RelayProgressJSON: Codable, Equatable, Sendable {
    public var contractVersion: String
    /// roundStarted | pmTurnFinished | gateBlocked | devTurnFinished | escalated | done | stopped
    public var event: String
    public var round: Int?
    /// Present on `pmTurnFinished`: continue | done | escalate.
    public var verdict: String?
    /// Present on `gateBlocked`.
    public var dangerClass: String?
    /// Present on `gateBlocked` (the gate's reason) or `stopped` (the ceiling reason).
    public var reason: String?
    /// Present on `escalated`/`done` — the founder-facing text.
    public var note: String?

    public init(
        contractVersion: String,
        event: String,
        round: Int? = nil,
        verdict: String? = nil,
        dangerClass: String? = nil,
        reason: String? = nil,
        note: String? = nil
    ) {
        self.contractVersion = contractVersion
        self.event = event
        self.round = round
        self.verdict = verdict
        self.dangerClass = dangerClass
        self.reason = reason
        self.note = note
    }
}
