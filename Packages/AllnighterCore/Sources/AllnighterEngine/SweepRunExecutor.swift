import Foundation
import AllnighterCore

/// Dispatches one sweep target through the existing run owner (`RunService`).
/// Sequential: the per-root write lock still admits one mutating worker at a time.
public struct SweepRunExecutor: SweepTargetExecuting, Sendable {
    public var runService: RunService
    public var repoRoot: String
    public var projectId: String?
    public var modelId: String?

    public init(
        runService: RunService,
        repoRoot: String,
        projectId: String? = nil,
        modelId: String? = nil
    ) {
        self.runService = runService
        self.repoRoot = repoRoot
        self.projectId = projectId
        self.modelId = modelId
    }

    public func attempt(order: String, targetId: String) async throws -> SweepAttempt {
        let request = RunRequest(
            message: """
            \(order)

            Apply this order to exactly this target: \(targetId)
            """,
            repoRoot: repoRoot,
            projectId: projectId,
            pinnedModelId: modelId
        )
        let result = await runService.run(request, origin: .cli)
        switch result {
        case .success(let run):
            return SweepRunOutcome.map(run)
        case .failure(let error):
            return .failed(runId: nil, reason: error.description)
        }
    }
}
