import Foundation

/// Maps journal `TeamRun` truth to live async polling vocabulary. Never invents
/// progress percentages — only observed worker/stage state.
public enum AsyncTeamStatusMapper {
    public static let defaultAcceptedPollMs = 2_500
    public static let defaultRunningPollMs = 5_000
    public static let defaultSynthesizingPollMs = 3_000

    /// Journal `RunStatus` → frozen public `RunLifecycle` (RLR-L3). Mostly the
    /// bare `RunStatus.lifecycle` projection, with two run-aware refinements the
    /// bare projection deliberately omits: a no-plan `partial` reads as `failed`,
    /// and a `fanning_out` run with no active worker yet reads as `queued`.
    public static func liveStatus(for run: TeamRun) -> RunLifecycle {
        switch run.status {
        case .partial:
            return run.plan != nil ? .done : .failed
        case .fanningOut:
            let active = run.workerAnswers.contains { $0.result.status == .running || $0.result.status == .done || $0.result.status == .failed }
            return active ? .running : .queued
        default:
            return run.status.lifecycle
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
        liveStatus(for: run).isTerminal
    }

    public static func nextPollAfterMs(for status: RunLifecycle) -> Int {
        switch status {
        case .queued: return defaultAcceptedPollMs
        case .running: return defaultRunningPollMs
        case .done, .failed, .timedOut, .cancelled: return 0
        }
    }

    /// Seconds the agent/harness should sleep before re-checking (PO-F3).
    /// Derived from `nextPollAfterMs` so external poll loops and in-process
    /// `--wait-for` share one cadence.
    public static func waitHintSeconds(for status: RunLifecycle) -> Double {
        Double(nextPollAfterMs(for: status)) / 1_000.0
    }

    /// Next action after a status snapshot or wait (PO-F3).
    public static func nextAction(for status: RunLifecycle, runId: String) -> AsyncTeamNextAction {
        if status.isTerminal {
            return AsyncTeamNextAction(kind: "fetchResult", tool: "team_result", runId: runId)
        }
        return AsyncTeamNextAction(kind: "waitForStatus", tool: "team_status", runId: runId)
    }

    /// Attach wait guidance fields without inventing new status truth.
    public static func withWaitGuidance(_ response: TeamStatusResponse) -> TeamStatusResponse {
        var copy = response
        copy.nextAction = nextAction(for: response.status, runId: response.runId)
        copy.waitHintSeconds = waitHintSeconds(for: response.status)
        return copy
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
        // Never infer endReason — only what the actor stamped.
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
            traceId: "trace_\(run.id)",
            endReason: run.endReason?.rawValue
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
