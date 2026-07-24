import Foundation

/// Wire shape for one panel seat on the roster (`docs/phases/Pilot_Panel.md` PN-S04).
public struct PanelSeatJSON: Codable, Equatable, Sendable {
    public var workerId: String
    public var lens: String
    public init(workerId: String, lens: String) {
        self.workerId = workerId
        self.lens = lens
    }

    public init(_ seat: PanelSeat) {
        self.workerId = seat.workerId
        self.lens = seat.lens
    }
}

/// Wire shape for one structured finding.
public struct FindingJSON: Codable, Equatable, Sendable {
    public var claim: String
    public var severity: String
    public var evidence: String
    public var proposedChange: String?

    public init(_ finding: Finding) {
        self.claim = finding.claim
        self.severity = finding.severity.rawValue
        self.evidence = finding.evidence
        self.proposedChange = finding.proposedChange
    }
}

/// Wire shape for one seat's settled result.
public struct SeatResultJSON: Codable, Equatable, Sendable {
    public var workerId: String
    public var lens: String
    public var status: String
    public var findings: [FindingJSON]?
    public var noMaterialFindings: Bool
    public var reason: String?
    public var report: String
    public var runId: String?

    public init(_ result: SeatResult) {
        self.workerId = result.workerId
        self.lens = result.lens
        self.status = result.status.rawValue
        self.findings = result.findings?.map(FindingJSON.init)
        self.noMaterialFindings = result.noMaterialFindings
        self.reason = result.reason
        self.report = result.report
        self.runId = result.runId
    }
}

/// Wire shape for one panel round (merged seat results + attempt count).
public struct PanelRoundLogEntry: Codable, Equatable, Sendable {
    public var round: Int
    /// `running | complete | partial | failed` — result of this round, distinct
    /// from the long-lived panel session status.
    public var outcome: String?
    public var targetHash: String
    public var briefSource: String
    public var attemptCount: Int
    public var seatResults: [SeatResultJSON]
    /// Worker ids with `status == done && findings == nil` (done-but-unstructured).
    /// Derived at envelope-build time — always present (`[]` when clean).
    public var unstructuredSeats: [String]

    public init(_ round: PanelRound) {
        self.round = round.roundNumber
        self.outcome = PanelRoundOutcome.project(from: round)
        self.targetHash = round.targetHash
        self.briefSource = round.briefSource.rawValue
        self.attemptCount = max(1, round.attempts.count)
        self.seatResults = round.seatResults.map(SeatResultJSON.init)
        self.unstructuredSeats = PanelUnstructuredSeats.project(from: round.seatResults)
    }
}

/// Honest round-level projection. The panel session parks at `awaitingPM` after
/// every settled round so the user can rerun; this value says whether that
/// particular review actually produced results.
public enum PanelRoundOutcome {
    public static func project(from round: PanelRound) -> String {
        if round.finishedAt == nil || round.seatResults.contains(where: { $0.status == .running }) {
            return "running"
        }
        let completed = round.seatResults.filter { $0.status == .done }.count
        if completed == round.seatResults.count, completed > 0 { return "complete" }
        if completed > 0 { return "partial" }
        return "failed"
    }
}

/// Derived projection: worker ids whose seat result is done-but-unstructured
/// (`status == done && findings == nil`). Never stored on `PanelState`.
public enum PanelUnstructuredSeats {
    public static func project(from results: [SeatResult]) -> [String] {
        results
            .filter { $0.status == .done && $0.findings == nil }
            .map(\.workerId)
    }
}

/// One path-overlap convergence entry (`docs/phases/Panel_Polish.md` §1 decision 4).
/// Flag only — no scores, no importance ordering.
public struct PanelConvergenceJSON: Codable, Equatable, Sendable {
    public var anchor: String
    public var seats: [String]

    public init(anchor: String, seats: [String]) {
        self.anchor = anchor
        self.seats = seats
    }
}

/// `PanelJSON` — public machine contract for `alln panel status|watch|done|start`
/// (`docs/phases/Pilot_Panel.md` PN-S04). Thin projection of `PanelState`.
public struct PanelJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var panelId: String
    /// `awaitingPM | running | done`
    public var status: String
    public var targetPath: String
    public var targetHash: String?
    public var teamId: String?
    public var roster: [PanelSeatJSON]
    public var rounds: Int
    public var maxRounds: Int
    public var roundLog: [PanelRoundLogEntry]
    public var note: String?

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        panelId: String,
        status: String,
        targetPath: String,
        targetHash: String? = nil,
        teamId: String? = nil,
        roster: [PanelSeatJSON],
        rounds: Int,
        maxRounds: Int,
        roundLog: [PanelRoundLogEntry],
        note: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.panelId = panelId
        self.status = status
        self.targetPath = targetPath
        self.targetHash = targetHash
        self.teamId = teamId
        self.roster = roster
        self.rounds = rounds
        self.maxRounds = maxRounds
        self.roundLog = roundLog
        self.note = note
    }

    public static func project(
        _ state: PanelState,
        contractVersion: String,
        targetHash: String? = nil
    ) -> PanelJSON {
        let hash = targetHash
            ?? state.rounds.last?.targetHash
            ?? PanelState.contentHash(
                ofFileAt: PanelCoordinatorTarget.resolve(state.targetPath, projectRoot: state.projectRoot)
            )
        return PanelJSON(
            contractVersion: contractVersion,
            panelId: state.id,
            status: state.status.rawValue,
            targetPath: state.targetPath,
            targetHash: hash,
            teamId: state.teamId,
            roster: state.seats.map(PanelSeatJSON.init),
            rounds: state.rounds.count,
            maxRounds: state.maxRounds,
            roundLog: state.rounds.map(PanelRoundLogEntry.init),
            note: state.note
        )
    }
}

/// `PanelRoundJSON` — envelope for a settled `panel round` (`--json`).
public struct PanelRoundJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var panel: PanelJSON
    public var round: Int
    public var attempt: Int
    /// `complete | partial | failed` for this settled round.
    public var outcome: String?
    public var targetHash: String
    public var briefSource: String
    public var seatResults: [SeatResultJSON]
    /// Worker ids with `status == done && findings == nil` (done-but-unstructured).
    /// Derived at envelope-build time — always present (`[]` when clean).
    public var unstructuredSeats: [String]
    /// Path-overlap anchors cited by ≥2 distinct seats. Always present (`[]` when none).
    public var convergence: [PanelConvergenceJSON]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        panel: PanelJSON,
        round: Int,
        attempt: Int,
        outcome: String? = nil,
        targetHash: String,
        briefSource: String,
        seatResults: [SeatResultJSON],
        unstructuredSeats: [String],
        convergence: [PanelConvergenceJSON] = []
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.panel = panel
        self.round = round
        self.attempt = attempt
        self.outcome = outcome
        self.targetHash = targetHash
        self.briefSource = briefSource
        self.seatResults = seatResults
        self.unstructuredSeats = unstructuredSeats
        self.convergence = convergence
    }
}

/// `panel start --json` envelope.
public struct PanelStartJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var panel: PanelJSON
    public var roster: [PanelSeatJSON]
    public var targetHash: String
    public var dirtyTargetAdvisory: String?
    public var scaffoldPath: String
    public var nextCommand: String
    public var teamId: String?
    public var rememberedTeam: Bool?

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        panel: PanelJSON,
        roster: [PanelSeatJSON],
        targetHash: String,
        dirtyTargetAdvisory: String? = nil,
        scaffoldPath: String,
        nextCommand: String,
        teamId: String? = nil,
        rememberedTeam: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.panel = panel
        self.roster = roster
        self.targetHash = targetHash
        self.dirtyTargetAdvisory = dirtyTargetAdvisory
        self.scaffoldPath = scaffoldPath
        self.nextCommand = nextCommand
        self.teamId = teamId
        self.rememberedTeam = rememberedTeam
    }
}

/// NDJSON progress line for a blocking `panel round`.
public struct PanelProgressJSON: Codable, Equatable, Sendable {
    public var event: String
    public var seat: String?
    public var round: Int?
    public var attempt: Int?
    public var status: String?

    public init(event: String, seat: String? = nil, round: Int? = nil, attempt: Int? = nil, status: String? = nil) {
        self.event = event
        self.seat = seat
        self.round = round
        self.attempt = attempt
        self.status = status
    }
}

/// Path resolution shared with the engine without importing AllnighterEngine from Core.
/// Duplicates `PanelCoordinator.resolveTargetPath` so `PanelJSON` can pin a hash.
enum PanelCoordinatorTarget {
    static func resolve(_ path: String, projectRoot: String) -> String {
        if path.hasPrefix("/") { return path }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(path).path
    }
}
