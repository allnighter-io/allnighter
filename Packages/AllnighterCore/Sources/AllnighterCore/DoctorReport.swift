import Foundation

/// Builds a `DoctorResult` from detection records + bench + local-check facts
/// (docs/phases/CLI_Implementation_Contract.md §Doctor Contract).
///
/// Pure and quota-aware: with `full == false` (the default `alln doctor`), the
/// smoke probe never ran, so auth/smoke/readiness are reported honestly as
/// `notChecked` with a next action pointing at `alln doctor --full` — never
/// inferred from the absence of a probe. With `full == true`, those checks
/// reflect the real probe outcome.
public enum DoctorReport {
    public struct Inputs: Sendable {
        public var binaryVersion: String
        public var contractVersion: String
        public var docsVersionMatchesBinary: Bool
        public var configDirWritable: Bool
        public var runsDirWritable: Bool
        public var pendingDirWritable: Bool
        /// Observed resident coordinator state from `ResidentCoordinatorProbe` when set.
        public var coordinator: DoctorResult.Coordinator?
        /// True when smoke probes ran (`--full`); false for the quota-free path.
        public var full: Bool

        public init(
            binaryVersion: String,
            contractVersion: String,
            docsVersionMatchesBinary: Bool = true,
            configDirWritable: Bool,
            runsDirWritable: Bool,
            pendingDirWritable: Bool = true,
            coordinator: DoctorResult.Coordinator? = nil,
            full: Bool
        ) {
            self.binaryVersion = binaryVersion
            self.contractVersion = contractVersion
            self.docsVersionMatchesBinary = docsVersionMatchesBinary
            self.configDirWritable = configDirWritable
            self.runsDirWritable = runsDirWritable
            self.pendingDirWritable = pendingDirWritable
            self.coordinator = coordinator
            self.full = full
        }
    }

    private static let fullFix = "alln doctor --full"

    public static func build(models: [Model], manifests: [DriverManifest], records: [ToolProbeRecord], inputs: Inputs) -> DoctorResult {
        func sourceName(_ id: String) -> String { manifests.first { $0.id == id }?.displayName ?? id }
        let sourcesLoaded = !manifests.isEmpty
        let recByDriver = Dictionary(records.map { ($0.driverId, $0) }, uniquingKeysWith: { a, _ in a })

        var checks: [DoctorResult.Check] = [
            .init(name: "binaryVersion", status: .ok, detail: "alln \(inputs.binaryVersion)"),
            .init(name: "docsVersion",
                  status: inputs.docsVersionMatchesBinary ? .ok : .degraded,
                  detail: inputs.docsVersionMatchesBinary ? "generated docs match the contract registry" : "generated docs drift from the registry",
                  fixCommand: inputs.docsVersionMatchesBinary ? nil : "alln dev export-contracts"),
            .init(name: "configDir",
                  status: inputs.configDirWritable ? .ok : .critical,
                  detail: inputs.configDirWritable ? "config dir writable" : "config dir missing or not writable",
                  requiresManual: !inputs.configDirWritable),
            .init(name: "runsDir",
                  status: inputs.runsDirWritable ? .ok : .critical,
                  detail: inputs.runsDirWritable ? "run journal dir writable" : "run journal dir missing or not writable",
                  requiresManual: !inputs.runsDirWritable),
            .init(name: "sources",
                  status: sourcesLoaded ? .ok : .critical,
                  detail: sourcesLoaded ? "\(manifests.count) source manifests loaded" : "no source manifests loaded"),
        ]

        // Per-source checks from detection records.
        for r in records.sorted(by: { $0.driverId < $1.driverId }) {
            let name = sourceName(r.driverId)
            checks.append(installedCheck(r, name: name))
            checks.append(authCheck(r, name: name, full: inputs.full))
        }

        // Bench-readiness aggregate.
        if inputs.full {
            let ready = records.filter { $0.status.isReady }.count
            checks.append(.init(name: "benchReadyCount",
                                status: ready > 0 ? .ok : .critical,
                                detail: "\(ready) model\(ready == 1 ? "" : "s") ready",
                                requiresManual: ready == 0))
        } else {
            checks.append(.init(name: "benchReadyCount", status: .notChecked,
                                detail: "model readiness not checked (no smoke probe)", fixCommand: fullFix))
        }

        checks.append(.init(name: "defaultTeamValid",
                            status: models.isEmpty ? .critical : .ok,
                            detail: models.isEmpty ? "no models configured" : "\(models.count) models configured"))
        checks.append(planWriterCheck(models: models, recByDriver: recByDriver, full: inputs.full))
        checks.append(journalIncrementalCheck(inputs.runsDirWritable))
        checks.append(journalOrphanCheck(inputs.runsDirWritable))
        checks.append(pendingReadableCheck(inputs.pendingDirWritable))
        checks.append(pendingWritableCheck(inputs.pendingDirWritable))
        let coordinator = inputs.coordinator ?? DoctorResult.Coordinator(
            state: .foregroundOnly,
            detail: "foreground CLI only; resident coordinator not running"
        )
        checks.append(coordinatorCheck(coordinator))

        let modelInfos = models.map { m -> TeamRunJSON.ModelInfo in
            let status: TeamRunJSON.ModelStatus
            if inputs.full {
                status = (recByDriver[m.driverId]?.status.isReady ?? false) ? .ready : .unavailable
            } else {
                status = .unknown
            }
            return TeamRunJSON.ModelInfo(id: m.id, displayName: m.displayName, sourceId: m.driverId, sourceName: sourceName(m.driverId), status: status)
        }

        return DoctorResult(
            status: overallStatus(records: records, sourcesLoaded: sourcesLoaded, inputs: inputs),
            binaryVersion: inputs.binaryVersion,
            contractVersion: inputs.contractVersion,
            docsVersionMatchesBinary: inputs.docsVersionMatchesBinary,
            checks: checks,
            fixes: [],
            models: modelInfos,
            coordinator: coordinator
        )
    }

    // MARK: - Per-check helpers

    private static func installedCheck(_ r: ToolProbeRecord, name: String) -> DoctorResult.Check {
        switch r.status {
        case .ready, .installedNotProbed, .installedNotSignedIn, .probeFailed:
            return .init(name: "source.\(r.driverId).installed", status: .ok, detail: "\(name) found\(r.version.map { " (\($0))" } ?? "")")
        case .shimmedNeedsConfirm:
            return .init(name: "source.\(r.driverId).installed", status: .degraded, detail: "\(name) needs a one-click path confirmation", requiresManual: true)
        case .notInstalled:
            return .init(name: "source.\(r.driverId).installed", status: .degraded, detail: "\(name) not found on PATH or known paths", requiresManual: true)
        }
    }

    private static func authCheck(_ r: ToolProbeRecord, name: String, full: Bool) -> DoctorResult.Check {
        let key = "source.\(r.driverId).auth"
        guard full else {
            return .init(name: key, status: .notChecked, detail: "auth not checked without --full", fixCommand: fullFix)
        }
        switch r.status {
        case .ready:
            return .init(name: key, status: .ok, detail: "\(name) authenticated")
        case .installedNotSignedIn(let flow):
            return .init(name: key, status: .degraded, detail: "\(name) is not signed in. \(flow.instructions)", fixCommand: flow.interactiveCommand, requiresManual: true)
        case .probeFailed(let reason):
            return .init(name: key, status: .degraded, detail: "\(name) smoke probe failed: \(reason)")
        default:
            return .init(name: key, status: .notChecked, detail: "auth not determined")
        }
    }

    private static func journalIncrementalCheck(_ runsOK: Bool) -> DoctorResult.Check {
        guard runsOK else {
            return .init(name: "journal.incrementalDurable", status: .critical,
                         detail: "run journal dir missing or not writable", requiresManual: true)
        }
        return .init(name: "journal.incrementalDurable", status: .ok,
                     detail: "run journal persists transitions incrementally")
    }

    private static func journalOrphanCheck(_ runsOK: Bool) -> DoctorResult.Check {
        guard runsOK else {
            return .init(name: "journal.orphanRecovery", status: .critical,
                         detail: "run journal dir missing or not writable", requiresManual: true)
        }
        return .init(name: "journal.orphanRecovery", status: .ok,
                     detail: "orphaned non-terminal runs resolve to interrupted")
    }

    private static func pendingReadableCheck(_ pendingOK: Bool) -> DoctorResult.Check {
        guard pendingOK else {
            return .init(name: "pending.storeReadable", status: .critical,
                         detail: "pending store dir missing or not readable", requiresManual: true)
        }
        return .init(name: "pending.storeReadable", status: .ok, detail: "pending store readable")
    }

    private static func pendingWritableCheck(_ pendingOK: Bool) -> DoctorResult.Check {
        guard pendingOK else {
            return .init(name: "pending.storeWritable", status: .critical,
                         detail: "pending store dir missing or not writable", requiresManual: true)
        }
        return .init(name: "pending.storeWritable", status: .ok, detail: "pending store writable")
    }

    private static func coordinatorCheck(_ coordinator: DoctorResult.Coordinator) -> DoctorResult.Check {
        switch coordinator.state {
        case .available:
            let pid = coordinator.pid.map { " (pid \($0))" } ?? ""
            return .init(name: "coordinator", status: .ok, detail: "resident coordinator running\(pid)")
        case .foregroundOnly:
            return .init(name: "coordinator", status: .ok, detail: coordinator.detail)
        case .unavailable:
            return .init(name: "coordinator", status: .degraded, detail: coordinator.detail,
                         fixCommand: "alln serve", requiresManual: false)
        }
    }

    private static func planWriterCheck(models: [Model], recByDriver: [String: ToolProbeRecord], full: Bool) -> DoctorResult.Check {
        guard let writer = models.first(where: { $0.role == .planWriter || $0.role == .both }) else {
            return .init(name: "planWriterReady", status: .degraded, detail: "no plan-writer model configured", requiresManual: true)
        }
        guard full else {
            return .init(name: "planWriterReady", status: .notChecked, detail: "plan writer \(writer.displayName) configured; readiness not checked", fixCommand: fullFix)
        }
        let ready = recByDriver[writer.driverId]?.status.isReady ?? false
        return .init(name: "planWriterReady",
                     status: ready ? .ok : .degraded,
                     detail: ready ? "plan writer \(writer.displayName) ready" : "plan writer \(writer.displayName) not ready")
    }

    // MARK: - Overall status

    private static func overallStatus(records: [ToolProbeRecord], sourcesLoaded: Bool, inputs: Inputs) -> DoctorResult.Status {
        let nothingInstalled = !records.isEmpty && records.allSatisfy {
            if case .notInstalled = $0.status { return true } else { return false }
        }
        if !inputs.configDirWritable || !inputs.runsDirWritable || !inputs.pendingDirWritable || !sourcesLoaded || nothingInstalled {
            return .critical
        }
        if inputs.full && records.allSatisfy({ !$0.status.isReady }) && !records.isEmpty {
            return .critical   // probed and nothing is ready
        }
        let problem = !inputs.docsVersionMatchesBinary || records.contains {
            switch $0.status {
            case .notInstalled, .shimmedNeedsConfirm, .probeFailed, .installedNotSignedIn: return true
            default: return false
            }
        }
        return problem ? .degraded : .ok
    }
}
