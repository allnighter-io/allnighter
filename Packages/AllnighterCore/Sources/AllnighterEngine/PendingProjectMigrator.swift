import Foundation
import AllnighterCore

/// PRJ-S04: backfill `projectId` onto existing Pending items. Resolution order:
/// the item's bound thread (after PRJ-S03), then its working-dir receipt via the
/// shared `ProjectBinding` rule. No reliable Project → left Unassigned (repair
/// bucket), blocked from running. Idempotent.
public struct PendingProjectMigrator {
    public struct Report: Equatable, Sendable {
        public var bound: Int = 0
        public var unassigned: Int = 0
        public var alreadyBound: Int = 0
        public var createdProjects: Int = 0
    }

    public static func migrate(
        pendingStore: PendingStore,
        threadStore: ThreadStore,
        projectStore: ProjectStore,
        git: GitObserver = GitObserver()
    ) throws -> Report {
        var report = Report()
        let before = try projectStore.activeProjects().count

        for var item in try pendingStore.loadAll() {
            if item.isProjectAssigned { report.alreadyBound += 1; continue }

            // 1. Inherit the bound thread's Project (after thread migration).
            if let threadId = item.threadId, let thread = threadStore.get(threadId), let pid = thread.projectId {
                item.projectId = pid
                try pendingStore.save(item)
                report.bound += 1
                continue
            }

            // 2. Resolve from the working-dir receipt.
            let projects = try projectStore.activeProjects()
            switch ProjectBinding.resolve(rawPath: item.localRootPathSnapshot, projects: projects, git: git) {
            case .existing(let pid):
                item.projectId = pid
                try pendingStore.save(item)
                report.bound += 1
            case .repoRoot(let path):
                let project = try projectStore.add(path: path)
                item.projectId = project.id
                try pendingStore.save(item)
                report.bound += 1
            case .unassigned:
                report.unassigned += 1   // projectId stays nil → repair bucket
            }
        }

        report.createdProjects = (try projectStore.activeProjects().count) - before
        return report
    }
}
