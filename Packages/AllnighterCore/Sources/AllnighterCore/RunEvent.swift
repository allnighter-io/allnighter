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
    /// Dotted kind, e.g. `run.status_changed`, `member.status_changed`,
    /// `synthesis.completed`. Extensible (a String, not a closed enum) so new
    /// kinds never break old clients.
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
    public static let memberStatusChanged = "member.status_changed"
    public static let memberOutput = "member.output"
    public static let synthesisStarted = "synthesis.started"
    public static let synthesisCompleted = "synthesis.completed"
    public static let synthesisFailed = "synthesis.failed"
}
