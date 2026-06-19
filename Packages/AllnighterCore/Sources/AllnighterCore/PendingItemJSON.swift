import Foundation

/// `PendingItemJSON` — public machine contract for Pending items
/// (docs/phases/CLI_Implementation_Contract.md §Pending CLI Contract).
public struct PendingItemJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var pendingItem: ItemInfo
    public var target: TargetInfo
    public var policy: PolicyInfo
    public var execution: ExecutionInfo
    public var safety: SafetyInfo
    public var admission: AdmissionInfo?
    public var capacityObservation: CapacityObservationJSON?
    public var attempts: [AttemptInfo]
    public var nextActions: [NextAction]
    public var audit: AuditInfo

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        pendingItem: ItemInfo,
        target: TargetInfo,
        policy: PolicyInfo,
        execution: ExecutionInfo,
        safety: SafetyInfo,
        admission: AdmissionInfo? = nil,
        capacityObservation: CapacityObservationJSON? = nil,
        attempts: [AttemptInfo] = [],
        nextActions: [NextAction] = [],
        audit: AuditInfo
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.pendingItem = pendingItem
        self.target = target
        self.policy = policy
        self.execution = execution
        self.safety = safety
        self.admission = admission
        self.capacityObservation = capacityObservation
        self.attempts = attempts
        self.nextActions = nextActions
        self.audit = audit
    }

    public struct ItemInfo: Codable, Equatable, Sendable {
        public var id: String
        public var status: Status
        public var title: String
        public var kind: Kind
        public var origin: Origin
        public var threadId: String?
        public var promptExcerpt: String
        public var createdAt: String
        public var updatedAt: String
        public var nextWakeAt: String?
        public var blockedReason: String?
        public var needsAttention: Bool

        public enum Status: String, Codable, Sendable, CaseIterable {
            case draft, pending, running, done, failed, cancelled
        }

        public enum Kind: String, Codable, Sendable, CaseIterable {
            case workerChat, teamRun, workOrder, dispatch, returnReview, followUp
        }

        public enum Origin: String, Codable, Sendable, CaseIterable {
            case cli, gui, mcp, ios, localApi, system, preset
        }
    }

    public struct TargetInfo: Codable, Equatable, Sendable {
        public var workerIds: [String]
        public var teamPresetId: String?
        public var preferredWorkerIds: [String]
        public var fallbackWorkerIds: [String]
        public var requiredWorkerIds: [String]
        public var minWorkers: Int?
    }

    public struct PolicyInfo: Codable, Equatable, Sendable {
        public var selection: String
        public var attentionMode: String
        public var drainMode: String
        public var maxAttempts: Int?
        public var retryFloorSeconds: Int?
        public var allowDegraded: Bool
        public var requireKnownAvailable: Bool
        public var createSuggestedFollowUps: Bool
    }

    public struct ExecutionInfo: Codable, Equatable, Sendable {
        public var intent: String
        public var executionLaneKey: String?
        public var executionLaneKeyVersion: String?
        public var executionLanePolicy: String
        public var executionLaneOrder: Int?
        public var executionLaneHeadItemId: String?
        public var executionLaneBlockedByItemId: String?
        public var executionLanePausedReason: String?
    }

    public struct SafetyInfo: Codable, Equatable, Sendable {
        public var workingDir: String?
        public var requiresTrustedDevice: Bool
        public var privacyLabel: String?
    }

    public struct AdmissionInfo: Codable, Equatable, Sendable {
        public var state: String
        public var source: String?
        public var observedAt: String?
        public var resetAt: String?
        public var confidence: String?
        public var reason: String?
    }

    public struct AttemptInfo: Codable, Equatable, Sendable {
        public var attemptId: String
        public var createdAt: String
        public var startedAt: String?
        public var completedAt: String?
        public var workerIds: [String]
        public var status: String
        public var executionLaneKey: String?
        public var reason: String?
    }

    public struct NextAction: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case submitPending, runPending, showPending, cancelPending
        }

        public var kind: Kind
        public var command: String
        public var label: String?

        public init(kind: Kind, command: String, label: String? = nil) {
            self.kind = kind
            self.command = command
            self.label = label
        }
    }

    public struct AuditInfo: Codable, Equatable, Sendable {
        public var traceId: String
        public var pendingStorePath: String
        public var userReorderedExecutionLane: Bool?

        public init(traceId: String, pendingStorePath: String, userReorderedExecutionLane: Bool? = nil) {
            self.traceId = traceId
            self.pendingStorePath = pendingStorePath
            self.userReorderedExecutionLane = userReorderedExecutionLane
        }
    }
}

/// `alln pending list --json` proof surface for floor snapshots.
public struct PendingListJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var items: [PendingItemJSON]

    public init(schemaVersion: Int = 1, contractVersion: String, items: [PendingItemJSON]) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.items = items
    }
}
