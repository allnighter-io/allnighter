import Foundation
import AllnighterCore

/// Read-path git observation for `StuckRunDisclosure`. Never mutates the tree,
/// never flips journal status, never skips a waiter.
public enum StuckRunDisclosureLive {
    public static func evaluate(
        run: TeamRun,
        store: RunStore,
        git: GitObserver = GitObserver(),
        now: Date = Date()
    ) -> StuckRunDisclosure.Result? {
        guard !run.status.isTerminal, run.mutating else { return nil }
        let holder: TeamRun? = {
            guard run.blocker?.resource == .repoWriteLock,
                  let holderId = run.blocker?.holderId, !holderId.isEmpty else {
                return nil
            }
            return store.loadRaw(runId: holderId)
        }()
        let root = run.repoRoot
            ?? holder?.repoRoot
            ?? run.blocker?.scopeRoot
        guard let root else { return nil }
        let currentHead = git.observe(rootPath: root).head
        let baseline = (run.blocker?.resource == .repoWriteLock)
            ? holder?.baselineHead
            : run.baselineHead
        let commits: [RepoDelta.CommitInfo] = {
            guard let baseline, let currentHead, baseline != currentHead else { return [] }
            return git.commitsInRange(rootPath: root, baseline: baseline, head: currentHead)
        }()
        return StuckRunDisclosure.evaluate(
            StuckRunDisclosure.facts(
                for: run,
                holder: holder,
                currentHead: currentHead,
                commits: commits,
                now: now
            )
        )
    }

    public static func attach(
        to context: inout TeamRunJSONMapper.Context,
        run: TeamRun,
        store: RunStore,
        git: GitObserver = GitObserver(),
        now: Date = Date()
    ) {
        context.stuckDisclosure = evaluate(run: run, store: store, git: git, now: now)
    }
}
