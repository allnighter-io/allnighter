import Foundation

/// An append-only record of one sequential worker attempt within a unified run.
/// Selection and substitution policy are intentionally opaque strings until RLC-S04
/// freezes their precedence; S01 only preserves the observed provenance.
public struct RunAttempt: Codable, Sendable, Equatable {
    public var attemptNumber: Int
    public var requestedSourceId: String?
    public var requestedModelId: String?
    public var resolvedSourceId: String?
    public var resolvedModelId: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var capacityObservation: CapacityObservation?
    public var vendorSessionId: String?
    public var selectionOrigin: String?
    public var substitutionOfAttempt: Int?
    public var terminalStatus: WorkerAnswerStatus?
    public var reason: String?
    /// Bounded and redacted at construction and decode; raw worker output is never durable here.
    public private(set) var diagnosticSnippet: String?

    public init(
        attemptNumber: Int,
        requestedSourceId: String? = nil,
        requestedModelId: String? = nil,
        resolvedSourceId: String? = nil,
        resolvedModelId: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        capacityObservation: CapacityObservation? = nil,
        vendorSessionId: String? = nil,
        selectionOrigin: String? = nil,
        substitutionOfAttempt: Int? = nil,
        terminalStatus: WorkerAnswerStatus? = nil,
        reason: String? = nil,
        diagnosticSnippet: String? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.requestedSourceId = requestedSourceId
        self.requestedModelId = requestedModelId
        self.resolvedSourceId = resolvedSourceId
        self.resolvedModelId = resolvedModelId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.capacityObservation = capacityObservation
        self.vendorSessionId = vendorSessionId
        self.selectionOrigin = selectionOrigin
        self.substitutionOfAttempt = substitutionOfAttempt
        self.terminalStatus = terminalStatus
        self.reason = reason
        self.diagnosticSnippet = Self.sanitize(diagnosticSnippet)
    }

    private enum CodingKeys: String, CodingKey {
        case attemptNumber, requestedSourceId, requestedModelId
        case resolvedSourceId, resolvedModelId, startedAt, endedAt
        case capacityObservation, vendorSessionId, selectionOrigin
        case substitutionOfAttempt, terminalStatus, reason, diagnosticSnippet
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attemptNumber = try c.decode(Int.self, forKey: .attemptNumber)
        requestedSourceId = try c.decodeIfPresent(String.self, forKey: .requestedSourceId)
        requestedModelId = try c.decodeIfPresent(String.self, forKey: .requestedModelId)
        resolvedSourceId = try c.decodeIfPresent(String.self, forKey: .resolvedSourceId)
        resolvedModelId = try c.decodeIfPresent(String.self, forKey: .resolvedModelId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        capacityObservation = try c.decodeIfPresent(CapacityObservation.self, forKey: .capacityObservation)
        vendorSessionId = try c.decodeIfPresent(String.self, forKey: .vendorSessionId)
        selectionOrigin = try c.decodeIfPresent(String.self, forKey: .selectionOrigin)
        substitutionOfAttempt = try c.decodeIfPresent(Int.self, forKey: .substitutionOfAttempt)
        terminalStatus = try c.decodeIfPresent(WorkerAnswerStatus.self, forKey: .terminalStatus)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        diagnosticSnippet = Self.sanitize(
            try c.decodeIfPresent(String.self, forKey: .diagnosticSnippet)
        )
    }

    private static func sanitize(_ text: String?) -> String? {
        guard var text else { return nil }
        let patterns = [
            #"(?i)bearer\s+[a-z0-9\-_\.]+"#,
            #"(?i)api[_-]?key[=:\s]+[a-z0-9\-_]+"#,
            #"(?i)sk-[a-z0-9]{8,}"#,
            #"(?i)token[=:\s]+[a-z0-9\-_\.]{8,}"#,
            #"(?i)cookie[=:\s]+[^;\s]+"#,
            #"(?i)authorization:\s*[^\s]+"#,
        ]
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "[redacted]"
            )
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        if text.count > 200 {
            text = String(text.prefix(199)) + "…"
        }
        return text
    }
}

/// Makes newly-added public arrays decode as empty when older JSON omitted the key.
@propertyWrapper
public struct LegacySafeArray<Element>: Codable, Sendable, Equatable
where Element: Codable & Sendable & Equatable {
    public var wrappedValue: [Element]

    public init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode([Element].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

public extension KeyedDecodingContainer {
    func decode<Element>(
        _ type: LegacySafeArray<Element>.Type,
        forKey key: Key
    ) throws -> LegacySafeArray<Element>
    where Element: Codable & Sendable & Equatable {
        try decodeIfPresent(type, forKey: key) ?? LegacySafeArray(wrappedValue: [])
    }
}
