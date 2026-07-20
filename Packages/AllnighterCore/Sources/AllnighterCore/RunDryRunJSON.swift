import Foundation

/// `alln run --dry-run` probe (AE-S04). Resolves project/worker/auth/mutating/shape
/// and write-lock state without dispatch. Exit 0 always; `canStart` carries the verdict.
public struct RunDryRunJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var canStart: Bool
    public var blockedReason: String?
    public var projectId: String?
    public var projectRoot: String?
    public var teamPresetId: String?
    public var teamDisplayName: String?
    public var workerId: String?
    public var mutating: Bool
    public var lane: String?
    public var counts: Counts
    public var writeLockHeld: Bool?
    public var warnings: [String]
    public var nextAction: AgentNextAction

    public struct Counts: Codable, Sendable, Equatable {
        public var readyWorkers: Int
        public var blockedWorkers: Int
        public var resolvedSourceIds: Int
        public var seatCount: Int

        public init(readyWorkers: Int, blockedWorkers: Int, resolvedSourceIds: Int, seatCount: Int) {
            self.readyWorkers = readyWorkers
            self.blockedWorkers = blockedWorkers
            self.resolvedSourceIds = resolvedSourceIds
            self.seatCount = seatCount
        }
    }

    public init(
        schemaVersion: Int = 1,
        canStart: Bool,
        blockedReason: String? = nil,
        projectId: String? = nil,
        projectRoot: String? = nil,
        teamPresetId: String? = nil,
        teamDisplayName: String? = nil,
        workerId: String? = nil,
        mutating: Bool = false,
        lane: String? = nil,
        counts: Counts = .init(readyWorkers: 0, blockedWorkers: 0, resolvedSourceIds: 0, seatCount: 0),
        writeLockHeld: Bool? = nil,
        warnings: [String] = [],
        nextAction: AgentNextAction
    ) {
        self.schemaVersion = schemaVersion
        self.canStart = canStart
        self.blockedReason = blockedReason
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.teamPresetId = teamPresetId
        self.teamDisplayName = teamDisplayName
        self.workerId = workerId
        self.mutating = mutating
        self.lane = lane
        self.counts = counts
        self.writeLockHeld = writeLockHeld
        self.warnings = warnings
        self.nextAction = nextAction
    }
}
