import Foundation

/// Maps journal `TeamRun` truth to live async polling vocabulary. Never invents
/// progress percentages — only observed worker/stage state.
public enum AsyncTeamStatusMapper {
    public static let defaultAcceptedPollMs = 2_500
    public static let defaultRunningPollMs = 5_000
    public static let defaultSynthesizingPollMs = 3_000

    public static func liveStatus(for run: TeamRun) -> AsyncTeamLiveStatus {
        switch run.status {
        case .interrupted: return .interrupted
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .complete: return .completed
        case .partial:
            return run.plan != nil ? .completed : .failed
        case .planning: return .synthesizing
        case .fanningOut:
            let active = run.workerAnswers.contains { $0.result.status == .running || $0.result.status == .done || $0.result.status == .failed }
            return active ? .running : .accepted
        case .answersIn, .reviewing, .finalizing: return .running
        case .draft: return .accepted
        }
    }

    public static func currentStage(for run: TeamRun) -> String? {
        switch run.status {
        case .planning: return "plan"
        case .reviewing: return "review"
        case .fanningOut, .answersIn:
            let reviewIds = Set(run.workers.filter { $0.purpose == .review }.map(\.id))
            if !reviewIds.isEmpty,
               run.workerAnswers.contains(where: { reviewIds.contains($0.memberId) && $0.result.status != .queued }) {
                return "review"
            }
            return "answer"
        default: return nil
        }
    }

    public static func resultAvailable(for run: TeamRun) -> Bool {
        let status = liveStatus(for: run)
        guard status.isTerminal else { return false }
        switch status {
        case .completed: return true
        case .failed, .timedOut, .cancelled, .interrupted: return true
        default: return false
        }
    }

    public static func nextPollAfterMs(for status: AsyncTeamLiveStatus) -> Int {
        switch status {
        case .accepted: return defaultAcceptedPollMs
        case .running: return defaultRunningPollMs
        case .synthesizing: return defaultSynthesizingPollMs
        case .completed, .failed, .timedOut, .cancelled, .interrupted: return 0
        }
    }

    public static func workers(for run: TeamRun) -> [TeamStatusWorker] {
        let nameById = Dictionary(run.workers.map { ($0.id, $0.skillName ?? $0.label ?? $0.skillId ?? $0.id) },
                                  uniquingKeysWith: { a, _ in a })
        return run.workerAnswers.map { answer in
            TeamStatusWorker(
                workerId: answer.memberId,
                displayName: nameById[answer.memberId] ?? answer.memberId,
                status: mapWorkerLive(answer.result.status),
                startedAt: answer.result.timing.startedAt,
                finishedAt: answer.result.timing.finishedAt
            )
        }
    }

    public static func statusResponse(for run: TeamRun) -> TeamStatusResponse {
        let live = liveStatus(for: run)
        let workerRows = workers(for: run)
        let terminal: Set<String> = ["completed", "failed", "timedOut", "cancelled"]
        let done = workerRows.filter { terminal.contains($0.status) }.count
        return TeamStatusResponse(
            runId: run.id,
            status: live,
            lane: run.lane?.rawValue,
            teamPresetId: run.presetId,
            effort: run.effort?.rawValue,
            currentStage: currentStage(for: run),
            workers: workerRows,
            workersDone: done,
            workersTotal: workerRows.count,
            warnings: run.warnings,
            resultAvailable: resultAvailable(for: run),
            nextPollAfterMs: nextPollAfterMs(for: live),
            traceId: "trace_\(run.id)"
        )
    }

    private static func mapWorkerLive(_ status: WorkerAnswerStatus) -> String {
        switch status {
        case .queued: return "waiting"
        case .running: return "running"
        case .done: return "completed"
        case .failed: return "failed"
        case .timedOut: return "timedOut"
        case .cancelled: return "cancelled"
        case .skipped: return "waiting"
        }
    }
}
