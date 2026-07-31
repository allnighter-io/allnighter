import Foundation

/// `alln loop start --dry-run` — the free twin (LVC v7 §1, LVC-S08). Resolves
/// the brief, spec, both seats, and project against live state without
/// spending quota, starting a worker, or writing anything.
public struct LoopStartDryRunJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var brief: String
    public var specPath: String?
    public var projectId: String
    public var projectRoot: String
    public var pm: Seat
    public var dev: Seat
    public var ready: Bool
    public var warnings: [String]
    public var nextAction: AgentNextAction

    /// One resolved seat — `occupant` is `"caller"` or a canonical agent id.
    public struct Seat: Codable, Sendable, Equatable {
        public var occupant: String
        /// `explicit` (named on the command line), `caller`, `tier:frontier`, or `tier:balanced`.
        public var source: String

        public init(occupant: String, source: String) {
            self.occupant = occupant
            self.source = source
        }
    }

    public init(
        schemaVersion: Int = 1,
        brief: String,
        specPath: String?,
        projectId: String,
        projectRoot: String,
        pm: Seat,
        dev: Seat,
        ready: Bool,
        warnings: [String],
        nextAction: AgentNextAction
    ) {
        self.schemaVersion = schemaVersion
        self.brief = brief
        self.specPath = specPath
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.pm = pm
        self.dev = dev
        self.ready = ready
        self.warnings = warnings
        self.nextAction = nextAction
    }
}
