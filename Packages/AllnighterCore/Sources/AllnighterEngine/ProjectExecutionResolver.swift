import Foundation
import AllnighterCore

/// PRJ-S06: resolves the single Project root that a mutating run must use
/// and evaluates the deterministic dirty-state mutation gate. Worker cwd,
/// proof cwd, and the attachment mirror all derive from this one root — never an
/// ad hoc `workingDir`. Read-only: it observes the root and git state, never
/// mutating either.
///
public struct ProjectExecutionResolver: Sendable {
    private let git: GitObserver

    public init(git: GitObserver = GitObserver()) {
        self.git = git
    }

    /// Resolve the execution scope, re-observing whether the root is actually
    /// present on disk (a stored `rootState` can be stale). A missing or
    /// unreadable root yields no run roots — structurally blocking mutating runs.
    public func resolve(project: Project) -> ProjectExecutionScope {
        ProjectExecutionScope(project: project, observedRootState: observeRootState(project))
    }

    /// Evaluate the mutation gate for a mutating run. Gathers observed dirty files
    /// for the Project root and delegates the decision to the pure Core evaluator.
    public func mutationGate(
        project: Project,
        likelyFilesOrAreas: [String],
        dirtyAcknowledged: Bool = false
    ) -> ProjectMutationGate {
        let rootState = observeRootState(project)
        guard rootState == .available && !project.archived else {
            return .blockedNoProjectRoot   // don't shell out to git on a missing root
        }
        let dirty = git.dirtyFiles(rootPath: project.localRootPath)
        return ProjectMutationGateEvaluator.evaluate(
            project: project,
            observedRootState: rootState,
            likelyFilesOrAreas: likelyFilesOrAreas,
            dirtyFiles: dirty,
            dirtyAcknowledged: dirtyAcknowledged
        )
    }

    /// Observe whether the Project root currently exists and is a readable
    /// directory. Observed, never inferred from the stored value.
    private func observeRootState(_ project: Project) -> RootState {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.localRootPath, isDirectory: &isDir) else {
            return .missing
        }
        guard isDir.boolValue, FileManager.default.isReadableFile(atPath: project.localRootPath) else {
            return .permissionDenied
        }
        return .available
    }
}
