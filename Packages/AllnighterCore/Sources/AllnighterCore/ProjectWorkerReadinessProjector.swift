import Foundation

/// Projects per-Project worker readiness for `project models` / `project
/// recheck-models`. Pilot and Loop gate on **global** seat readiness (the
/// same `ToolProbeRecord` cache the run path uses), not on project-level probes —
/// `unsafeToProbe` is honest about that distinction.
public enum ProjectWorkerReadinessProjector {
    /// One driver row in `ProjectWorkersJSON` — the canonical readiness facts plus
    /// `pilotReady` derived from global seat readiness only.
    public struct Row: Codable, Sendable, Equatable {
        public var projectId: ProjectID
        public var sourceId: String
        public var workerId: String?
        public var status: WorkerReadinessStatus
        public var checkedAt: Date
        public var probeKind: ProbeKind
        public var probeCommandLabel: String?
        public var lastError: String?
        public var setupHint: String?
        /// True when this driver's global smoke probe is `ready` — the signal
        /// `RunService.sourceReadyModelIds()` uses for dispatch.
        public var pilotReady: Bool

        public init(
            projectId: ProjectID,
            sourceId: String,
            workerId: String? = nil,
            status: WorkerReadinessStatus,
            checkedAt: Date,
            probeKind: ProbeKind,
            probeCommandLabel: String? = nil,
            lastError: String? = nil,
            setupHint: String? = nil,
            pilotReady: Bool
        ) {
            self.projectId = projectId
            self.sourceId = sourceId
            self.workerId = workerId
            self.status = status
            self.checkedAt = checkedAt
            self.probeKind = probeKind
            self.probeCommandLabel = probeCommandLabel
            self.lastError = lastError
            self.setupHint = setupHint
            self.pilotReady = pilotReady
        }

        public init(_ readiness: ProjectWorkerReadiness, pilotReady: Bool, detail: String?) {
            self.projectId = readiness.projectId
            self.sourceId = readiness.sourceId
            self.workerId = readiness.workerId
            self.status = readiness.status
            self.checkedAt = readiness.checkedAt
            self.probeKind = readiness.probeKind
            self.probeCommandLabel = readiness.probeCommandLabel
            self.pilotReady = pilotReady
            if readiness.status == .unsafeToProbe, let detail {
                self.lastError = detail
                self.setupHint = detail
            } else {
                self.lastError = readiness.lastError
                self.setupHint = readiness.setupHint
            }
        }
    }

    /// Exact `unsafeToProbe` detail/hint copy (Pilot_DX.md §DX3).
    public static func unsafeToProbeDetail(globalSeatReady: Bool) -> String {
        let global = globalSeatReady ? "global seat ready" : "global seat not ready"
        return "\(global); project-level trust unprobed (driver declares no safe probe); pilot/relay may start — this is not a blocker."
    }

    public static func build(
        workers: [ProjectWorkerReadiness],
        probeRecords: [ToolProbeRecord]
    ) -> [Row] {
        let recordsByDriver = Dictionary(uniqueKeysWithValues: probeRecords.map { ($0.driverId, $0) })
        return workers.map { worker in
            let globalReady = recordsByDriver[worker.sourceId]?.status.isSmokeReady ?? false
            let detail = worker.status == .unsafeToProbe
                ? unsafeToProbeDetail(globalSeatReady: globalReady)
                : nil
            return Row(worker, pilotReady: globalReady, detail: detail)
        }
    }
}
