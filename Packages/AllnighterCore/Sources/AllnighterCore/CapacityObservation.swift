import Foundation

/// Sourced capacity/cooldown fact from a worker attempt (docs/phases/Stalled_Work_Watchdog.md).
public enum CapacityObservationKind: String, Codable, Sendable, CaseIterable {
    case accountRateLimit
    case providerBusy
    case cooldown
    case authRequired
    case manualRequired
    case unknownCapacity
}

/// How the observation was derived — not provider quota truth.
public enum CapacitySourceConfidence: String, Codable, Sendable, CaseIterable {
    case structured
    case messageFallback
    case localPolicy
    case unknown
}

public struct CapacityObservation: Codable, Sendable, Equatable {
    public var kind: CapacityObservationKind
    /// Worker or driver source id (e.g. `claude_code`, `codex`, `agy`).
    public var source: String
    public var sourceConfidence: CapacitySourceConfidence
    public var rawSnippet: String
    public var observedAt: Date
    /// Present only when the CLI/API provided a reset time or duration.
    public var observedResetAt: Date?
    public var retryAfterSeconds: Int?
    /// Conservative local retry boundary; may equal `observedResetAt` when sourced.
    public var wakeAfter: Date?

    public init(
        kind: CapacityObservationKind,
        source: String,
        sourceConfidence: CapacitySourceConfidence,
        rawSnippet: String,
        observedAt: Date,
        observedResetAt: Date? = nil,
        retryAfterSeconds: Int? = nil,
        wakeAfter: Date? = nil
    ) {
        self.kind = kind
        self.source = source
        self.sourceConfidence = sourceConfidence
        self.rawSnippet = rawSnippet
        self.observedAt = observedAt
        self.observedResetAt = observedResetAt
        self.retryAfterSeconds = retryAfterSeconds
        self.wakeAfter = wakeAfter
    }
}

/// Public JSON projection for Pending CLI/MCP surfaces.
public struct CapacityObservationJSON: Codable, Equatable, Sendable {
    public var kind: String
    public var source: String
    public var sourceConfidence: String
    public var rawSnippet: String
    public var observedAt: String
    public var observedResetAt: String?
    public var retryAfterSeconds: Int?
    public var wakeAfter: String?

    public init(
        kind: String,
        source: String,
        sourceConfidence: String,
        rawSnippet: String,
        observedAt: String,
        observedResetAt: String? = nil,
        retryAfterSeconds: Int? = nil,
        wakeAfter: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.sourceConfidence = sourceConfidence
        self.rawSnippet = rawSnippet
        self.observedAt = observedAt
        self.observedResetAt = observedResetAt
        self.retryAfterSeconds = retryAfterSeconds
        self.wakeAfter = wakeAfter
    }
}

public enum CapacityObservationJSONMapper {
    public static func map(_ observation: CapacityObservation, iso: ISO8601DateFormatter) -> CapacityObservationJSON {
        CapacityObservationJSON(
            kind: observation.kind.rawValue,
            source: observation.source,
            sourceConfidence: observation.sourceConfidence.rawValue,
            rawSnippet: observation.rawSnippet,
            observedAt: iso.string(from: observation.observedAt),
            observedResetAt: observation.observedResetAt.map { iso.string(from: $0) },
            retryAfterSeconds: observation.retryAfterSeconds,
            wakeAfter: observation.wakeAfter.map { iso.string(from: $0) }
        )
    }
}
