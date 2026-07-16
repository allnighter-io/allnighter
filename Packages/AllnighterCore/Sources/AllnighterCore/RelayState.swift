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
        outcome: Outcome? = nil
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
    }

    public var id: String
    public var projectRoot: String
    public var docPath: String
    public var pmWorkerId: String
    public var devWorkerId: String
    public var status: Status
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
    /// Mirrors `RelayCoordinator.Config.pmMayMutate` (PM_Relay.md §4.2) — persisted so a
    /// `--pm-read-only` relay's guarantee survives `--resume` instead of silently
    /// reverting to mutating (the resume path re-derives every other config field —
    /// `projectRoot`/`docPath`/`pmWorkerId`/`devWorkerId` — from THIS persisted state
    /// rather than the resume call's fresh `Config`; this field follows the same rule).
    /// Defaults `true` on decode for relays persisted before this field existed.
    public var pmMayMutate: Bool

    public init(
        id: String,
        projectRoot: String,
        docPath: String,
        pmWorkerId: String,
        devWorkerId: String,
        status: Status,
        rounds: [RelayRound] = [],
        createdAt: Date,
        finishedAt: Date? = nil,
        note: String? = nil,
        stoppedReason: String? = nil,
        founderNote: String? = nil,
        pmMayMutate: Bool = true
    ) {
        self.id = id
        self.projectRoot = projectRoot
        self.docPath = docPath
        self.pmWorkerId = pmWorkerId
        self.devWorkerId = devWorkerId
        self.status = status
        self.rounds = rounds
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.note = note
        self.stoppedReason = stoppedReason
        self.founderNote = founderNote
        self.pmMayMutate = pmMayMutate
    }

    // Lenient decode: `pmMayMutate` defaults to `true` for relays persisted before this
    // field existed (mirrors `FixPacket.init(from:)`'s partial-model tolerance).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectRoot = try c.decode(String.self, forKey: .projectRoot)
        docPath = try c.decode(String.self, forKey: .docPath)
        pmWorkerId = try c.decode(String.self, forKey: .pmWorkerId)
        devWorkerId = try c.decode(String.self, forKey: .devWorkerId)
        status = try c.decode(Status.self, forKey: .status)
        rounds = try c.decodeIfPresent([RelayRound].self, forKey: .rounds) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        stoppedReason = try c.decodeIfPresent(String.self, forKey: .stoppedReason)
        founderNote = try c.decodeIfPresent(String.self, forKey: .founderNote)
        pmMayMutate = try c.decodeIfPresent(Bool.self, forKey: .pmMayMutate) ?? true
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
