import Foundation

// MARK: - Lifecycle

public enum PendingItemStatus: String, Codable, Sendable, CaseIterable {
    case draft, pending, running, done, failed, cancelled
}

public enum PendingItemKind: String, Codable, Sendable, CaseIterable {
    case workerChat, teamRun, workOrder, dispatch, returnReview, followUp
}

public enum PendingItemPriority: String, Codable, Sendable, CaseIterable {
    case pinned, normal, low
}

public enum PendingCreatedBy: String, Codable, Sendable, CaseIterable {
    case user, preset, failedRun, returnReview, approvedSuggestion, remoteDevice
}

public enum PendingOrigin: String, Codable, Sendable, CaseIterable {
    case cli, gui, mcp, ios, localApi, system, preset
}

// MARK: - Target / policy / execution

public struct PendingTarget: Codable, Sendable, Equatable {
    public var workerIds: [String]
    public var teamPresetId: String?
    public var preferredWorkerIds: [String]
    public var fallbackWorkerIds: [String]
    public var requiredWorkerIds: [String]
    public var minWorkers: Int?

    public init(
        workerIds: [String] = [],
        teamPresetId: String? = nil,
        preferredWorkerIds: [String] = [],
        fallbackWorkerIds: [String] = [],
        requiredWorkerIds: [String] = [],
        minWorkers: Int? = nil
    ) {
        self.workerIds = workerIds
        self.teamPresetId = teamPresetId
        self.preferredWorkerIds = preferredWorkerIds
        self.fallbackWorkerIds = fallbackWorkerIds
        self.requiredWorkerIds = requiredWorkerIds
        self.minWorkers = minWorkers
    }
}

public enum PendingSelectionPolicy: String, Codable, Sendable, CaseIterable {
    case selectedOnly, allowFallbacks, allowPartialTeam, requireFullTeam
}

public enum PendingAttentionMode: String, Codable, Sendable, CaseIterable {
    case present, away
}

public enum PendingDrainMode: String, Codable, Sendable, CaseIterable {
    case manualStart, drainWhenReady, drainAway
}

public struct PendingPolicy: Codable, Sendable, Equatable {
    public var selection: PendingSelectionPolicy
    public var attentionMode: PendingAttentionMode
    public var drainMode: PendingDrainMode
    public var maxAttempts: Int?
    public var retryFloorSeconds: Int?
    public var allowDegraded: Bool
    public var requireKnownAvailable: Bool
    public var createSuggestedFollowUps: Bool

    public init(
        selection: PendingSelectionPolicy = .selectedOnly,
        attentionMode: PendingAttentionMode = .present,
        drainMode: PendingDrainMode = .manualStart,
        maxAttempts: Int? = nil,
        retryFloorSeconds: Int? = nil,
        allowDegraded: Bool = false,
        requireKnownAvailable: Bool = false,
        createSuggestedFollowUps: Bool = false
    ) {
        self.selection = selection
        self.attentionMode = attentionMode
        self.drainMode = drainMode
        self.maxAttempts = maxAttempts
        self.retryFloorSeconds = retryFloorSeconds
        self.allowDegraded = allowDegraded
        self.requireKnownAvailable = requireKnownAvailable
        self.createSuggestedFollowUps = createSuggestedFollowUps
    }
}

public enum PendingExecutionIntent: String, Codable, Sendable, CaseIterable {
    case ask, execute
}

public enum PendingExecutionLanePolicy: String, Codable, Sendable, CaseIterable {
    case fifo, userOrdered
}

public struct PendingExecution: Codable, Sendable, Equatable {
    public var intent: PendingExecutionIntent
    public var executionLaneKey: String?
    public var executionLaneKeyVersion: String?
    public var executionLanePolicy: PendingExecutionLanePolicy
    public var executionLaneOrder: Int?

    public init(
        intent: PendingExecutionIntent,
        executionLaneKey: String? = nil,
        executionLaneKeyVersion: String? = "v1",
        executionLanePolicy: PendingExecutionLanePolicy = .fifo,
        executionLaneOrder: Int? = nil
    ) {
        self.intent = intent
        self.executionLaneKey = executionLaneKey
        self.executionLaneKeyVersion = executionLaneKeyVersion
        self.executionLanePolicy = executionLanePolicy
        self.executionLaneOrder = executionLaneOrder
    }
}

public struct PendingSafety: Codable, Sendable, Equatable {
    public var workingDir: String?
    public var requiresTrustedDevice: Bool
    public var privacyLabel: String?

    public init(workingDir: String? = nil, requiresTrustedDevice: Bool = false, privacyLabel: String? = nil) {
        self.workingDir = workingDir
        self.requiresTrustedDevice = requiresTrustedDevice
        self.privacyLabel = privacyLabel
    }
}

// MARK: - Resume / lease / attempts

public enum PendingResumeReason: String, Codable, Sendable, CaseIterable {
    case cooldown, localBusy, timeout, stopped, appRestart, macSleep, userPaused
}

public struct PendingResume: Codable, Sendable, Equatable {
    public var reason: PendingResumeReason
    public var lastAttemptId: String?
    public var transcriptRef: String?
    public var nextInstruction: String?
    public var observedResetAt: Date?
    public var wakeAfter: Date?

    public init(
        reason: PendingResumeReason,
        lastAttemptId: String? = nil,
        transcriptRef: String? = nil,
        nextInstruction: String? = nil,
        observedResetAt: Date? = nil,
        wakeAfter: Date? = nil
    ) {
        self.reason = reason
        self.lastAttemptId = lastAttemptId
        self.transcriptRef = transcriptRef
        self.nextInstruction = nextInstruction
        self.observedResetAt = observedResetAt
        self.wakeAfter = wakeAfter
    }
}

public enum PendingLeaseOwner: String, Codable, Sendable, CaseIterable {
    case serve, cli, gui, localApi
}

public struct PendingLease: Codable, Sendable, Equatable {
    public var leaseId: String
    public var owner: PendingLeaseOwner
    public var leasedAt: Date
    public var expiresAt: Date?
    public var attemptId: String?

    public init(leaseId: String, owner: PendingLeaseOwner, leasedAt: Date, expiresAt: Date? = nil, attemptId: String? = nil) {
        self.leaseId = leaseId
        self.owner = owner
        self.leasedAt = leasedAt
        self.expiresAt = expiresAt
        self.attemptId = attemptId
    }
}

public enum PendingAttemptStatus: String, Codable, Sendable, CaseIterable {
    case queued, running, done, failed, timedOut, cancelled, skipped, blocked
}

public struct PendingAttemptSummary: Codable, Sendable, Equatable, Identifiable {
    public var attemptId: String
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var workerIds: [String]
    public var status: PendingAttemptStatus
    public var admissionEventIds: [String]
    public var executionLaneKey: String?
    public var reason: String?

    public var id: String { attemptId }

    public init(
        attemptId: String,
        createdAt: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        workerIds: [String] = [],
        status: PendingAttemptStatus,
        admissionEventIds: [String] = [],
        executionLaneKey: String? = nil,
        reason: String? = nil
    ) {
        self.attemptId = attemptId
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.workerIds = workerIds
        self.status = status
        self.admissionEventIds = admissionEventIds
        self.executionLaneKey = executionLaneKey
        self.reason = reason
    }
}

public enum PendingExecutionLanePauseReason: String, Codable, Sendable, CaseIterable {
    case user, editLock
}

public struct PendingExecutionLaneState: Codable, Sendable, Equatable {
    public var executionLaneKey: String
    public var executionLanePolicy: PendingExecutionLanePolicy
    public var pausedReason: PendingExecutionLanePauseReason?
    public var orderedItemIds: [String]
    public var editLease: PendingLease?

    public init(
        executionLaneKey: String,
        executionLanePolicy: PendingExecutionLanePolicy = .fifo,
        pausedReason: PendingExecutionLanePauseReason? = nil,
        orderedItemIds: [String] = [],
        editLease: PendingLease? = nil
    ) {
        self.executionLaneKey = executionLaneKey
        self.executionLanePolicy = executionLanePolicy
        self.pausedReason = pausedReason
        self.orderedItemIds = orderedItemIds
        self.editLease = editLease
    }
}

// MARK: - Root item

/// Durable user intent for Pending work (docs/phases/Pending_Work_And_Drain.md).
public struct PendingItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String?
    /// Owning Project (PRJ-S04). `nil` = Unassigned: visible in the repair bucket,
    /// blocked from running until assigned. New Pending items require a `projectId`.
    public var projectId: String?
    /// Link to the WorkOrder this Pending item runs, when it is one.
    public var workOrderId: String?
    public var title: String
    public var kind: PendingItemKind
    public var status: PendingItemStatus
    public var priority: PendingItemPriority
    public var createdAt: Date
    public var updatedAt: Date
    public var submittedAt: Date?
    public var createdBy: PendingCreatedBy
    public var origin: PendingOrigin
    public var prompt: String
    public var contextPacketId: String?
    public var seedTurnId: String?
    public var runId: String?
    public var stageId: String?
    public var target: PendingTarget
    public var policy: PendingPolicy
    public var execution: PendingExecution?
    public var safety: PendingSafety
    public var resume: PendingResume?
    public var lease: PendingLease?
    public var attempts: [PendingAttemptSummary]
    public var expiresAt: Date?

    public init(
        id: String,
        threadId: String? = nil,
        projectId: String? = nil,
        workOrderId: String? = nil,
        title: String,
        kind: PendingItemKind,
        status: PendingItemStatus,
        priority: PendingItemPriority = .normal,
        createdAt: Date,
        updatedAt: Date,
        submittedAt: Date? = nil,
        createdBy: PendingCreatedBy = .user,
        origin: PendingOrigin = .cli,
        prompt: String,
        contextPacketId: String? = nil,
        seedTurnId: String? = nil,
        runId: String? = nil,
        stageId: String? = nil,
        target: PendingTarget,
        policy: PendingPolicy,
        execution: PendingExecution? = nil,
        safety: PendingSafety = PendingSafety(),
        resume: PendingResume? = nil,
        lease: PendingLease? = nil,
        attempts: [PendingAttemptSummary] = [],
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.projectId = projectId
        self.workOrderId = workOrderId
        self.title = title
        self.kind = kind
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.submittedAt = submittedAt
        self.createdBy = createdBy
        self.origin = origin
        self.prompt = prompt
        self.contextPacketId = contextPacketId
        self.seedTurnId = seedTurnId
        self.runId = runId
        self.stageId = stageId
        self.target = target
        self.policy = policy
        self.execution = execution
        self.safety = safety
        self.resume = resume
        self.lease = lease
        self.attempts = attempts
        self.expiresAt = expiresAt
    }
}

public extension PendingItem {
    /// PRJ-S04: bound to a Project. Unassigned items (`projectId == nil`) live in
    /// the repair bucket and are blocked from running until assigned.
    var isProjectAssigned: Bool { projectId != nil }

    /// The path to bind from when migrating — the safety working-dir receipt.
    /// (Thread/run binding is resolved first by the migrator.) Working-directory
    /// snapshots are receipts only, never the scope owner after migration.
    var localRootPathSnapshot: String? { safety.workingDir }
}

/// On-disk index for Pending store ordering and execution-lane state.
public struct PendingStoreIndex: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var itemOrder: [String]
    public var executionLanes: [PendingExecutionLaneState]

    public init(schemaVersion: Int = 1, itemOrder: [String] = [], executionLanes: [PendingExecutionLaneState] = []) {
        self.schemaVersion = schemaVersion
        self.itemOrder = itemOrder
        self.executionLanes = executionLanes
    }
}
