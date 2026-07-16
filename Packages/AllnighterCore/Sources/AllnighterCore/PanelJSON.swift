import Foundation

/// Wire shape for one panel seat on the roster (`docs/phases/Pilot_Panel.md` PN-S04).
public struct PanelSeatJSON: Codable, Equatable, Sendable {
    public var workerId: String
    public var lens: String
    /// `driverReadOnly` | `clone` — echoed on `panel start` roster block (PN-S06 / works-test).
    public var isolationMode: String?

    public init(workerId: String, lens: String, isolationMode: String? = nil) {
        self.workerId = workerId
        self.lens = lens
        self.isolationMode = isolationMode
    }

    public init(_ seat: PanelSeat, isolationMode: String? = nil) {
        self.workerId = seat.workerId
        self.lens = seat.lens
        self.isolationMode = isolationMode
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
    public var targetHash: String
    public var briefSource: String
    public var attemptCount: Int
    public var seatResults: [SeatResultJSON]

    public init(_ round: PanelRound) {
        self.round = round.roundNumber
        self.targetHash = round.targetHash
        self.briefSource = round.briefSource.rawValue
        self.attemptCount = max(1, round.attempts.count)
        self.seatResults = round.seatResults.map(SeatResultJSON.init)
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
        targetHash: String? = nil,
        isolationBySeat: [String: String]? = nil
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
            roster: state.seats.map {
                PanelSeatJSON($0, isolationMode: isolationBySeat?[$0.workerId])
            },
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
    public var targetHash: String
    public var briefSource: String
    public var seatResults: [SeatResultJSON]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        panel: PanelJSON,
        round: Int,
        attempt: Int,
        targetHash: String,
        briefSource: String,
        seatResults: [SeatResultJSON]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.panel = panel
        self.round = round
        self.attempt = attempt
        self.targetHash = targetHash
        self.briefSource = briefSource
        self.seatResults = seatResults
    }
}

/// Per-seat isolation mode echoed on `panel start` (PN-S06).
public struct PanelSeatIsolationJSON: Codable, Equatable, Sendable {
    public var workerId: String
    /// `driverReadOnly` | `clone`
    public var mode: String
    public var driverId: String?
    public var advisory: String?

    public init(workerId: String, mode: String, driverId: String? = nil, advisory: String? = nil) {
        self.workerId = workerId
        self.mode = mode
        self.driverId = driverId
        self.advisory = advisory
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
    /// Per-seat isolation mode (driver RO args on real root vs ephemeral clone).
    public var isolation: [PanelSeatIsolationJSON]?

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
        rememberedTeam: Bool? = nil,
        isolation: [PanelSeatIsolationJSON]? = nil
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
        self.isolation = isolation
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
