import Foundation
import AllnighterCore

/// Serve-hosted periodic probe smoke so `lastProbeAt` stays honest evidence
/// without inventing timestamps on the cheap path.
///
/// Founder ruling B (2026-08-09, `docs/phases/Probe_Freshness.md` §PF-S03):
/// spending tiny vendor quota on a serve timer is approved; inventing
/// `lastProbeAt` without smoke is not.
///
/// This scheduler runs a `full: true` probe via `SourceProbeService` when probe
/// records are stale. It does NOT write `lastProbeAt` itself — `CensusIngest` /
/// the full probe path owns persistence. The cheap (`full: false`) path is
/// deliberately excluded: a non-smoke refresh would return cached records with
/// old timestamps, manufacturing evidence no probe produced.
public struct ProbeRecordRefreshScheduler: Sendable {

    public static let progressId = "probeRecordRefresh"

    /// How often to check. Matches `CapacityRefreshScheduler.tickInterval`.
    public static let tickInterval: TimeInterval = 5 * 60

    public var recordLoader: @Sendable () -> [ToolProbeRecord]
    public var parkedLoader: @Sendable () -> Set<String>
    public var smoke: @Sendable () async -> Void
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper
    public var tickJitterSeconds: TimeInterval
    public var progress: any SchedulerProgressReporting

    public init(
        recordLoader: @escaping @Sendable () -> [ToolProbeRecord] = { SetupStore().load().records },
        parkedLoader: @escaping @Sendable () -> Set<String> = { SetupStore().load().parkedSet },
        smoke: (@Sendable () async -> Void)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        tickJitterSeconds: TimeInterval = 0,
        progress: any SchedulerProgressReporting = NoOpSchedulerProgress()
    ) {
        self.recordLoader = recordLoader
        self.parkedLoader = parkedLoader
        self.smoke = smoke ?? Self.defaultSmoke()
        self.now = now
        self.sleeper = sleeper
        self.tickJitterSeconds = tickJitterSeconds
        self.progress = progress
    }

    /// True when records are empty OR any non-parked record has `lastProbeAt`
    /// age >= `ProbeFreshnessGate.gateInterval` (30m).
    public func shouldSmoke(records: [ToolProbeRecord], now: Date, parked: Set<String>) -> Bool {
        if records.isEmpty { return true }
        let nonParked = records.filter { !parked.contains($0.driverId) }
        if nonParked.isEmpty { return true }
        for record in nonParked {
            if now.timeIntervalSince(record.lastProbeAt) >= ProbeFreshnessGate.gateInterval {
                return true
            }
        }
        return false
    }

    /// Loop like `CapacityRefreshScheduler`: check → smoke if due →
    /// sleep `tickInterval` → repeat until cancelled.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            let records = recordLoader()
            let parked = parkedLoader()
            if shouldSmoke(records: records, now: now(), parked: parked) {
                progress.attempting(id: Self.progressId)
                await smoke()
                progress.succeeded(id: Self.progressId)
            }
            if isCancelled() { break }
            let sleepUntil = now().addingTimeInterval(Self.tickInterval)
            do {
                progress.waiting(id: Self.progressId, until: sleepUntil)
                try await sleeper.sleep(until: sleepUntil, jitterSeconds: tickJitterSeconds)
            } catch {
                if error is CancellationError || isCancelled() {
                    progress.stopped(id: Self.progressId)
                } else {
                    progress.failed(
                        id: Self.progressId,
                        error: "probeRecordRefresh sleep failed: \(error.localizedDescription)"
                    )
                }
                break
            }
        }
    }

    private static func defaultSmoke() -> @Sendable () async -> Void {
        {
            let registry = ModelCatalog.bundledRegistry()
            let models = ModelCatalog.resolvedModels(registry: registry)
            let service = SourceProbeService(
                models: models,
                registry: registry,
                binaryVersion: AllnighterVersionIdentity.binaryVersion,
                binaryGitSha: AllnighterBuildInfo.gitSha
            )
            _ = await service.probe(SourceProbeRequest(full: true))
        }
    }
}
