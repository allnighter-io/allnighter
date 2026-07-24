import Foundation

/// `CoordinatorHealth` — the structured `alln serve --health --json` contract
/// (docs/phases/Mac_Standalone_App_And_Background_Coordinator.md §Serve0).
///
/// Read-only health surface for the `alln serve` background daemon. Never fakes
/// liveness: `foregroundOnly` when no daemon process is running, `available`
/// only when a live pid is observed, `unavailable` when durable state names a
/// dead process.
///
/// Code Red deleted the resident execution transport, so this no longer reports
/// a broker endpoint or a transport-specific recovery action: the daemon runs
/// background schedulers and answers health, and owns no run semantics.
public struct CoordinatorHealth: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var state: State
    public var daemonId: String?
    public var pid: Int32?
    public var startedAt: Date?
    public var contractVersion: String
    public var binaryVersion: String
    /// Exact source-build identity of the daemon process.
    public var binaryGitSha: String
    public var journal: Journal
    public var loopback: Loopback
    public var activeObligationCount: Int

    public init(
        schemaVersion: Int = 1,
        state: State,
        daemonId: String? = nil,
        pid: Int32? = nil,
        startedAt: Date? = nil,
        contractVersion: String,
        binaryVersion: String,
        binaryGitSha: String = AllnighterBuildInfo.gitSha,
        journal: Journal,
        loopback: Loopback,
        activeObligationCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.daemonId = daemonId
        self.pid = pid
        self.startedAt = startedAt
        self.contractVersion = contractVersion
        self.binaryVersion = binaryVersion
        self.binaryGitSha = binaryGitSha
        self.journal = journal
        self.loopback = loopback
        self.activeObligationCount = activeObligationCount
    }

    public enum State: String, Codable, Sendable {
        /// No background daemon; foreground CLI is the only surface.
        case foregroundOnly
        /// The daemon is running and its pid is live.
        case available
        /// Durable daemon state exists but the owning process is gone.
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
}
