import Foundation

/// Durable delivery record for one run or relay PM boundary.
///
/// `PMTurnStore` owns persistence. This value is intentionally independent of
/// execution state so every delivery surface can project the same wire shape.
public struct PMTurnJSON: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case run
        case relay
    }

    public var schemaVersion: Int
    public var kind: Kind
    public var subjectId: String
    /// Monotonic per `(kind, subjectId)` for delivery deduplication.
    public var sequence: Int
    /// Present only for relay turns.
    public var round: Int?
    public var createdAt: Date
    public var reason: String
    public var lifecycleStatus: String
    /// The untruncated primary worker or team report, when one is available.
    public var report: String?
    public var workerRunId: String?
    /// WRC-S00's future nested recovery envelope. `nil` never delays delivery.
    public var workRecovery: JSONValue?
    public var nextCommands: [String]
    public var notes: [String]
    /// Present only for relay turns.
    public var pmMode: String?

    public init(
        schemaVersion: Int = 1,
        kind: Kind,
        subjectId: String,
        sequence: Int,
        round: Int? = nil,
        createdAt: Date,
        reason: String,
        lifecycleStatus: String,
        report: String? = nil,
        workerRunId: String? = nil,
        workRecovery: JSONValue? = nil,
        nextCommands: [String],
        notes: [String] = [],
        pmMode: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.subjectId = subjectId
        self.sequence = sequence
        self.round = round
        self.createdAt = createdAt
        self.reason = reason
        self.lifecycleStatus = lifecycleStatus
        self.report = report
        self.workerRunId = workerRunId
        self.workRecovery = workRecovery
        self.nextCommands = nextCommands
        self.notes = notes
        self.pmMode = pmMode
    }
}
