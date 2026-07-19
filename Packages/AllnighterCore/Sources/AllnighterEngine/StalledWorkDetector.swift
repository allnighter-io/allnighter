import Foundation
import AllnighterCore

public struct StalledWorkThresholds: Sendable, Equatable {
    /// Default worker-chat stall window (ordinary chat / execution turns).
    public var workerChatSeconds: Int
    public var teamRunSeconds: Int
    /// Pair-programming and advisory code-review slices may run 30–60+ min without
    /// thread-turn progress signals; use this longer window for those runs.
    public var longRunningWorkerChatSeconds: Int

    public init(
        workerChatSeconds: Int = 30 * 60,
        teamRunSeconds: Int = 60 * 60,
        longRunningWorkerChatSeconds: Int = 90 * 60
    ) {
        self.workerChatSeconds = workerChatSeconds
        self.teamRunSeconds = teamRunSeconds
        self.longRunningWorkerChatSeconds = longRunningWorkerChatSeconds
    }
}

public struct StalledWorkScanInput: Sendable {
    public var threads: [WorkThread]
    public var runs: [TeamRun]
    public var pendingItems: [PendingItem]
    public var now: Date

    public init(threads: [WorkThread], runs: [TeamRun], pendingItems: [PendingItem], now: Date) {
        self.threads = threads
        self.runs = runs
        self.pendingItems = pendingItems
        self.now = now
    }
}

/// Local-truth stalled-work detector with Wake Ticket suppression (SWW-S01/S02, WTK-S04).
public enum StalledWorkDetector {
    public static func scan(
        input: StalledWorkScanInput,
        thresholds: StalledWorkThresholds = StalledWorkThresholds(),
        idFactory: @Sendable () -> String = { "stall_\(UUID().uuidString.lowercased())" }
    ) -> [StallEpisode] {
        var episodes: [StallEpisode] = []
        episodes.append(contentsOf: scanWorkerTurns(input: input, thresholds: thresholds, idFactory: idFactory))
        episodes.append(contentsOf: scanTeamRuns(input: input, thresholds: thresholds, idFactory: idFactory))
        return episodes
    }

    // MARK: - Worker chat turns

    private static func scanWorkerTurns(
        input: StalledWorkScanInput,
        thresholds: StalledWorkThresholds,
        idFactory: @Sendable () -> String
    ) -> [StallEpisode] {
        let runById = Dictionary(input.runs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [StallEpisode] = []
        for thread in input.threads {
            guard let projectId = thread.projectId else { continue }
            for turn in thread.turns where turn.kind == .workerChat {
                guard turn.status == .queued || turn.status == .running else { continue }
                if turn.requiresUserAttention { continue }
                if suppressedByWakeTicket(pending: input.pendingItems, threadId: thread.id, runId: turn.runId, now: input.now) {
                    continue
                }
                let linkedRun = turn.runId.flatMap { runById[$0] }
                if queuedTurnWaitingOnActiveRun(turn: turn, linkedRun: linkedRun) { continue }
                let thresholdSeconds = workerChatThresholdSeconds(for: turn, linkedRun: linkedRun, thresholds: thresholds)
                let lastEvent = lastObservableEvent(for: turn, thread: thread, linkedRun: linkedRun)
                let age = input.now.timeIntervalSince(lastEvent.at)
                guard age >= TimeInterval(thresholdSeconds) else { continue }
                let reason: StallReason = turn.status == .queued ? .queuedNoStart : .runningNoProgress
                out.append(makeEpisode(
                    idFactory: idFactory,
                    projectId: projectId,
                    targetKind: .workerTurn,
                    targetId: turn.id,
                    threadId: thread.id,
                    runId: turn.runId,
                    reason: reason,
                    firstDetectedAt: input.now,
                    deadlineAnchorAt: lastEvent.at,
                    thresholdSeconds: thresholdSeconds,
                    lastEvent: lastEvent
                ))
            }
        }
        return out
    }

    // MARK: - Team runs

    private static func scanTeamRuns(
        input: StalledWorkScanInput,
        thresholds: StalledWorkThresholds,
        idFactory: @Sendable () -> String
    ) -> [StallEpisode] {
        let threadById = Dictionary(input.threads.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [StallEpisode] = []
        for run in input.runs {
            let live = AsyncTeamStatusMapper.liveStatus(for: run)
            guard !live.isTerminal else { continue }
            guard live == .queued || live == .running else { continue }

            let threadId = run.threadId
            let projectId: String?
            if let threadId, let thread = threadById[threadId] {
                projectId = thread.projectId
            } else {
                projectId = nil
            }
            guard let projectId else { continue }

            if suppressedByWakeTicket(pending: input.pendingItems, threadId: threadId, runId: run.id, now: input.now) {
                continue
            }

            let lastEvent = observableEvent(for: run)
            let age = input.now.timeIntervalSince(lastEvent.at)
            guard age >= TimeInterval(thresholds.teamRunSeconds) else { continue }

            let reason: StallReason
            if live == .queued {
                reason = .queuedNoStart
            } else if live == .running {
                reason = .runningNoProgress
            } else {
                reason = .statusUnknownNoProgress
            }

            out.append(makeEpisode(
                idFactory: idFactory,
                projectId: projectId,
                targetKind: .teamRun,
                targetId: run.id,
                threadId: threadId ?? "unthreaded-\(run.id)",
                runId: run.id,
                reason: reason,
                firstDetectedAt: input.now,
                deadlineAnchorAt: lastEvent.at,
                thresholdSeconds: thresholds.teamRunSeconds,
                lastEvent: lastEvent
            ))
        }
        return out
    }

    // MARK: - Suppression (WTK-S04)

    /// Future `nextWakeAt` on a linked Pending item suppresses stall promotion.
    public static func suppressedByWakeTicket(
        pending: [PendingItem],
        threadId: String?,
        runId: String?,
        now: Date
    ) -> Bool {
        for item in pending {
            guard item.status == .pending || item.status == .running else { continue }
            let linked = (runId != nil && item.runId == runId) || (threadId != nil && item.threadId == threadId)
            guard linked else { continue }
            if let wakeAt = PendingItemDerivation.nextWakeAt(for: item), wakeAt > now {
                return true
            }
            if item.resume == nil && item.status == .pending {
                return true // idle Pending is not stalled
            }
            if let kind = item.resume?.capacityObservation?.kind {
                switch kind {
                case .authRequired, .manualRequired: return true
                default: break
                }
            }
        }
        return false
    }

    // MARK: - Refresh helpers

    public static func refreshWorkerTurn(thread: WorkThread, turnId: String) -> ThreadTurn? {
        thread.turn(id: turnId)
    }

    public static func refreshTeamRun(runStore: RunStore, runId: String) -> TeamRun? {
        runStore.load(runId: runId)
    }

    public static func isStillStalledAfterRefresh(
        thread: WorkThread?,
        turn: ThreadTurn?,
        run: TeamRun?,
        input: StalledWorkScanInput,
        thresholds: StalledWorkThresholds = StalledWorkThresholds()
    ) -> Bool {
        if let turn, let thread {
            guard turn.kind == .workerChat else { return false }
            guard turn.status == .queued || turn.status == .running else { return false }
            if turn.requiresUserAttention { return false }
            if suppressedByWakeTicket(pending: input.pendingItems, threadId: thread.id, runId: turn.runId, now: input.now) {
                return false
            }
            let linkedRun = run ?? turn.runId.flatMap { runId in input.runs.first { $0.id == runId } }
            if queuedTurnWaitingOnActiveRun(turn: turn, linkedRun: linkedRun) { return false }
            let thresholdSeconds = workerChatThresholdSeconds(for: turn, linkedRun: linkedRun, thresholds: thresholds)
            let lastEvent = lastObservableEvent(for: turn, thread: thread, linkedRun: linkedRun)
            return input.now.timeIntervalSince(lastEvent.at) >= TimeInterval(thresholdSeconds)
        }
        if let run {
            let live = AsyncTeamStatusMapper.liveStatus(for: run)
            guard !live.isTerminal else { return false }
            if suppressedByWakeTicket(pending: input.pendingItems, threadId: run.threadId, runId: run.id, now: input.now) {
                return false
            }
            let lastEvent = observableEvent(for: run)
            let threshold = TimeInterval(thresholds.teamRunSeconds)
            return input.now.timeIntervalSince(lastEvent.at) >= threshold
        }
        return false
    }

    // MARK: - Worker-turn context (WATCHDOG-S01)

    /// Pair slice envelopes, slice attempts, and advisory review prompts run longer than default chat.
    public static func isLongRunningWorkerContext(run: TeamRun) -> Bool {
        if run.id.hasPrefix("slice_") { return true }
        if run.parentRunId != nil { return true }
        if run.runLinks.contains(where: { $0.kind == .sliceOf || $0.kind == .sliceAttemptFor }) {
            return true
        }
        if run.prompt.contains("pair slice") { return true }
        if run.prompt.contains("READ-ONLY advisory") { return true }
        return false
    }

    private static func workerChatThresholdSeconds(
        for turn: ThreadTurn,
        linkedRun: TeamRun?,
        thresholds: StalledWorkThresholds
    ) -> Int {
        if let linkedRun, isLongRunningWorkerContext(run: linkedRun) {
            return thresholds.longRunningWorkerChatSeconds
        }
        return thresholds.workerChatSeconds
    }

    /// A queued turn waiting on an in-flight linked run is not stalled-by-design.
    private static func queuedTurnWaitingOnActiveRun(turn: ThreadTurn, linkedRun: TeamRun?) -> Bool {
        guard turn.status == .queued, let linkedRun else { return false }
        let live = AsyncTeamStatusMapper.liveStatus(for: linkedRun)
        return live == .queued || live == .running
    }

    /// Anchor stall age on the latest thread-turn or linked-run observable signal.
    private static func lastObservableEvent(
        for turn: ThreadTurn,
        thread: WorkThread,
        linkedRun: TeamRun?
    ) -> StallObservableEvent {
        let turnEvent = observableEvent(for: turn, thread: thread)
        guard let linkedRun else { return turnEvent }
        let runEvent = observableEvent(for: linkedRun)
        guard runEvent.at > turnEvent.at else { return turnEvent }
        return runEvent
    }

    // MARK: - Builders

    private static func observableEvent(for turn: ThreadTurn, thread: WorkThread) -> StallObservableEvent {
        let at = turn.completedAt ?? turn.createdAt
        return StallObservableEvent(
            at: at,
            kind: "turn.\(turn.status.rawValue)",
            source: "threadStore",
            summary: turn.text ?? thread.title
        )
    }

    private static func observableEvent(for run: TeamRun) -> StallObservableEvent {
        let workerTimes = run.workerAnswers.compactMap { $0.result.timing.finishedAt ?? $0.result.timing.startedAt }
        let stageTimes = run.stages.compactMap(\.finishedAt)
        let at = (workerTimes + stageTimes + [run.createdAt]).max() ?? run.createdAt
        return StallObservableEvent(
            at: at,
            kind: "teamRun.\(AsyncTeamStatusMapper.liveStatus(for: run).rawValue)",
            source: "runStore",
            summary: run.teamDisplayName ?? run.presetId ?? run.id
        )
    }

    private static func makeEpisode(
        idFactory: @Sendable () -> String,
        projectId: String,
        targetKind: StallTargetKind,
        targetId: String,
        threadId: String,
        runId: String?,
        reason: StallReason,
        firstDetectedAt: Date,
        deadlineAnchorAt: Date,
        thresholdSeconds: Int,
        lastEvent: StallObservableEvent
    ) -> StallEpisode {
        let (primary, secondary) = primaryActions(for: reason)
        return StallEpisode(
            id: idFactory(),
            projectId: projectId,
            targetKind: targetKind,
            targetId: targetId,
            threadId: threadId,
            runId: runId,
            status: .active,
            reason: reason,
            firstDetectedAt: firstDetectedAt,
            deadlineAnchorAt: deadlineAnchorAt,
            thresholdSeconds: thresholdSeconds,
            lastObservableEvent: lastEvent,
            lastRefreshAt: firstDetectedAt,
            primaryAction: primary,
            secondaryActions: secondary
        )
    }

    private static func primaryActions(for reason: StallReason) -> (String, [String]) {
        switch reason {
        case .queuedNoStart:
            return ("Cancel", ["Check status", "Open thread", "Keep waiting"])
        case .runningNoProgress:
            return ("Check status", ["Open thread", "Keep waiting", "Cancel"])
        case .statusUnknownNoProgress:
            return ("Open thread", ["Check status", "Keep waiting", "Cancel"])
        }
    }
}
