import Foundation
import AllnighterCore

/// PRJ-S03: backfill `projectId` onto existing threads from their legacy
/// `workingDir`, using the deterministic `ProjectBinding` rule. Threads that bind
/// keep their old path as `localRootPathSnapshot` (a receipt). Threads with no
/// reliable root are left Unassigned (repair bucket) — blocked from mutating
/// dispatch until the user assigns them. One-time, idempotent (already-bound
/// threads are skipped).
public struct ThreadProjectMigrator {
    public struct Report: Equatable, Sendable {
        public var bound: Int = 0
        public var unassigned: Int = 0
        public var alreadyBound: Int = 0
        public var createdProjects: Int = 0
    }

    public static func migrate(
        threadStore: ThreadStore,
        projectStore: ProjectStore,
        git: GitObserver = GitObserver()
    ) throws -> Report {
        var report = Report()
        let before = try projectStore.activeProjects().count

        for thread in threadStore.list() {
            if thread.isProjectAssigned { report.alreadyBound += 1; continue }
            let projects = try projectStore.activeProjects()   // re-read so later threads see new roots
            switch ProjectBinding.resolve(rawPath: thread.workingDir, projects: projects, git: git) {
            case .existing(let projectId):
                _ = try threadStore.bindProject(threadId: thread.id, projectId: projectId,
                                                 localRootPathSnapshot: thread.workingDir)
                report.bound += 1
            case .repoRoot(let path):
                let project = try projectStore.add(path: path)   // dedups by normalized key
                _ = try threadStore.bindProject(threadId: thread.id, projectId: project.id,
                                                 localRootPathSnapshot: thread.workingDir)
                report.bound += 1
            case .unassigned:
                report.unassigned += 1   // projectId stays nil
            }
        }

        report.createdProjects = (try projectStore.activeProjects().count) - before
        return report
    }
}
