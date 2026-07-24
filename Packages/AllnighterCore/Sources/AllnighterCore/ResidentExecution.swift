import Foundation

/// Client wait budgets for resident operations. A request is durable once the
/// broker claims it, so the foreground wait must reflect the operation's real
/// bounded work rather than a one-size-fits-all rendezvous poll default.
public enum ResidentExecutionWaitBudget {
    /// Full driver smoke probes have a 60-second per-driver timeout.
    public static let sourceProbe: TimeInterval = 130
    /// A Panel round may wait for several real source CLIs to return.
    public static let panelRound: TimeInterval = 1_800
}

/// Typed work accepted by the resident execution authority.  This is a closed
/// union: a foreground client can request product operations, never a shell,
/// environment, executable path, or arbitrary process arguments.
public enum ResidentExecutionOperation: Codable, Equatable, Sendable {
    case teamRun(AsyncTeamStartRequest)
    case panelStart(PanelStart)
    case panelRound(PanelRound)
    case panelDone(PanelDone)
    case sourceProbe(SourceProbe)
    case boostSeed(BoostSeed)
    case pendingRun(PendingRun)
    case projectRecheck(ProjectRecheck)
    case query(Query)
    case cancel(Cancel)
    case teamCancel(TeamCancel)
    case teamReconcile(TeamReconcile)
    case admissionProbe(AdmissionProbe)

    public struct PanelStart: Codable, Equatable, Sendable {
        public var projectRoot: String
        public var projectId: String
        public var targetPath: String
        public var teamId: String?
        public var seats: [PanelSeat]
        public var maxRounds: Int
        public var rememberedTeam: Bool
        public var laneDefault: Bool

        public init(
            projectRoot: String,
            projectId: String,
            targetPath: String,
            teamId: String? = nil,
            seats: [PanelSeat],
            maxRounds: Int,
            rememberedTeam: Bool = false,
            laneDefault: Bool = false
        ) {
            self.projectRoot = projectRoot
            self.projectId = projectId
            self.targetPath = targetPath
            self.teamId = teamId
            self.seats = seats
            self.maxRounds = maxRounds
            self.rememberedTeam = rememberedTeam
            self.laneDefault = laneDefault
        }
    }

    public struct PanelRound: Codable, Equatable, Sendable {
        public var panelId: String
        public var brief: String?
        public var seatFilter: [String]?
        public init(panelId: String, brief: String? = nil, seatFilter: [String]? = nil) {
            self.panelId = panelId
            self.brief = brief
            self.seatFilter = seatFilter
        }
    }

    public struct PanelDone: Codable, Equatable, Sendable {
        public var panelId: String
        public var note: String?
        public init(panelId: String, note: String? = nil) {
            self.panelId = panelId
            self.note = note
        }
    }

    public struct SourceProbe: Codable, Equatable, Sendable {
        public enum Intent: String, Codable, Sendable { case doctor, detect }
        public var sourceId: String?
        public var full: Bool
        public var intent: Intent
        public var pilot: Bool
        public var projectToken: String?
        public var workingDirectory: String?
        /// Optional, client-computed Git commit identity for the checkout from
        /// which `doctor` was invoked. This is deliberately a value rather
        /// than a path: the resident must never inspect a restricted caller's
        /// workspace merely to diagnose binary freshness.
        public var workspaceHeadSha: String?
        public init(
            sourceId: String? = nil,
            full: Bool,
            intent: Intent = .doctor,
            pilot: Bool = false,
            projectToken: String? = nil,
            workingDirectory: String? = nil,
            workspaceHeadSha: String? = nil
        ) {
            self.sourceId = sourceId
            self.full = full
            self.intent = intent
            self.pilot = pilot
            self.projectToken = projectToken
            self.workingDirectory = workingDirectory
            self.workspaceHeadSha = workspaceHeadSha
        }
    }

    public struct BoostSeed: Codable, Equatable, Sendable {
        public var sourceId: String

        public init(sourceId: String) {
            self.sourceId = sourceId
        }
    }

    /// Runs a previously persisted Pending item. The client may create and
    /// manage the item, but worker invocation and settlement belong to the
    /// resident coordinator.
    public struct PendingRun: Codable, Equatable, Sendable {
        public var pendingItemId: String

        public init(pendingItemId: String) {
            self.pendingItemId = pendingItemId
        }
    }

    /// Refreshes one project's safe, driver-declared readiness probes. The
    /// project client resolves its identity, while process ownership and the
    /// persisted freshness record remain in the resident service.
    public struct ProjectRecheck: Codable, Equatable, Sendable {
        public var projectId: String
        public var rootPath: String

        public init(projectId: String, rootPath: String) {
            self.projectId = projectId
            self.rootPath = rootPath
        }
    }

    public struct Query: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case health
            case runStatus
            case runResult
            case panelStatus
            case panelResult
            case processSnapshot
        }
        public var kind: Kind
        public var canonicalId: String?
        public var scopeRoot: String?
        public init(kind: Kind, canonicalId: String? = nil, scopeRoot: String? = nil) {
            self.kind = kind
            self.canonicalId = canonicalId
            self.scopeRoot = scopeRoot
        }
    }

    public struct Cancel: Codable, Equatable, Sendable {
        public var canonicalId: String?
        public var all: Bool
        public var scopeRoot: String?
        public init(canonicalId: String? = nil, all: Bool = false, scopeRoot: String? = nil) {
            self.canonicalId = canonicalId
            self.all = all
            self.scopeRoot = scopeRoot
        }
    }

    /// Lifecycle cancellation is distinct from the process-ownership surface.
    /// The former settles Team journal truth; the latter only addresses an
    /// explicitly owned process tree. Keeping them separate prevents a client
    /// from accidentally bypassing resident lifecycle reconciliation.
    public struct TeamCancel: Codable, Equatable, Sendable {
        public var runId: String
        public init(runId: String) { self.runId = runId }
    }

    public struct TeamReconcile: Codable, Equatable, Sendable {
        public var runId: String?
        public var scopeRoot: String?
        public init(runId: String? = nil, scopeRoot: String? = nil) {
            self.runId = runId
            self.scopeRoot = scopeRoot
        }
    }

    /// Free control-plane probe. It reserves no worker and starts no vendor
    /// process, but deliberately travels through the exact durable acceptance
    /// and idempotency gate used by a paid Team start.
    public struct AdmissionProbe: Codable, Equatable, Sendable {
        public var scope: String
        public init(scope: String = "doctor") { self.scope = scope }
    }

    public enum Kind: String, Codable, Sendable {
        case teamRun, panelStart, panelRound, panelDone, sourceProbe, boostSeed, pendingRun, projectRecheck, query, cancel, teamCancel, teamReconcile, admissionProbe
    }

    private enum CodingKeys: String, CodingKey { case type, payload }

    public var kind: Kind {
        switch self {
        case .teamRun: return .teamRun
        case .panelStart: return .panelStart
        case .panelRound: return .panelRound
        case .panelDone: return .panelDone
        case .sourceProbe: return .sourceProbe
        case .boostSeed: return .boostSeed
        case .pendingRun: return .pendingRun
        case .projectRecheck: return .projectRecheck
        case .query: return .query
        case .cancel: return .cancel
        case .teamCancel: return .teamCancel
        case .teamReconcile: return .teamReconcile
        case .admissionProbe: return .admissionProbe
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .teamRun: self = .teamRun(try container.decode(AsyncTeamStartRequest.self, forKey: .payload))
        case .panelStart: self = .panelStart(try container.decode(PanelStart.self, forKey: .payload))
        case .panelRound: self = .panelRound(try container.decode(PanelRound.self, forKey: .payload))
        case .panelDone: self = .panelDone(try container.decode(PanelDone.self, forKey: .payload))
        case .sourceProbe: self = .sourceProbe(try container.decode(SourceProbe.self, forKey: .payload))
        case .boostSeed: self = .boostSeed(try container.decode(BoostSeed.self, forKey: .payload))
        case .pendingRun: self = .pendingRun(try container.decode(PendingRun.self, forKey: .payload))
        case .projectRecheck: self = .projectRecheck(try container.decode(ProjectRecheck.self, forKey: .payload))
        case .query: self = .query(try container.decode(Query.self, forKey: .payload))
        case .cancel: self = .cancel(try container.decode(Cancel.self, forKey: .payload))
        case .teamCancel: self = .teamCancel(try container.decode(TeamCancel.self, forKey: .payload))
        case .teamReconcile: self = .teamReconcile(try container.decode(TeamReconcile.self, forKey: .payload))
        case .admissionProbe: self = .admissionProbe(try container.decode(AdmissionProbe.self, forKey: .payload))
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
        case let .boostSeed(value): try container.encode(value, forKey: .payload)
        case let .pendingRun(value): try container.encode(value, forKey: .payload)
        case let .projectRecheck(value): try container.encode(value, forKey: .payload)
        case let .query(value): try container.encode(value, forKey: .payload)
        case let .cancel(value): try container.encode(value, forKey: .payload)
        case let .teamCancel(value): try container.encode(value, forKey: .payload)
        case let .teamReconcile(value): try container.encode(value, forKey: .payload)
        case let .admissionProbe(value): try container.encode(value, forKey: .payload)
        }
    }
}

/// A signed request placed into the resident coordinator's local inbox.
public struct ResidentExecutionRequest: Codable, Equatable, Sendable {
    public struct Client: Codable, Equatable, Sendable {
        public var binaryVersion: String
        /// Exact source-build identity. Resident work is rejected on a mismatch.
        public var binaryGitSha: String
        public var contractVersion: String
        public var pid: Int32
        public var origin: String

        public init(
            binaryVersion: String,
            binaryGitSha: String = AllnighterBuildInfo.gitSha,
            contractVersion: String,
            pid: Int32,
            origin: String = "cli"
        ) {
            self.binaryVersion = binaryVersion
            self.binaryGitSha = binaryGitSha
            self.contractVersion = contractVersion
            self.pid = pid
            self.origin = origin
        }
    }

    public var schemaVersion: Int
    public var requestId: String
    public var idempotencyKey: String
    public var submittedAt: Date
    public var coordinatorId: String
    public var coordinatorNonce: String
    public var client: Client
    public var operation: ResidentExecutionOperation
    public var clientProof: ResidentClientProof

    public init(
        schemaVersion: Int = 1,
        requestId: String,
        idempotencyKey: String,
        submittedAt: Date,
        coordinatorId: String,
        coordinatorNonce: String,
        client: Client = .init(
            binaryVersion: AllnighterVersionIdentity.binaryVersion,
            binaryGitSha: AllnighterBuildInfo.gitSha,
            contractVersion: ContractRegistry.contractVersion,
            pid: ProcessInfo.processInfo.processIdentifier
        ),
        operation: ResidentExecutionOperation,
        clientProof: ResidentClientProof
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.submittedAt = submittedAt
        self.coordinatorId = coordinatorId
        self.coordinatorNonce = coordinatorNonce
        self.client = client
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
    /// The submission key that created this receipt. Clients must retain this
    /// value and use it for a retry; a receipt or timeout without the key makes
    /// an exactly-once retry impossible.
    public var idempotencyKey: String?
    public var canonicalId: String?
    public var state: State
    public var acceptedAt: Date
    public var result: ResidentExecutionResult?
    public var rejection: ResidentExecutionRejection?

    public init(
        schemaVersion: Int = 1,
        requestId: String,
        idempotencyKey: String? = nil,
        canonicalId: String? = nil,
        state: State,
        acceptedAt: Date,
        result: ResidentExecutionResult? = nil,
        rejection: ResidentExecutionRejection? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.canonicalId = canonicalId
        self.state = state
        self.acceptedAt = acceptedAt
        self.result = result
        self.rejection = rejection
    }
}

/// Typed acceptance payload. Result-bearing commands reuse their existing
/// public contracts rather than inventing broker-only JSON.
public enum ResidentExecutionResult: Codable, Equatable, Sendable {
    case coordinatorHealth(CoordinatorHealth)
    case teamStart(TeamStartResponse)
    case teamStatus(TeamStatusResponse)
    case teamResult(TeamRunJSON)
    case teamResultNotReady(TeamResultNotReady)
    case teamCancel(TeamCancelResponse)
    case teamReconcile(TeamReconcileResponse)
    case admissionProbe(AdmissionProbeResult)
    case panelStart(PanelStartJSON)
    case panelRound(PanelRoundJSON)
    case panelStatus(PanelJSON)
    case doctor(DoctorResult)
    case detection(ResidentDetectionResult)
    case ownership(OwnershipPsJSON)
    case ownershipKill(OwnershipKillJSON)
    case utilizationSeed(UtilizationSeedEvent)
    case pendingItem(PendingItem)
    case projectWorkerReadiness([ProjectWorkerReadiness])

    private enum CodingKeys: String, CodingKey { case type, payload }
    private enum Kind: String, Codable {
        case coordinatorHealth, teamStart, teamStatus, teamResult, teamResultNotReady, teamCancel, teamReconcile, admissionProbe, panelStart, panelRound, panelStatus, doctor, detection, ownership, ownershipKill, utilizationSeed, pendingItem, projectWorkerReadiness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .coordinatorHealth: self = .coordinatorHealth(try container.decode(CoordinatorHealth.self, forKey: .payload))
        case .teamStart: self = .teamStart(try container.decode(TeamStartResponse.self, forKey: .payload))
        case .teamStatus: self = .teamStatus(try container.decode(TeamStatusResponse.self, forKey: .payload))
        case .teamResult: self = .teamResult(try container.decode(TeamRunJSON.self, forKey: .payload))
        case .teamResultNotReady: self = .teamResultNotReady(try container.decode(TeamResultNotReady.self, forKey: .payload))
        case .teamCancel: self = .teamCancel(try container.decode(TeamCancelResponse.self, forKey: .payload))
        case .teamReconcile: self = .teamReconcile(try container.decode(TeamReconcileResponse.self, forKey: .payload))
        case .admissionProbe: self = .admissionProbe(try container.decode(AdmissionProbeResult.self, forKey: .payload))
        case .panelStart: self = .panelStart(try container.decode(PanelStartJSON.self, forKey: .payload))
        case .panelRound: self = .panelRound(try container.decode(PanelRoundJSON.self, forKey: .payload))
        case .panelStatus: self = .panelStatus(try container.decode(PanelJSON.self, forKey: .payload))
        case .doctor: self = .doctor(try container.decode(DoctorResult.self, forKey: .payload))
        case .detection: self = .detection(try container.decode(ResidentDetectionResult.self, forKey: .payload))
        case .ownership: self = .ownership(try container.decode(OwnershipPsJSON.self, forKey: .payload))
        case .ownershipKill: self = .ownershipKill(try container.decode(OwnershipKillJSON.self, forKey: .payload))
        case .utilizationSeed: self = .utilizationSeed(try container.decode(UtilizationSeedEvent.self, forKey: .payload))
        case .pendingItem: self = .pendingItem(try container.decode(PendingItem.self, forKey: .payload))
        case .projectWorkerReadiness: self = .projectWorkerReadiness(try container.decode([ProjectWorkerReadiness].self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .coordinatorHealth(value):
            try container.encode(Kind.coordinatorHealth, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .teamStart(value):
            try container.encode(Kind.teamStart, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .teamStatus(value):
            try container.encode(Kind.teamStatus, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .teamResult(value):
            try container.encode(Kind.teamResult, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .teamResultNotReady(value):
            try container.encode(Kind.teamResultNotReady, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .teamCancel(value):
            try container.encode(Kind.teamCancel, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .teamReconcile(value):
            try container.encode(Kind.teamReconcile, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .admissionProbe(value):
            try container.encode(Kind.admissionProbe, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .panelStart(value):
            try container.encode(Kind.panelStart, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .panelRound(value):
            try container.encode(Kind.panelRound, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .panelStatus(value):
            try container.encode(Kind.panelStatus, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .doctor(value):
            try container.encode(Kind.doctor, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .detection(value):
            try container.encode(Kind.detection, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .ownership(value):
            try container.encode(Kind.ownership, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .ownershipKill(value):
            try container.encode(Kind.ownershipKill, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .utilizationSeed(value):
            try container.encode(Kind.utilizationSeed, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .pendingItem(value):
            try container.encode(Kind.pendingItem, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .projectWorkerReadiness(value):
            try container.encode(Kind.projectWorkerReadiness, forKey: .type)
            try container.encode(value, forKey: .payload)
        }
    }
}

/// Coordinator-owned setup detection projection. The returned records are
/// presentation data; the resident's persisted setup cache remains execution
/// truth for future dispatch.
public struct ResidentDetectionResult: Codable, Equatable, Sendable {
    public var records: [ToolProbeRecord]
    public var assembledTeam: TeamAssembler.Assembled

    public init(records: [ToolProbeRecord], assembledTeam: TeamAssembler.Assembled) {
        self.records = records
        self.assembledTeam = assembledTeam
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
    /// Existing run event projected through the sandbox-safe rendezvous. Nil
    /// for non-run broker lifecycle notices.
    public var runEvent: RunEvent?

    public init(
        requestId: String,
        sequence: Int,
        state: State,
        emittedAt: Date,
        message: String? = nil,
        runEvent: RunEvent? = nil
    ) {
        self.requestId = requestId
        self.sequence = sequence
        self.state = state
        self.emittedAt = emittedAt
        self.message = message
        self.runEvent = runEvent
    }
}
