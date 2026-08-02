import Foundation

/// Free twin JSON for `alln loop * --dry-run` (LVC v7 §1, LVC-S08; LOOP-TWIN).
/// Shared by `loop start`, `loop resume`, `loop step`, and `loop pm` — one schema,
/// not a fourth dry-run shape. Resolves seats/payload/project against live state
/// without spending quota, starting a worker, or mutating durable loop/run state.
///
/// Field mapping for non-start verbs:
/// - `brief` — the payload that would be used (founder answer / step message /
///   PM reassignment description)
/// - `specPath` / `project*` / `pm` / `dev` — resolved from the existing loop
///   (or from start flags for `loop start`)
/// - `ready` — whether the real verb can proceed from current durable state
/// - `warnings` — illegal state, missing loop, write-lock hold, seat issues
/// - `nextAction.command` — the real (spending) invocation without `--dry-run`
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
