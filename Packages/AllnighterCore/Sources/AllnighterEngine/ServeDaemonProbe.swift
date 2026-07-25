import Foundation
import AllnighterCore

/// Builds read-only daemon health for `alln serve --health --json` and
/// `alln doctor --json`. Never fakes liveness: health is the durable record
/// plus a live pid check, and nothing else. Code Red deleted the request
/// transport this used to also report on, so there is no longer a second
/// readiness question to answer.
public struct ServeDaemonProbe: Sendable {
    public let store: ServeDaemonStore
    public let runsDirectory: URL
    public let processAlive: @Sendable (Int32) -> Bool
    public let currentPID: @Sendable () -> Int32
    public let activeObligationCount: @Sendable () -> Int

    public init(
        store: ServeDaemonStore = ServeDaemonStore(),
        runsDirectory: URL? = nil,
        processAlive: @escaping @Sendable (Int32) -> Bool = { RunStore.processAlive($0) },
        currentPID: @escaping @Sendable () -> Int32 = { ProcessInfo.processInfo.processIdentifier },
        activeObligationCount: (@Sendable () -> Int)? = nil
    ) {
        self.store = store
        let resolvedRunsDirectory = runsDirectory ?? AllnighterPaths.runs
        self.runsDirectory = resolvedRunsDirectory
        self.processAlive = processAlive
        self.currentPID = currentPID
        if let activeObligationCount {
            self.activeObligationCount = activeObligationCount
        } else {
            self.activeObligationCount = { @Sendable in
                Self.countActiveObligations(runsDirectory: resolvedRunsDirectory)
            }
        }
    }

    public func health(
        binaryVersion: String,
        binaryGitSha: String = AllnighterBuildInfo.gitSha,
        contractVersion: String = ContractRegistry.contractVersion
    ) -> CoordinatorHealth {
        let runsWritable = Self.directoryWritable(runsDirectory)
        let journal = CoordinatorHealth.Journal(
            incrementalDurable: runsWritable,
            orphanRecovery: runsWritable,
            runsDirWritable: runsWritable
        )
        let activeObligations = activeObligationCount()
        guard let record = store.load() else {
            return CoordinatorHealth(
                state: .foregroundOnly,
                contractVersion: contractVersion,
                binaryVersion: binaryVersion,
                binaryGitSha: binaryGitSha,
                journal: journal,
                loopback: .init(listening: false),
                activeObligationCount: activeObligations
            )
        }
        guard processAlive(record.pid) else {
            return CoordinatorHealth(
                state: .unavailable,
                daemonId: record.daemonId,
                pid: record.pid,
                startedAt: record.startedAt,
                contractVersion: record.contractVersion,
                binaryVersion: record.binaryVersion,
                binaryGitSha: record.binaryGitSha,
                journal: journal,
                loopback: .init(listening: false, host: record.loopbackHost, port: Int(record.loopbackPort)),
                activeObligationCount: activeObligations
            )
        }
        return CoordinatorHealth(
            state: .available,
            daemonId: record.daemonId,
            pid: record.pid,
            startedAt: record.startedAt,
            contractVersion: record.contractVersion,
            binaryVersion: record.binaryVersion,
            binaryGitSha: record.binaryGitSha,
            journal: journal,
            loopback: .init(listening: true, host: record.loopbackHost, port: Int(record.loopbackPort)),
            activeObligationCount: activeObligations
        )
    }

    public func doctorCoordinator() -> DoctorResult.Coordinator {
        let h = health(binaryVersion: "", binaryGitSha: AllnighterBuildInfo.gitSha, contractVersion: ContractRegistry.contractVersion)
        switch h.state {
        case .foregroundOnly:
            return .init(state: .foregroundOnly, detail: "foreground CLI only; background scheduler not running")
        case .available:
            let pid = h.pid.map { "pid \($0)" } ?? "running"
            return .init(state: .available, detail: "background scheduler running (\(pid))",
                         coordinatorId: h.daemonId, pid: h.pid, startedAt: h.startedAt)
        case .unavailable:
            return .init(state: .unavailable,
                         detail: "stale serve state; prior background scheduler is gone",
                         coordinatorId: h.daemonId, pid: h.pid, startedAt: h.startedAt)
        }
    }

    private static func directoryWritable(_ url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    private static func countActiveObligations(runsDirectory: URL) -> Int {
        // A vendor-backoff run is durable but unowned: it deliberately holds no
        // worker, write lock, or daemon process obligation. Counting it here
        // strands every new install behind a vendor's usage window.
        let activeRuns = RunStore(rootDirectory: runsDirectory).list().count {
            !$0.status.isTerminal && $0.blocker?.resource != .vendorBackoff
        }
        return activeRuns
    }
}
