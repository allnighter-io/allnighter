import Foundation

/// Typed work accepted by the resident execution authority.  This is a closed
/// union: a foreground client can request product operations, never a shell,
/// environment, executable path, or arbitrary process arguments.
public enum ResidentExecutionOperation: Codable, Equatable, Sendable {
    case teamRun(TeamRun)
    case panelStart(PanelStart)
    case panelRound(PanelRound)
    case panelDone(PanelDone)
    case sourceProbe(SourceProbe)
    case query(Query)
    case cancel(Cancel)

    public struct TeamRun: Codable, Equatable, Sendable {
        public var projectRoot: String
        public var prompt: String
        public var teamId: String?
        public var mutating: Bool

        public init(projectRoot: String, prompt: String, teamId: String? = nil, mutating: Bool) {
            self.projectRoot = projectRoot
            self.prompt = prompt
            self.teamId = teamId
            self.mutating = mutating
        }
    }

    public struct PanelStart: Codable, Equatable, Sendable {
        public var projectRoot: String
        public var targetPath: String
        public var juryId: String?

        public init(projectRoot: String, targetPath: String, juryId: String? = nil) {
            self.projectRoot = projectRoot
            self.targetPath = targetPath
            self.juryId = juryId
        }
    }

    public struct PanelRound: Codable, Equatable, Sendable {
        public var panelId: String
        public init(panelId: String) { self.panelId = panelId }
    }

    public struct PanelDone: Codable, Equatable, Sendable {
        public var panelId: String
        public init(panelId: String) { self.panelId = panelId }
    }

    public struct SourceProbe: Codable, Equatable, Sendable {
        public var sourceId: String?
        public var full: Bool
        public init(sourceId: String? = nil, full: Bool) {
            self.sourceId = sourceId
            self.full = full
        }
    }

    public struct Query: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case health
            case runStatus
            case panelStatus
        }
        public var kind: Kind
        public var canonicalId: String?
        public init(kind: Kind, canonicalId: String? = nil) {
            self.kind = kind
            self.canonicalId = canonicalId
        }
    }

    public struct Cancel: Codable, Equatable, Sendable {
        public var canonicalId: String
        public init(canonicalId: String) { self.canonicalId = canonicalId }
    }

    public enum Kind: String, Codable, Sendable {
        case teamRun, panelStart, panelRound, panelDone, sourceProbe, query, cancel
    }

    private enum CodingKeys: String, CodingKey { case type, payload }

    public var kind: Kind {
        switch self {
        case .teamRun: return .teamRun
        case .panelStart: return .panelStart
        case .panelRound: return .panelRound
        case .panelDone: return .panelDone
        case .sourceProbe: return .sourceProbe
        case .query: return .query
        case .cancel: return .cancel
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .teamRun: self = .teamRun(try container.decode(TeamRun.self, forKey: .payload))
        case .panelStart: self = .panelStart(try container.decode(PanelStart.self, forKey: .payload))
        case .panelRound: self = .panelRound(try container.decode(PanelRound.self, forKey: .payload))
        case .panelDone: self = .panelDone(try container.decode(PanelDone.self, forKey: .payload))
        case .sourceProbe: self = .sourceProbe(try container.decode(SourceProbe.self, forKey: .payload))
        case .query: self = .query(try container.decode(Query.self, forKey: .payload))
        case .cancel: self = .cancel(try container.decode(Cancel.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case let .teamRun(value): try container.encode(value, forKey: .payload)
        case let .panelStart(value): try container.encode(value, forKey: .payload)
        case let .panelRound(value): try container.encode(value, forKey: .payload)
        case let .panelDone(value): try container.encode(value, forKey: .payload)
        case let .sourceProbe(value): try container.encode(value, forKey: .payload)
        case let .query(value): try container.encode(value, forKey: .payload)
        case let .cancel(value): try container.encode(value, forKey: .payload)
        }
    }
}

/// A signed request placed into the resident coordinator's local inbox.
public struct ResidentExecutionRequest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestId: String
    public var idempotencyKey: String
    public var submittedAt: Date
    public var coordinatorId: String
    public var coordinatorNonce: String
    public var operation: ResidentExecutionOperation
    public var clientProof: ResidentClientProof

    public init(
        schemaVersion: Int = 1,
        requestId: String,
        idempotencyKey: String,
        submittedAt: Date,
        coordinatorId: String,
        coordinatorNonce: String,
        operation: ResidentExecutionOperation,
        clientProof: ResidentClientProof
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.submittedAt = submittedAt
        self.coordinatorId = coordinatorId
        self.coordinatorNonce = coordinatorNonce
        self.operation = operation
        self.clientProof = clientProof
    }
}

/// HMAC proof owned by this Allnighter installation, not by a project or vendor.
public struct ResidentClientProof: Codable, Equatable, Sendable {
    public var keyId: String
    public var signature: String

    public init(keyId: String = "resident-v1", signature: String) {
        self.keyId = keyId
        self.signature = signature
    }
}

public struct ResidentExecutionReceipt: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case accepted, rejected }

    public var schemaVersion: Int
    public var requestId: String
    public var canonicalId: String?
    public var state: State
    public var acceptedAt: Date
    public var rejection: ResidentExecutionRejection?

    public init(
        schemaVersion: Int = 1,
        requestId: String,
        canonicalId: String? = nil,
        state: State,
        acceptedAt: Date,
        rejection: ResidentExecutionRejection? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.canonicalId = canonicalId
        self.state = state
        self.acceptedAt = acceptedAt
        self.rejection = rejection
    }
}

public struct ResidentExecutionRejection: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ResidentExecutionEvent: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case queued, running, completed, failed }
    public var requestId: String
    public var sequence: Int
    public var state: State
    public var emittedAt: Date
    public var message: String?

    public init(requestId: String, sequence: Int, state: State, emittedAt: Date, message: String? = nil) {
        self.requestId = requestId
        self.sequence = sequence
        self.state = state
        self.emittedAt = emittedAt
        self.message = message
    }
}
