import Foundation
import AllnighterCore

/// SWW-S04: makes a stall episode's recovery actions EXECUTABLE. The detector emits
/// action labels (Check status / Keep waiting / Dismiss); this service runs them and
/// persists the result. Pure store mutations + a re-check via the detector — no run
/// invocation here (cancelling a live run is a separate, gated slice).
public struct StallRecoveryService: Sendable {
    public var threadStore: ThreadStore
    public var runStore: RunStore
    public var pendingStore: PendingStore
    public var episodeStore: StallEpisodeStore
    public var now: @Sendable () -> Date

    public init(
        threadStore: ThreadStore = ThreadStore(),
        runStore: RunStore = RunStore(),
        pendingStore: PendingStore = PendingStore(),
        episodeStore: StallEpisodeStore = StallEpisodeStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.threadStore = threadStore
        self.runStore = runStore
        self.pendingStore = pendingStore
        self.episodeStore = episodeStore
        self.now = now
    }

    public enum RecoveryError: Error, Equatable {
        case episodeNotFound(String)
        case invalidMinutes
    }

    private func load(_ id: String) throws -> StallEpisode {
        guard let e = episodeStore.loadAll().first(where: { $0.id == id }) else {
            throw RecoveryError.episodeNotFound(id)
        }
        return e
    }

    /// Keep waiting: snooze attention until now + `minutes`. The episode is still a real
    /// stall — just quiet — so periodic scans / notifications suppress it until then.
    public func keepWaiting(episodeId: String, minutes: Int) throws -> StallEpisode {
        guard minutes > 0 else { throw RecoveryError.invalidMinutes }
        var e = try load(episodeId)
        e.snoozedUntil = now().addingTimeInterval(TimeInterval(minutes * 60))
        e.status = .snoozed
        try episodeStore.save(e)
        return e
    }

    /// Dismiss: the user accepts the stall and stops being nudged. Kept as a cleared
    /// record (history), not deleted.
    public func dismiss(episodeId: String) throws -> StallEpisode {
        var e = try load(episodeId)
        e.status = .cleared
        e.clearedBy = .userDismiss
        e.clearedAt = now()
        try episodeStore.save(e)
        return e
    }

    /// Check status: re-observe the target right now. If it has progressed or
    /// terminated, clear the episode (refreshedOut). Otherwise stamp the refresh time
    /// and keep it active so the agent/user knows it's genuinely still stuck.
    public func checkStatus(episodeId: String, thresholds: StalledWorkThresholds = StalledWorkThresholds()) throws -> StallEpisode {
        var e = try load(episodeId)
        let input = StalledWorkScanInput(
            threads: threadStore.list(), runs: runStore.list(),
            pendingItems: (try? pendingStore.loadOrdered().items) ?? [], now: now())
        let thread = input.threads.first { $0.id == e.threadId }
        let turn = e.targetKind == .workerTurn
            ? thread.flatMap { StalledWorkDetector.refreshWorkerTurn(thread: $0, turnId: e.targetId) }
            : nil
        let run = e.targetKind == .teamRun
            ? StalledWorkDetector.refreshTeamRun(runStore: runStore, runId: e.targetId)
            : nil
        let stillStalled = StalledWorkDetector.isStillStalledAfterRefresh(
            thread: thread, turn: turn, run: run, input: input, thresholds: thresholds)
        e.lastRefreshAt = now()
        if !stillStalled {
            e.status = .cleared
            e.clearedBy = .refreshedOut
            e.clearedAt = now()
        }
        try episodeStore.save(e)
        return e
    }
}
