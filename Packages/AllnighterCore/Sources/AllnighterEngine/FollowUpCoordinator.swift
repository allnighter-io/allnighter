import Foundation
import AllnighterCore

/// Runs the Try Fix chain (Try_Fix_Auto_Implement): a Bug Hunt answer run, then — if it
/// returns an actionable FixPacket and the gate allows — ONE child execution run that tries
/// the top hypothesis. One round of the elimination loop. Owns no git and no second
/// permission layer: it orders RunService, which takes the repo write lock for the child.
public struct FollowUpCoordinator: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var parentRun: TeamRun
        public var packet: FixPacket?
        public var gate: TryFixGate.Decision
        /// The child fix-attempt run, when the gate allowed one and it started.
        public var childRun: TeamRun?
    }

    private let runService: RunService
    public init(runService: RunService) { self.runService = runService }

    public static let defaultExecutorTeamId = "build_slice"

    public func runTryFix(
        _ request: RunRequest, origin: RunOrigin, runId: String? = nil
    ) async -> Result<Outcome, RunServiceError> {
        // 1. Parent: the read-only Bug Hunt answer run.
        var parent: TeamRun
        switch await runService.run(request, origin: origin, runId: runId) {
        case .failure(let error): return .failure(error)
        case .success(let run): parent = run
        }

        // 2. Lift the typed FixPacket from the writer's output (the synthesis / plan).
        let packet = FixPacketParser.parse(fromWriterOutput: parent.plan)

        // 3. Gate the chain — danger blocks, doubt does not.
        let executorId = request.executorTeamId ?? Self.defaultExecutorTeamId
        let executorFacts = await runService.tryFixExecutorFacts(teamId: executorId)
        let decision = TryFixGate.evaluate(packet: packet, executor: executorFacts)

        guard case .allowed(let topId) = decision,
              let packet,
              let hypothesis = packet.hypotheses.first(where: { $0.id == topId }) else {
            return .success(Outcome(parentRun: parent, packet: packet, gate: decision, childRun: nil))
        }

        // 4. Assemble the one-round fix-attempt order and run the child execution.
        let prompt = FixAttemptPrompt.assemble(
            originalReport: request.message, packet: packet, hypothesis: hypothesis)
        let childRequest = RunRequest(
            message: prompt, repoRoot: request.repoRoot, projectId: request.projectId,
            presetId: executorId, effort: request.effort)
        var child: TeamRun
        switch await runService.run(childRequest, origin: origin) {
        // e.g. the repo write lock is busy — surface it; the diagnosis already ran.
        case .failure(let error): return .failure(error)
        case .success(let run): child = run
        }

        // 5. Link diagnosis <-> fix attempt durably, and persist both.
        child.parentRunId = parent.id
        child.links = (child.runLinks + [RunLink(kind: .diagnosisOf, runId: parent.id)])
        parent.links = (parent.runLinks + [RunLink(kind: .fixAttemptFor, runId: child.id)])
        await runService.save(parent)
        await runService.save(child)

        return .success(Outcome(parentRun: parent, packet: packet, gate: decision, childRun: child))
    }
}
