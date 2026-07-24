import Foundation
import AllnighterCore

/// Builds read-only coordinator health for `alln serve --health --json` and
/// `alln doctor --json`. Never fakes liveness.
public struct ResidentCoordinatorProbe: Sendable {
    public let store: ResidentCoordinatorStore
    public let rendezvous: ResidentExecutionRendezvous
    public let runsDirectory: URL
    public let panelsDirectory: URL
    public let processAlive: @Sendable (Int32) -> Bool
    public let currentPID: @Sendable () -> Int32
    public let activeObligationCount: @Sendable () -> Int

    public init(
        store: ResidentCoordinatorStore = ResidentCoordinatorStore(),
        rendezvous: ResidentExecutionRendezvous = ResidentExecutionRendezvous(),
        runsDirectory: URL? = nil,
        panelsDirectory: URL? = nil,
        processAlive: @escaping @Sendable (Int32) -> Bool = { RunStore.processAlive($0) },
        currentPID: @escaping @Sendable () -> Int32 = { ProcessInfo.processInfo.processIdentifier },
        activeObligationCount: (@Sendable () -> Int)? = nil
    ) {
        self.store = store
        self.rendezvous = rendezvous
        let resolvedRunsDirectory = runsDirectory ?? AllnighterPaths.runs
        let resolvedPanelsDirectory = panelsDirectory ?? AllnighterPaths.panels
        self.runsDirectory = resolvedRunsDirectory
        self.panelsDirectory = resolvedPanelsDirectory
        self.processAlive = processAlive
        self.currentPID = currentPID
        if let activeObligationCount {
            self.activeObligationCount = activeObligationCount
        } else {
            self.activeObligationCount = { @Sendable in
                Self.countActiveObligations(
                    runsDirectory: resolvedRunsDirectory,
                    panelsDirectory: resolvedPanelsDirectory
                )
            }
        }
    }

    public func health(binaryVersion: String, contractVersion: String = ContractRegistry.contractVersion) -> CoordinatorHealth {
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
                journal: journal,
                loopback: .init(listening: false),
                broker: .init(ready: false),
                activeObligationCount: activeObligations
            )
        }
        guard processAlive(record.pid) else {
            return CoordinatorHealth(
                state: .unavailable,
                coordinatorId: record.coordinatorId,
                pid: record.pid,
                startedAt: record.startedAt,
                contractVersion: record.contractVersion,
                binaryVersion: record.binaryVersion,
                journal: journal,
                loopback: .init(listening: false, host: record.loopbackHost, port: Int(record.loopbackPort)),
                broker: .init(ready: false),
                activeObligationCount: activeObligations
            )
        }
        return CoordinatorHealth(
            state: .available,
            coordinatorId: record.coordinatorId,
            pid: record.pid,
            startedAt: record.startedAt,
            contractVersion: record.contractVersion,
            binaryVersion: record.binaryVersion,
            journal: journal,
            loopback: .init(listening: true, host: record.loopbackHost, port: Int(record.loopbackPort)),
            broker: .init(ready: rendezvous.isReady(
                coordinatorId: record.coordinatorId,
                binaryVersion: record.binaryVersion,
                contractVersion: record.contractVersion
            )),
            activeObligationCount: activeObligations
        )
    }

    public func doctorCoordinator() -> DoctorResult.Coordinator {
        let h = health(binaryVersion: "", contractVersion: ContractRegistry.contractVersion)
        switch h.state {
        case .foregroundOnly:
            return .init(state: .foregroundOnly, detail: "foreground CLI only; resident coordinator not running")
        case .available:
            let pid = h.pid.map { "pid \($0)" } ?? "running"
            return .init(state: .available, detail: "resident coordinator running (\(pid))",
                         coordinatorId: h.coordinatorId, pid: h.pid, startedAt: h.startedAt)
        case .unavailable:
            return .init(state: .unavailable,
                         detail: "stale coordinator state; prior resident process is gone",
                         coordinatorId: h.coordinatorId, pid: h.pid, startedAt: h.startedAt)
        }
    }

    private static func directoryWritable(_ url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    private static func countActiveObligations(runsDirectory: URL, panelsDirectory: URL) -> Int {
        let activeRuns = RunStore(rootDirectory: runsDirectory).list().count { !$0.status.isTerminal }
        let activePanels = PanelStateStore(rootDirectory: panelsDirectory).list().count { $0.status == .running }
        return activeRuns + activePanels
    }
}
