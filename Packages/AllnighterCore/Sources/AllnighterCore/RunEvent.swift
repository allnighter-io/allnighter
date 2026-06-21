import Foundation

/// Append-only event describing one state change in a run. The UI updates from
/// these events, never by mutating truth directly. The envelope matches the
/// constitution (`ON HOLD/00` §5/§6) so the same events can later be served over
/// WebSocket to iOS — clients dedupe by `id` and apply idempotently.
public struct RunEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Monotonic per-Mac sequence number; clients persist the last `seq` seen.
    public var seq: Int64
    public var ts: Date
    /// Dotted kind, e.g. `run.status_changed`, `worker.status_changed`,
    /// `stage.completed`. Extensible (a String, not a closed enum) so new kinds
    /// never break old clients.
    public var kind: String
    public var payload: [String: JSONValue]

    public init(
        id: String,
        seq: Int64,
        ts: Date,
        kind: String,
        payload: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.seq = seq
        self.ts = ts
        self.kind = kind
        self.payload = payload
    }
}

/// Well-known event kinds. Stored as strings so the set is open for growth.
public enum RunEventKind {
    public static let runStatusChanged = "run.status_changed"
    public static let workerStatusChanged = "worker.status_changed"
    public static let workerOutput = "worker.output"
    /// Live streaming partial: the FULL accumulated visible answer text so far for a
    /// worker (03_Mac_Streaming). Payload: `runId`, `workerId`, `text`, `truncated`.
    public static let workerAnswerDelta = "worker.answer_delta"
    /// Live streaming REASONING: the FULL accumulated thinking text so far for a
    /// worker, shown in a separate surface. Payload: `runId`, `workerId`, `text`.
    public static let workerReasoningDelta = "worker.reasoning_delta"
    // Generic stage events (RB1+) — one family for analysis/plan/review/final/
    // Stage payload carries `stageId` + `purpose`. No per-kind families.
    public static let stageStarted = "stage.started"
    public static let stageOutput = "stage.output"
    public static let stageCompleted = "stage.completed"
    public static let stageFailed = "stage.failed"
    public static let stageReused = "stage.reused"
}
