import Foundation

/// Shared honest-bench projector for team preflight, hello, and foreground runs.
/// Ready ≠ "binary on PATH + stale SetupStore smoke." A model is bench-ready only
/// when its driver probe says ready, the driver is not capacity-cooling, and the
/// driver is not **parked** (user ignored that CLI).
public enum BenchReadiness {
    public static let capacityLookbackSeconds: TimeInterval = 12 * 60 * 60

    /// Enabled models whose driver is probe-ready, not cooling, and not parked.
    ///
    /// OpenCode `ollama/<tag>` seats use local Ollama evidence instead of the
    /// driver-wide Zen/Go smoke. A rejected Zen probe or Go cooldown never
    /// answers for a local seat. `ollamaLocal` nil = unobserved, so those seats
    /// stay off this list (fail closed; never inferred ready).
    public static func readyModels(
        models: [Model],
        probeRecords: [ToolProbeRecord],
        coolingDriverIds: Set<String> = [],
        parkedDriverIds: Set<String> = [],
        knownDriverIds: Set<String>? = nil,
        ollamaLocal: OllamaLocalRuntimeObserver.Snapshot? = nil
    ) -> [Model] {
        let readyDrivers = TeamAssembler.readyDriverIds(from: probeRecords, excludingParked: parkedDriverIds)
        let recordsByDriver = Dictionary(uniqueKeysWithValues: probeRecords.map { ($0.driverId, $0) })
        return models.filter { m in
            guard m.enabled else { return false }
            if parkedDriverIds.contains(m.driverId) { return false }
            if let known = knownDriverIds, !known.contains(m.driverId) { return false }
            if OpenCodeLocalSeatReadiness.isLocalOpenCodeSeat(m) {
                return OpenCodeLocalSeatReadiness.isLocallyReady(
                    modelLabel: m.modelLabel,
                    binaryPath: OpenCodeLocalSeatReadiness.installedBinaryPath(
                        from: recordsByDriver[m.driverId]),
                    snapshot: ollamaLocal
                )
            }
            guard readyDrivers.contains(m.driverId) else { return false }
            return !coolingDriverIds.contains(m.driverId)
        }
    }

    /// Cooling drivers from recent failed-worker capacity observations.
    public static func coolingDriverIds(
        observations: [CapacityObservation],
        now: Date = Date()
    ) -> Set<String> {
        SourceCapacityLedger.coolingSources(observations: observations, now: now)
    }

    /// Collect capacity observations from recent runs (12h lookback), plus any
    /// older observation whose sourced cooldown is still live. Weekly/monthly
    /// vendor windows must survive the short run-origin lookback.
    public static func recentObservations(
        from runs: [TeamRun],
        now: Date = Date()
    ) -> [CapacityObservation] {
        let lookback = now.addingTimeInterval(-capacityLookbackSeconds)
        return runs.flatMap { run in
            let observations = run.failedWorkerAnswers.compactMap {
                $0.result.capacityObservation
            } + run.attempts.compactMap(\.capacityObservation)
            guard run.createdAt < lookback else { return observations }
            return observations.filter {
                SourceCapacityLedger.coolingUntil(of: $0).map { $0 > now } == true
            }
        }
    }
}
