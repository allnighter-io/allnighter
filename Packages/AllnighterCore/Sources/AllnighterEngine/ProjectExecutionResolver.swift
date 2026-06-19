import Foundation
import AllnighterCore

/// PRJ-S06: resolves the single Project root that a mutating send/execute must run
/// against and evaluates the deterministic dirty-state dispatch gate. Worker cwd,
/// proof cwd, and the attachment mirror all derive from this one root — never an
/// ad hoc `workingDir`. Read-only: it observes the root and git state, never
/// mutating either.
///
/// The actual call-site rewiring (TeamRunCoordinator / WorkerRunner consuming the
/// resolved cwds) lands with dispatch (PRJ-S11), which is where the execute-lane
/// safety invariants live; this slice provides the deterministic substrate they
/// will route through.
public struct ProjectExecutionResolver: Sendable {
    private let git: GitObserver

    public init(git: GitObserver = GitObserver()) {
        self.git = git
    }

    /// Resolve the execution scope, re-observing whether the root is actually
    /// present on disk (a stored `rootState` can be stale). A missing or
    /// unreadable root yields no dispatch roots — structurally blocking mutating
    /// dispatch.
    public func resolve(project: Project) -> ProjectExecutionScope {
        ProjectExecutionScope(project: project, observedRootState: observeRootState(project))
    }

    /// Evaluate the dispatch gate for a mutating run. Gathers observed dirty files
    /// for the Project root and delegates the decision to the pure Core evaluator.
    public func dispatchGate(
        project: Project,
        likelyFilesOrAreas: [String],
        dirtyAcknowledged: Bool = false
    ) -> ProjectDispatchGate {
        let rootState = observeRootState(project)
        guard rootState == .available && !project.archived else {
            return .blockedNoProjectRoot   // don't shell out to git on a missing root
        }
        let dirty = git.dirtyFiles(rootPath: project.localRootPath)
        return ProjectDispatchGateEvaluator.evaluate(
            project: project,
            observedRootState: rootState,
            likelyFilesOrAreas: likelyFilesOrAreas,
            dirtyFiles: dirty,
            dirtyAcknowledged: dirtyAcknowledged
        )
    }

    /// PRJ-S11 substrate: revalidate mutating dispatch gates for a work order,
    /// including execution-team source coherence before worker readiness.
    public func evaluateMutatingDispatch(
        workOrder: WorkOrder,
        project: Project,
        proposal: ProjectProposal?,
        workerReadiness: [ProjectWorkerReadiness],
        readyModels: [Model],
        dirtyAcknowledged: Bool = false,
        teams: [TeamPreset] = TeamCatalog.all,
        registry: DriverRegistry? = nil
    ) -> ProjectMutatingDispatchGate {
        let rootState = observeRootState(project)
        let dirty = rootState == .available && !project.archived
            ? git.dirtyFiles(rootPath: project.localRootPath) : []
        let head = rootState == .available ? git.observe(rootPath: project.localRootPath).head : nil
        return ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: workOrder,
            project: project,
            proposal: proposal,
            observedRootState: rootState,
            dirtyFiles: dirty,
            dirtyAcknowledged: dirtyAcknowledged,
            workerReadiness: workerReadiness,
            readyModels: readyModels,
            currentGitHead: head,
            teams: teams,
            registry: registry
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
