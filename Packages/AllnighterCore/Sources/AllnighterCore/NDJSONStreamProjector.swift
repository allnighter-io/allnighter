import Foundation

/// Projects a settled `TeamRun` into the public NDJSON event sequence for
/// `alln team --stream` (docs/phases/CLI_Implementation_Contract.md §NDJSON
/// Stream). Events are ordered by `seq`, carry the run's real timestamps, and the
/// final event is always a terminal one (`teamRunCompleted`/`teamRunFailed`).
///
/// This is a faithful event log derived from the persisted run (the internal
/// `RunEvent` stream + the post-fan-out plan stage are not exposed live by
/// `TeamService` today). Live incremental streaming is a later enhancement; the
/// emitted shape, ordering, and content are the contract here.
public enum NDJSONStreamProjector {
    public struct Event: Encodable, Sendable {
        public let schemaVersion: Int
        public let seq: Int
        public let ts: String
        public let event: String
        public let teamRunId: String
        public let data: EventData
        init(seq: Int, ts: String, event: String, teamRunId: String, data: EventData) {
            self.schemaVersion = 1; self.seq = seq; self.ts = ts
            self.event = event; self.teamRunId = teamRunId; self.data = data
        }
    }

    /// Flexible per-event data. Nil fields are omitted on encode, so each event
    /// carries only its contract-required keys.
    public struct EventData: Encodable, Sendable {
        public var status: String?
        public var origin: String?
        public var teamPresetId: String?
        public var workerId: String?
        public var modelId: String?
        public var skillId: String?
        public var durationMs: Int?
        public var stageId: String?
        public var planStageId: String?
        public var error: ErrorEnvelope?
    }

    public static func events(for run: TeamRun) -> [Event] {
        var out: [Event] = []
        var seq = 0
        func add(_ event: String, _ ts: Date, _ data: EventData) {
            seq += 1
            out.append(Event(seq: seq, ts: iso(ts), event: event, teamRunId: run.id, data: data))
        }

        let created = run.createdAt
        let lastFinish = run.workerAnswers.compactMap(\.finishedAt).max() ?? created

        add("teamRunStarted", created, EventData(
            status: TeamRunJSON.Status.running.rawValue,
            origin: TeamRunJSONMapper.mapOrigin(run.origin).rawValue,
            teamPresetId: run.presetId
        ))

        for worker in run.workers {
            let answer = run.workerAnswer(workerId: worker.id)
            let startedAt = answer?.startedAt ?? created
            add("workerStarted", startedAt, EventData(workerId: worker.id, modelId: worker.modelId, skillId: worker.skillId))
            guard let answer else { continue }
            let endAt = answer.finishedAt ?? startedAt
            switch answer.status {
            case .done:
                add("workerAnswered", endAt, EventData(workerId: worker.id, durationMs: answer.durationMs))
            case .failed, .timedOut:
                add("workerFailed", endAt, EventData(workerId: worker.id, error: workerError(answer, runId: run.id)))
            default:
                break   // queued/running/skipped/cancelled: no terminal worker event
            }
        }

        if let plan = run.latestStage(.plan) {
            add("planStarted", lastFinish, EventData(workerId: plan.producedByWorkerId, stageId: plan.id))
            if plan.status == .done {
                add("planWritten", lastFinish, EventData(workerId: plan.producedByWorkerId, stageId: plan.id))
            }
        }

        switch TeamRunJSONMapper.mapRun(run.status) {
        case .done:
            add("teamRunCompleted", lastFinish, EventData(
                status: TeamRunJSON.Status.done.rawValue,
                planStageId: run.latestStage(.plan).flatMap { $0.status == .done ? $0.id : nil }
            ))
        default:
            add("teamRunFailed", lastFinish, EventData(
                status: TeamRunJSONMapper.mapRun(run.status).rawValue,
                error: ErrorEnvelope(code: "TEAM_RUN_FAILED", message: "team run \(run.status.rawValue)", requiresManual: false, retryable: true, runId: run.id)
            ))
        }
        return out
    }

    /// One compact (single-line, sorted-key) JSON object per event — NDJSON.
    public static func lines(for run: TeamRun) -> [String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]   // compact: no .prettyPrinted
        return events(for: run).map { event in
            String(decoding: (try? encoder.encode(event)) ?? Data("{}".utf8), as: UTF8.self)
        }
    }

    private static func workerError(_ a: WorkerAnswer, runId: String) -> ErrorEnvelope {
        ErrorEnvelope(
            code: a.status == .timedOut ? "TEAM_RUN_TIMEOUT" : "WORKER_FAILED",
            message: a.errorReason ?? "worker did not produce an answer",
            requiresManual: false, retryable: true, runId: runId, workerId: a.workerId
        )
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
