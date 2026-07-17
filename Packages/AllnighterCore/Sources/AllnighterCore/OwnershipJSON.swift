import Foundation

/// Machine envelope for `alln ps --json` (PO-S05). Read-only ownership
/// inventory: every process tree Allnighter owns, from durable state only.
/// Schema-backed per agent-first law — never free-text-only returns.
public struct OwnershipPsJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var countedAt: Date
    public var processCount: Int
    public var processes: [OwnershipProcessJSON]

    public init(
        schemaVersion: Int = 1,
        countedAt: Date,
        processes: [OwnershipProcessJSON]
    ) {
        self.schemaVersion = schemaVersion
        self.countedAt = countedAt
        self.processCount = processes.count
        self.processes = processes
    }
}

/// One owned process tree in the `alln ps` inventory.
public struct OwnershipProcessJSON: Codable, Sendable, Equatable {
    /// Stable work id (run id, relay id, or harness-proof claim id).
    public var id: String
    /// `run` | `relay` | `pilot` | `proof`
    public var kind: String
    public var projectRoot: String?
    /// Durable owner-of-record when present (`ProcessOwnerRecord` wire form).
    public var identity: ProcessOwnerRecord?
    /// pid alive AND startTimeTicks match. Recycled pids read false.
    public var identityAlive: Bool
    /// True when explicit reconcile WOULD reap this tree (identity-dead owner,
    /// non-terminal). `ps` never kills — this is the read-only would-reap report.
    public var wouldReconcile: Bool
    /// Lane snapshot for this root: held / ticket / none.
    public var lane: OwnershipLaneJSON?
    public var lastProgressAt: Date?
    /// Seconds since `lastProgressAt` (nil when no progress heartbeat).
    public var heartbeatAgeSeconds: Double?
    /// Stamped end reason when terminal (`completed|failed|cancelled|reconciledOrphan|killed|…`).
    public var endReason: String?
    /// Durable status string when available (run status, relay status).
    public var status: String?

    public init(
        id: String,
        kind: String,
        projectRoot: String? = nil,
        identity: ProcessOwnerRecord? = nil,
        identityAlive: Bool,
        wouldReconcile: Bool,
        lane: OwnershipLaneJSON? = nil,
        lastProgressAt: Date? = nil,
        heartbeatAgeSeconds: Double? = nil,
        endReason: String? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.projectRoot = projectRoot
        self.identity = identity
        self.identityAlive = identityAlive
        self.wouldReconcile = wouldReconcile
        self.lane = lane
        self.lastProgressAt = lastProgressAt
        self.heartbeatAgeSeconds = heartbeatAgeSeconds
        self.endReason = endReason
        self.status = status
    }
}

/// Per-root execution-lane state attached to an ownership row (PO-S03).
public struct OwnershipLaneJSON: Codable, Sendable, Equatable {
    /// `held` | `ticket` | `none`
    public var state: String
    public var holderId: String?
    public var holderKind: String?
    public var heldSinceSeconds: Double?
    /// 1-based FIFO position when `state == ticket`.
    public var ticketPosition: Int?

    public init(
        state: String,
        holderId: String? = nil,
        holderKind: String? = nil,
        heldSinceSeconds: Double? = nil,
        ticketPosition: Int? = nil
    ) {
        self.state = state
        self.holderId = holderId
        self.holderKind = holderKind
        self.heldSinceSeconds = heldSinceSeconds
        self.ticketPosition = ticketPosition
    }
}

/// Machine envelope for `alln kill --json` (single id or `--all`).
public struct OwnershipKillJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var killedCount: Int
    public var killed: [OwnershipKillRowJSON]
    public var skipped: [OwnershipKillSkipJSON]

    public init(
        schemaVersion: Int = 1,
        killed: [OwnershipKillRowJSON],
        skipped: [OwnershipKillSkipJSON] = []
    ) {
        self.schemaVersion = schemaVersion
        self.killedCount = killed.count
        self.killed = killed
        self.skipped = skipped
    }
}

public struct OwnershipKillRowJSON: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var endReason: String
    public var signalled: Bool

    public init(id: String, kind: String, endReason: String = "killed", signalled: Bool) {
        self.id = id
        self.kind = kind
        self.endReason = endReason
        self.signalled = signalled
    }
}

public struct OwnershipKillSkipJSON: Codable, Sendable, Equatable {
    public var id: String
    public var reason: String

    public init(id: String, reason: String) {
        self.id = id
        self.reason = reason
    }
}

/// Typed kill refusals (PO-S05). Mapped to catalog error codes at the CLI.
public enum OwnershipKillError: Error, Sendable, Equatable {
    case notFound(id: String)
    case alreadyTerminal(id: String, endReason: String?)
    case identityMismatch(id: String)
}
