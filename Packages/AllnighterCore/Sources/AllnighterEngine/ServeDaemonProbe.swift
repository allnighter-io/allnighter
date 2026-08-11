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
    /// Observed resident LaunchAgent (SC-S00). Live by default; tests inject
    /// fixture-backed `ServeLaunchAgentStatus` — never launchctl in unit tests.
    public let launchAgent: ServeLaunchAgentStatus

    public init(
        store: ServeDaemonStore = ServeDaemonStore(),
        runsDirectory: URL? = nil,
        processAlive: @escaping @Sendable (Int32) -> Bool = { RunStore.processAlive($0) },
        currentPID: @escaping @Sendable () -> Int32 = { ProcessInfo.processInfo.processIdentifier },
        activeObligationCount: (@Sendable () -> Int)? = nil,
        launchAgent: ServeLaunchAgentStatus = ServeLaunchAgentStatus()
    ) {
        self.store = store
        let resolvedRunsDirectory = runsDirectory ?? AllnighterPaths.runs
        self.runsDirectory = resolvedRunsDirectory
        self.processAlive = processAlive
        self.currentPID = currentPID
        self.launchAgent = launchAgent
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
        contractVersion: String = ContractRegistry.contractVersion,
        healthClient: ServeHealthClient? = nil
    ) -> CoordinatorHealth {
        let runsWritable = Self.directoryWritable(runsDirectory)
        let journal = CoordinatorHealth.Journal(
            incrementalDurable: runsWritable,
            orphanRecovery: runsWritable,
            runsDirWritable: runsWritable
        )
        let activeObligations = activeObligationCount()
        let launchAgentHealth = Self.launchAgentHealth(launchAgent.observe())
        guard let record = store.load() else {
            return CoordinatorHealth(
                state: .foregroundOnly,
                contractVersion: contractVersion,
                binaryVersion: binaryVersion,
                binaryGitSha: binaryGitSha,
                journal: journal,
                loopback: .init(listening: false),
                activeObligationCount: activeObligations,
                launchAgent: launchAgentHealth
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
                activeObligationCount: activeObligations,
                launchAgent: launchAgentHealth
            )
        }

        let loopback: CoordinatorHealth.Loopback
        if let client = healthClient {
            switch client.probe(host: record.loopbackHost, port: record.loopbackPort) {
            case .success(let response):
                if response.daemonId == record.daemonId && response.pid == record.pid {
                    loopback = .init(listening: true, host: record.loopbackHost, port: Int(record.loopbackPort))
                } else {
                    let mismatch: String
                    if response.daemonId != record.daemonId && response.pid != record.pid {
                        mismatch = "daemonId mismatch (\(response.daemonId) != \(record.daemonId)) and pid mismatch (\(response.pid) != \(record.pid))"
                    } else if response.daemonId != record.daemonId {
                        mismatch = "daemonId mismatch (\(response.daemonId) != \(record.daemonId))"
                    } else {
                        mismatch = "pid mismatch (\(response.pid) != \(record.pid)) — recycled pid"
                    }
                    loopback = .init(listening: false, host: record.loopbackHost, port: Int(record.loopbackPort), detail: mismatch)
                }
            case .failure(let failure):
                let reason: String
                switch failure {
                case .nonLoopbackHost(let addr):
                    reason = "non-loopback host: \(addr)"
                case .connectionRefused(let addr):
                    reason = "connection refused at \(addr)"
                case .timeout(let addr):
                    reason = "timeout at \(addr)"
                case .non200Status(let code, let addr):
                    reason = "HTTP \(code) at \(addr)"
                case .unparseableBody(let detail):
                    reason = "unparseable body: \(detail)"
                }
                loopback = .init(listening: false, host: record.loopbackHost, port: Int(record.loopbackPort), detail: reason)
            }
        } else {
            loopback = .init(listening: true, host: record.loopbackHost, port: Int(record.loopbackPort))
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
            loopback: loopback,
            activeObligationCount: activeObligations,
            launchAgent: launchAgentHealth
        )
    }

    /// Maps the LaunchAgent observation onto the health contract; an absent
    /// plist omits the field (foreground-only stays OK).
    private static func launchAgentHealth(_ observation: ServeLaunchAgentStatus.Observation) -> CoordinatorHealth.LaunchAgent? {
        switch observation.state {
        case .absent:
            return nil
        case .running:
            return .init(state: .running, pid: observation.pid, lastExitCode: observation.lastExitCode, detail: observation.detail)
        case .wedged:
            return .init(state: .wedged, pid: observation.pid, lastExitCode: observation.lastExitCode, detail: observation.detail)
        case .unknown:
            return .init(state: .unknown, pid: observation.pid, lastExitCode: observation.lastExitCode, detail: observation.detail)
        }
    }

    public func doctorCoordinator() -> DoctorResult.Coordinator {
        let h = health(binaryVersion: "", binaryGitSha: AllnighterBuildInfo.gitSha, contractVersion: ContractRegistry.contractVersion)
        switch h.state {
        case .foregroundOnly:
            return .init(state: .foregroundOnly, detail: "foreground CLI only; background scheduler not running",
                         launchAgent: h.launchAgent)
        case .available:
            let pid = h.pid.map { "pid \($0)" } ?? "running"
            return .init(state: .available, detail: "background scheduler running (\(pid))",
                         coordinatorId: h.daemonId, pid: h.pid, startedAt: h.startedAt,
                         launchAgent: h.launchAgent)
        case .unavailable:
            return .init(state: .unavailable,
                         detail: "stale serve state; prior background scheduler is gone",
                         coordinatorId: h.daemonId, pid: h.pid, startedAt: h.startedAt,
                         launchAgent: h.launchAgent)
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
