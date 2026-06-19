import Foundation
import AllnighterCore

/// PRJ-S11b: dispatch an approved work order to one worker, under the inviolable
/// execution lane. The flow is: re-validate the full mutating gate
/// (`ProjectMutatingDispatchEvaluator`), acquire the one-Running-per-lane gate
/// (keyed on the normalized working directory), invoke the worker via the SAME
/// `WorkerRunner` as every other run, release the lane, and capture a `WorkReturn`.
///
/// A return is NOT proof — S12 verification decides "done". This service mutates a
/// real repo through the worker's CLI, so the gate + lane are load-bearing: never
/// weaken them. Injecting the `CommandRunner` + `ExecutionLaneRegistry` keeps it
/// unit-testable without spawning real CLIs.
public struct ProjectDispatchService: Sendable {
    private let runner: CommandRunner
    private let registry: DriverRegistry
    private let invocations: [String: ToolInvocation]
    private let dispatchTimeout: Duration
    private let now: @Sendable () -> Date

    public init(
        runner: CommandRunner,
        registry: DriverRegistry,
        invocations: [String: ToolInvocation] = [:],
        dispatchTimeout: Duration = .seconds(600),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runner = runner
        self.registry = registry
        self.invocations = invocations
        self.dispatchTimeout = dispatchTimeout
        self.now = now
    }

    public enum Outcome: Sendable, Equatable {
        /// The worker ran (under the lane); the captured return carries the result —
        /// status `.returned` on success, `.failed`/`.interrupted` otherwise.
        case dispatched(WorkReturn)
        /// A mutating gate refused dispatch before any worker started.
        case blocked(code: String, message: String)
        /// Another Execute order holds this lane; dispatch was refused (never run two).
        case laneBusy(laneKey: String)
    }

    /// `order` must already be in `.dispatch` mode with its `targetSourceId` set to
    /// `targetModel`'s source (the caller resolves the single execution source).
    public func dispatch(
        order: WorkOrder,
        project: Project,
        proposal: ProjectProposal?,
        targetModel: Model,
        workerReadiness: [ProjectWorkerReadiness],
        readyModels: [Model],
        currentGitHead: String?,
        dirtyFiles: [String],
        observedRootState: RootState,
        dirtyAcknowledged: Bool,
        teams: [TeamPreset] = TeamCatalog.all,
        lane: ExecutionLaneRegistry = .shared
    ) async -> Outcome {
        let gate = ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: order, project: project, proposal: proposal,
            observedRootState: observedRootState, dirtyFiles: dirtyFiles,
            dirtyAcknowledged: dirtyAcknowledged, workerReadiness: workerReadiness,
            readyModels: readyModels, currentGitHead: currentGitHead, teams: teams, registry: registry)
        guard case .allowed(let scope, _) = gate else {
            return .blocked(code: gate.primaryErrorCode, message: gate.message)
        }
        guard let manifest = registry.manifest(for: targetModel) else {
            return .blocked(code: "WORKER_NOT_READY_IN_PROJECT", message: "no driver manifest for \(targetModel.id)")
        }

        // Execution lane: at most one Execute order per working directory. INVIOLABLE.
        let laneKey = ExecutionLane.key(workingDirectory: scope.workerCwd)
        guard await lane.acquire(laneKey) else {
            return .laneBusy(laneKey: laneKey)
        }
        let startedAt = now()
        let runOutcome = await WorkerRunner(commandRunner: runner, invocations: invocations, now: now)
            .invoke(worker: targetModel, manifest: manifest, prompt: order.promptBody,
                    workingDirectoryOverride: scope.workerCwd, timeoutOverride: dispatchTimeout)
        await lane.release(laneKey)

        let status: WorkReturnStatus
        switch runOutcome.status {
        case .done: status = .returned
        case .timedOut: status = .interrupted
        default: status = .failed
        }
        let ret = WorkReturn(
            id: "ret_" + UUID().uuidString.prefix(8).lowercased(),
            projectId: project.id, workOrderId: order.id,
            runId: nil, targetWorkerId: targetModel.id, transcriptRef: nil,
            summary: runOutcome.output ?? runOutcome.errorReason,
            reportedFiles: [], reportedProof: [],
            status: status, createdAt: startedAt)
        return .dispatched(ret)
    }
}
