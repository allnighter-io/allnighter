import Foundation
import AllnighterCore

/// Pure resident-tick plan for accepted runs parked on vendor capacity. It
/// mirrors `PendingWakePlanner`, but reads the unified run journal directly.
public struct VendorBackoffWakePlan: Sendable, Equatable {
    public var dueRunId: String?
    public var nextWakeAt: Date?

    public init(dueRunId: String? = nil, nextWakeAt: Date? = nil) {
        self.dueRunId = dueRunId
        self.nextWakeAt = nextWakeAt
    }
}

public enum VendorBackoffWakePlanner {
    public static func plan(runs: [TeamRun], now: Date) -> VendorBackoffWakePlan {
        let nominated = SourceCapacityLedger.oldestVendorParkRunIDs(runs: runs)
        var due: [(run: TeamRun, wakeAt: Date)] = []
        var future: [Date] = []

        for run in runs where nominated.contains(run.id) {
            guard let blocker = run.blocker, blocker.resource == .vendorBackoff else { continue }
            let baseWake = blocker.wakeAfter ?? run.attempts.last.map {
                VendorBackoffPolicy.unknownResetWakeAfter(
                    attemptNumber: $0.attemptNumber,
                    observedAt: $0.endedAt ?? $0.capacityObservation?.observedAt ?? run.createdAt
                )
            }
            guard var wakeAt = baseWake else { continue }
            if blocker.holderKind == "coordinator",
               let claimedAt = blocker.holderAcquiredAt {
                wakeAt = max(
                    wakeAt,
                    claimedAt.addingTimeInterval(VendorBackoffPolicy.wakeLeaseSeconds)
                )
            }
            if wakeAt <= now {
                due.append((run, wakeAt))
            } else {
                future.append(wakeAt)
            }
        }

        let selected = due.min {
            if $0.wakeAt != $1.wakeAt { return $0.wakeAt < $1.wakeAt }
            if $0.run.createdAt != $1.run.createdAt { return $0.run.createdAt < $1.run.createdAt }
            return $0.run.id < $1.run.id
        }
        return VendorBackoffWakePlan(
            dueRunId: selected?.run.id,
            nextWakeAt: future.min()
        )
    }
}

/// Resident in-process park reconciler. It leases one due journal, then calls
/// `RunService` directly; it never shells out to `alln run`.
public struct VendorBackoffReconciler: Sendable {
    public static let progressId = "vendorBackoff"

    public var runStore: RunStore
    public var runService: RunService
    public var coordinatorId: String
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper
    public var progress: any SchedulerProgressReporting

    public init(
        runStore: RunStore = RunStore(),
        runService: RunService,
        coordinatorId: String,
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        progress: any SchedulerProgressReporting = NoOpSchedulerProgress()
    ) {
        self.runStore = runStore
        self.runService = runService
        self.coordinatorId = coordinatorId
        self.now = now
        self.sleeper = sleeper
        self.progress = progress
    }

    /// Reconcile at most one source-scoped readiness nomination.
    @discardableResult
    public func reconcileDueOnce() async -> String? {
        let snapshot = runStore.list()
        let plan = VendorBackoffWakePlanner.plan(runs: snapshot, now: now())
        guard let runId = plan.dueRunId,
              runStore.claimVendorWake(
                runId: runId,
                coordinatorId: coordinatorId,
                now: now()
              ) != nil else { return nil }
        progress.attempting(id: Self.progressId)
        let result = await runService.resumeParkedRun(
            runId: runId,
            coordinatorId: coordinatorId
        )
        if case .failure(let error) = result,
           var failed = runStore.loadRaw(runId: runId),
           !failed.status.isTerminal {
            failed.status = .failed
            failed.phase = nil
            failed.blocker = nil
            failed.endReason = .failed
            failed.warnings.append("vendor wake escalation: \(error.code)")
            _ = try? runStore.save(failed, models: [])
        }
        progress.succeeded(id: Self.progressId)
        return runId
    }

    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            if await reconcileDueOnce() != nil { continue }
            let plan = VendorBackoffWakePlanner.plan(runs: runStore.list(), now: now())
            let target = plan.nextWakeAt ?? now().addingTimeInterval(60)
            do {
                progress.waiting(id: Self.progressId, until: target)
                try await sleeper.sleep(until: target, jitterSeconds: 0)
            } catch {
                if error is CancellationError || isCancelled() {
                    progress.stopped(id: Self.progressId)
                } else {
                    progress.failed(
                        id: Self.progressId,
                        error: "vendorBackoff sleep failed: \(error.localizedDescription)"
                    )
                }
                break
            }
        }
    }
}
