import Foundation

/// Live mutating-run git vs tracker split (founder 2026-08-20).
///
/// Git landing is supplementary and unattributed: it never flips status,
/// observation, or the write lock, and it never skips a queued waiter.
/// When HEAD moved in the stuck job's window **and** that job looks silent,
/// `alln show` names one recovery: stop that job so the line can move.
public enum StuckRunDisclosure {
    public static let attributionNotProven = "notProven"

    public struct Result: Equatable, Sendable {
        public var repoActivity: TeamRunJSON.RepoActivity
        /// Set only when the stuck job is silent **and** files landed. Nil means
        /// tell the git fact without recommending stop.
        public var stopRunId: String?
        public var warning: String?

        public init(
            repoActivity: TeamRunJSON.RepoActivity,
            stopRunId: String? = nil,
            warning: String? = nil
        ) {
            self.repoActivity = repoActivity
            self.stopRunId = stopRunId
            self.warning = warning
        }
    }

    public struct Facts: Equatable, Sendable {
        public var subjectId: String
        public var subjectIsTerminal: Bool
        public var subjectMutating: Bool
        public var subjectLastActivityAt: Date?
        public var subjectBaselineHead: String?
        public var waitingOnWriteLock: Bool
        public var holderId: String?
        public var holderIsTerminal: Bool
        public var holderLastActivityAt: Date?
        public var holderBaselineHead: String?
        public var currentHead: String?
        public var commits: [RepoDelta.CommitInfo]
        public var now: Date

        public init(
            subjectId: String,
            subjectIsTerminal: Bool,
            subjectMutating: Bool,
            subjectLastActivityAt: Date? = nil,
            subjectBaselineHead: String? = nil,
            waitingOnWriteLock: Bool = false,
            holderId: String? = nil,
            holderIsTerminal: Bool = false,
            holderLastActivityAt: Date? = nil,
            holderBaselineHead: String? = nil,
            currentHead: String? = nil,
            commits: [RepoDelta.CommitInfo] = [],
            now: Date
        ) {
            self.subjectId = subjectId
            self.subjectIsTerminal = subjectIsTerminal
            self.subjectMutating = subjectMutating
            self.subjectLastActivityAt = subjectLastActivityAt
            self.subjectBaselineHead = subjectBaselineHead
            self.waitingOnWriteLock = waitingOnWriteLock
            self.holderId = holderId
            self.holderIsTerminal = holderIsTerminal
            self.holderLastActivityAt = holderLastActivityAt
            self.holderBaselineHead = holderBaselineHead
            self.currentHead = currentHead
            self.commits = commits
            self.now = now
        }
    }

    /// Pure. Fail closed when the run window cannot be proven (missing baseline
    /// or HEAD). Never infers "the waiter already did this work."
    public static func evaluate(_ facts: Facts) -> Result? {
        guard !facts.subjectIsTerminal, facts.subjectMutating else { return nil }

        let waiter = facts.waitingOnWriteLock
            && !(facts.holderId ?? "").isEmpty
            && !facts.holderIsTerminal
        let stuckId = waiter ? facts.holderId : facts.subjectId
        let baseline = waiter ? facts.holderBaselineHead : facts.subjectBaselineHead
        let lastActivity = waiter ? facts.holderLastActivityAt : facts.subjectLastActivityAt
        guard let stuckId, let baseline, let head = facts.currentHead,
              !baseline.isEmpty, !head.isEmpty, baseline != head else {
            return nil
        }

        let activity = TeamRunJSON.RepoActivity(
            changedDuringRunWindow: true,
            attribution: attributionNotProven,
            baseline: baseline,
            head: head,
            commits: Array(facts.commits.prefix(5))
        )
        let silent = StreamLiveness.streamSilenceWarning(
            lastActivityAt: lastActivity, now: facts.now)
        guard silent else {
            return Result(repoActivity: activity)
        }

        let warning: String
        if waiter {
            warning = "You're waiting on job \(stuckId). That job still shows running, but files already landed. Stop that job so this one can start."
        } else {
            warning = "Files already landed in git, but this job still shows running. That does not mean the job is done. Stop it so the next job can start."
        }
        return Result(repoActivity: activity, stopRunId: stuckId, warning: warning)
    }

    public static func facts(
        for run: TeamRun,
        holder: TeamRun?,
        currentHead: String?,
        commits: [RepoDelta.CommitInfo],
        now: Date
    ) -> Facts {
        let waiting = !run.status.isTerminal
            && run.blocker?.resource == .repoWriteLock
            && run.phase == .waitingForWriteLock
        return Facts(
            subjectId: run.id,
            subjectIsTerminal: run.status.isTerminal,
            subjectMutating: run.mutating,
            subjectLastActivityAt: run.lastActivityAt,
            subjectBaselineHead: run.baselineHead,
            waitingOnWriteLock: waiting,
            holderId: run.blocker?.holderId,
            holderIsTerminal: holder?.status.isTerminal ?? false,
            holderLastActivityAt: holder?.lastActivityAt,
            holderBaselineHead: holder?.baselineHead,
            currentHead: currentHead,
            commits: commits,
            now: now
        )
    }

    public static func stopAction(runId: String) -> TeamRunJSON.NextAction {
        TeamRunJSON.NextAction(
            kind: .stopStuckRun,
            command: "alln kill \(runId) --json",
            label: "Stop the stuck job so the line can move"
        )
    }
}
