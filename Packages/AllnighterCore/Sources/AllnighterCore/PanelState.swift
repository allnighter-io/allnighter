import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// One structured finding from a panel seat (`docs/phases/Pilot_Panel.md` §1 decision 3).
/// Shape only — content judgment is the session's. Severity stays a closed 3-value set.
public struct Finding: Sendable, Codable, Equatable {
    public enum Severity: String, Sendable, Codable, CaseIterable {
        case low, medium, high
    }

    public var claim: String
    public var severity: Severity
    /// Cite file/line or quote — the seat's evidence, not Allnighter's judgment.
    public var evidence: String
    public var proposedChange: String?

    public init(
        claim: String,
        severity: Severity,
        evidence: String,
        proposedChange: String? = nil
    ) {
        self.claim = claim
        self.severity = severity
        self.evidence = evidence
        self.proposedChange = proposedChange
    }
}

/// One seat's settled result for a panel round. Verbatim report is always kept;
/// structured findings are best-effort (unparseable → findings nil, status still `.done`).
public struct SeatResult: Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        case done
        case failed
        case timedOut
        case empty
    }

    public var workerId: String
    public var lens: String
    public var status: Status
    /// Parsed findings when the seat ended with a valid schema block; `nil` when the
    /// report is present but unstructured (done-but-unstructured — never discarded).
    public var findings: [Finding]?
    /// First-class valid answer when the seat honestly found nothing material.
    public var noMaterialFindings: Bool
    public var reason: String?
    /// Verbatim raw seat report — never discarded, even when findings fail to parse.
    public var report: String
    public var runId: String?

    public init(
        workerId: String,
        lens: String,
        status: Status,
        findings: [Finding]? = nil,
        noMaterialFindings: Bool = false,
        reason: String? = nil,
        report: String = "",
        runId: String? = nil
    ) {
        self.workerId = workerId
        self.lens = lens
        self.status = status
        self.findings = findings
        self.noMaterialFindings = noMaterialFindings
        self.reason = reason
        self.report = report
        self.runId = runId
    }
}

/// One dispatch attempt within a panel round (`docs/phases/Pilot_Panel.md` PN-S03).
/// A full round starts as attempt 1. A `--seats a,b` rerun appends an attempt on the
/// **same** round (never a new round number) and REPLACE those seats' results in the
/// round's merged `seatResults`. Partial failures stay on the ledger.
public struct PanelRoundAttempt: Sendable, Codable, Equatable {
    public var attemptNumber: Int
    /// Worker ids this attempt dispatched; `nil` means the full roster for the round.
    public var seatFilter: [String]?
    /// SHA256 hex of the target file bytes, pinned at this attempt's dispatch.
    public var targetHash: String
    public var brief: String
    public var briefSource: PanelRound.BriefSource
    public var seatResults: [SeatResult]
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        attemptNumber: Int,
        seatFilter: [String]? = nil,
        targetHash: String,
        brief: String,
        briefSource: PanelRound.BriefSource,
        seatResults: [SeatResult] = [],
        startedAt: Date,
        finishedAt: Date? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.seatFilter = seatFilter
        self.targetHash = targetHash
        self.brief = brief
        self.briefSource = briefSource
        self.seatResults = seatResults
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// One panel round: pins the target's content hash at dispatch (panel analog of the
/// relay's `baselineHead`) and records every seat's result. Reruns of a subset of
/// seats land as additional `attempts` on this same round.
public struct PanelRound: Sendable, Codable, Equatable {
    public enum BriefSource: String, Sendable, Codable, CaseIterable {
        case builtin
        case custom
    }

    public var roundNumber: Int
    /// SHA256 hex of the target file bytes, pinned at the latest dispatch for this round.
    public var targetHash: String
    /// Verbatim brief text the seats saw on the latest attempt.
    public var brief: String
    public var briefSource: BriefSource
    /// Merged seat results: latest result per seat after any `--seats` reruns.
    public var seatResults: [SeatResult]
    /// Per-attempt history. Attempt 1 is the full-round dispatch; later attempts are
    /// seat-subset reruns that REPLACE those seats in `seatResults`.
    public var attempts: [PanelRoundAttempt]
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        roundNumber: Int,
        targetHash: String,
        brief: String,
        briefSource: BriefSource,
        seatResults: [SeatResult] = [],
        attempts: [PanelRoundAttempt] = [],
        startedAt: Date,
        finishedAt: Date? = nil
    ) {
        self.roundNumber = roundNumber
        self.targetHash = targetHash
        self.brief = brief
        self.briefSource = briefSource
        self.seatResults = seatResults
        self.attempts = attempts
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case roundNumber, targetHash, brief, briefSource, seatResults, attempts, startedAt, finishedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roundNumber = try c.decode(Int.self, forKey: .roundNumber)
        targetHash = try c.decode(String.self, forKey: .targetHash)
        brief = try c.decode(String.self, forKey: .brief)
        briefSource = try c.decode(BriefSource.self, forKey: .briefSource)
        seatResults = try c.decode([SeatResult].self, forKey: .seatResults)
        attempts = try c.decodeIfPresent([PanelRoundAttempt].self, forKey: .attempts) ?? []
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    }
}

/// One seat on a panel roster (worker + lens, optional standing lens instruction).
public struct PanelSeat: Sendable, Codable, Equatable {
    public var workerId: String
    public var lens: String
    public var lensInstruction: String?

    public init(workerId: String, lens: String, lensInstruction: String? = nil) {
        self.workerId = workerId
        self.lens = lens
        self.lensInstruction = lensInstruction
    }
}

/// One Panel session — session-led blind jury on any target (`docs/phases/Pilot_Panel.md`).
/// State machine mirrors Pilot: `awaitingPM | running | done`; parked-unowned between
/// rounds (orphan reconcile skips `awaitingPM`).
public struct PanelState: Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        case awaitingPM
        case running
        case done
    }

    public var id: String
    public var projectRoot: String
    public var projectId: String
    /// The `--doc` target path (any path the session judges — not hard-coded to phases/).
    public var targetPath: String
    public var teamId: String?
    public var seats: [PanelSeat]
    public var status: Status
    public var maxRounds: Int
    public var rounds: [PanelRound]
    public var createdAt: Date
    public var finishedAt: Date?
    public var note: String?

    public init(
        id: String,
        projectRoot: String,
        projectId: String,
        targetPath: String,
        teamId: String? = nil,
        seats: [PanelSeat],
        status: Status = .awaitingPM,
        maxRounds: Int = 10,
        rounds: [PanelRound] = [],
        createdAt: Date,
        finishedAt: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.projectRoot = projectRoot
        self.projectId = projectId
        self.targetPath = targetPath
        self.teamId = teamId
        self.seats = seats
        self.status = status
        self.maxRounds = maxRounds
        self.rounds = rounds
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.note = note
    }

    /// Mint a panel id: `panel_<uuid>`.
    public static func makeId() -> String {
        "panel_\(UUID().uuidString.lowercased())"
    }

    /// Stamped as `note` when a `.running` panel is reconciled after its owner process
    /// died mid-round — stable string so callers can detect reconciled panels without a
    /// new field (mirrors `RelayState.orphanReconciledReason`).
    public static let orphanReconciledNote = "owner process died mid-round (reconciled)"

    /// SHA256 hex of raw file bytes — the run-truth anchor pinned at dispatch
    /// (panel analog of the relay's baseline HEAD).
    public static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 hex of the target file at `path`, or `nil` when unreadable.
    public static func contentHash(ofFileAt path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return contentHash(of: data)
    }
}
