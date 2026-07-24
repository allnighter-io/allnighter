import Foundation

/// `CoordinatorHealth` — the structured `alln serve --health --json` contract
/// (docs/phases/Mac_Standalone_App_And_Background_Coordinator.md §Serve0).
///
/// Read-only health surface for the resident coordinator. Never fakes liveness:
/// `foregroundOnly` when no resident process is running, `available` only when a
/// live pid is observed, `unavailable` when durable state names a dead process.
public struct CoordinatorHealth: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var state: State
    public var coordinatorId: String?
    public var pid: Int32?
    public var startedAt: Date?
    public var contractVersion: String
    public var binaryVersion: String
    /// Exact source-build identity of the resident process.
    public var binaryGitSha: String
    public var journal: Journal
    public var loopback: Loopback
    /// File-rendezvous execution endpoint, distinct from loopback health.
    public var broker: Broker
    public var activeObligationCount: Int
    /// Explicit recovery, when the client can observe a broker identity but
    /// cannot prove a live resident process from its private coordinator state.
    public var recoveryAction: String?

    public init(
        schemaVersion: Int = 1,
        state: State,
        coordinatorId: String? = nil,
        pid: Int32? = nil,
        startedAt: Date? = nil,
        contractVersion: String,
        binaryVersion: String,
        binaryGitSha: String = AllnighterBuildInfo.gitSha,
        journal: Journal,
        loopback: Loopback,
        broker: Broker = .init(ready: false),
        activeObligationCount: Int = 0,
        recoveryAction: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.coordinatorId = coordinatorId
        self.pid = pid
        self.startedAt = startedAt
        self.contractVersion = contractVersion
        self.binaryVersion = binaryVersion
        self.binaryGitSha = binaryGitSha
        self.journal = journal
        self.loopback = loopback
        self.broker = broker
        self.activeObligationCount = activeObligationCount
        self.recoveryAction = recoveryAction
    }

    public enum State: String, Codable, Sendable {
        /// No resident coordinator; foreground CLI is the only surface.
        case foregroundOnly
        /// Resident coordinator is running and its pid is live.
        case available
        /// Durable coordinator state exists but the owning process is gone.
        case unavailable
    }

    public struct Journal: Codable, Equatable, Sendable {
        public var incrementalDurable: Bool
        public var orphanRecovery: Bool
        public var runsDirWritable: Bool

        public init(incrementalDurable: Bool, orphanRecovery: Bool, runsDirWritable: Bool) {
            self.incrementalDurable = incrementalDurable
            self.orphanRecovery = orphanRecovery
            self.runsDirWritable = runsDirWritable
        }
    }

    public struct Loopback: Codable, Equatable, Sendable {
        public var listening: Bool
        public var host: String
        public var port: Int?

        public init(listening: Bool, host: String = "127.0.0.1", port: Int? = nil) {
            self.listening = listening
            self.host = host
            self.port = port
        }
    }

    public struct Broker: Codable, Equatable, Sendable {
        public var ready: Bool
        public var transport: String

        public init(ready: Bool, transport: String = "file-rendezvous") {
            self.ready = ready
            self.transport = transport
        }
    }
}
