import Foundation

// MARK: - Project Spine contract (PRJ-S00)
//
// The durable Core models for Projects and the Project Manager loop, per
// `docs/phases/Project_Spine_And_Project_Manager.md`. Models only — no store
// (PRJ-S01), no engine (PRJ-S08+), no GUI. Public JSON projection (string dates,
// schemaVersion) lands with the CLI in PRJ-S07. Durable models use `Date` and the
// canonical `CoreJSON` (.iso8601) encoding like the rest of Core.

// MARK: Identifiers

public typealias ProjectID = String
public typealias ProposalID = String
public typealias WorkOrderID = String
public typealias WorkReturnID = String
public typealias VerificationID = String
public typealias ManagerTurnID = String

// MARK: - Project

/// Whether a Project root is a git repo or a plain folder (reduced guarantees).
public enum ProjectKind: String, Codable, Sendable, CaseIterable {
    case gitRepo
    case folder
}

/// Observed availability of a Project's local root. Never inferred — observed.
public enum RootState: String, Codable, Sendable, CaseIterable {
    case available
    case missing
    case permissionDenied
}

/// The product-owned representation of a local work floor.
public struct Project: Codable, Sendable, Equatable, Identifiable {
    public var id: ProjectID
    public var displayName: String
    /// User-facing display path (expanded `~`, standardized). Not the dup key.
    public var localRootPath: String
    /// Duplicate-detection key (symlink-resolved + standardized). See `RootNormalization`.
    public var normalizedRootPath: String
    public var kind: ProjectKind
    public var rootState: RootState
    public var gitRemoteURL: String?
    public var gitBranch: String?
    public var gitHead: String?
    public var gitDirtySummary: String?
    public var createdAt: Date
    public var lastOpenedAt: Date
    public var pinned: Bool
    public var archived: Bool
    public var docsEntrypoints: [String]
    public var proofCommands: [String]
    public var workerReadinessSummary: String?
    public var defaultCodeTeamId: String?
    public var defaultDesignTeamId: String?
    public var defaultCopyTeamId: String?
    public var managerThreadId: String?
    public var managerModelId: String?

    public init(
        id: ProjectID,
        displayName: String,
        localRootPath: String,
        normalizedRootPath: String,
        kind: ProjectKind,
        rootState: RootState = .available,
        gitRemoteURL: String? = nil,
        gitBranch: String? = nil,
        gitHead: String? = nil,
        gitDirtySummary: String? = nil,
        createdAt: Date,
        lastOpenedAt: Date,
        pinned: Bool = false,
        archived: Bool = false,
        docsEntrypoints: [String] = [],
        proofCommands: [String] = [],
        workerReadinessSummary: String? = nil,
        defaultCodeTeamId: String? = nil,
        defaultDesignTeamId: String? = nil,
        defaultCopyTeamId: String? = nil,
        managerThreadId: String? = nil,
        managerModelId: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.localRootPath = localRootPath
        self.normalizedRootPath = normalizedRootPath
        self.kind = kind
        self.rootState = rootState
        self.gitRemoteURL = gitRemoteURL
        self.gitBranch = gitBranch
        self.gitHead = gitHead
        self.gitDirtySummary = gitDirtySummary
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.pinned = pinned
        self.archived = archived
        self.docsEntrypoints = docsEntrypoints
        self.proofCommands = proofCommands
        self.workerReadinessSummary = workerReadinessSummary
        self.defaultCodeTeamId = defaultCodeTeamId
        self.defaultDesignTeamId = defaultDesignTeamId
        self.defaultCopyTeamId = defaultCopyTeamId
        self.managerThreadId = managerThreadId
        self.managerModelId = managerModelId
    }

    /// Mutating dispatch requires an available root and an un-archived Project.
    public var allowsMutatingDispatch: Bool { rootState == .available && !archived }

    /// A non-git folder can never be marked commit-verified (see VerificationRecord).
    public var canClaimCommitVerification: Bool { kind == .gitRepo }
}

// MARK: - Project worker readiness

/// Whether a specific worker can safely run inside this Project root right now.
/// Per-Project and driver-probed — global setup is not enough.
public enum WorkerReadinessStatus: String, Codable, Sendable, CaseIterable {
    case ready
    case notInstalled
    case authRequired
    case needsProjectAuthorization
    case interactiveRequired
    case unsafeToProbe
    case blocked
    case unknown

    /// Only `ready` authorizes dispatch to this worker in this Project.
    public var isDispatchable: Bool { self == .ready }
}

/// How a readiness fact was observed.
public enum ProbeKind: String, Codable, Sendable, CaseIterable {
    case silent
    case explicitRecheck
    case userInitiatedRun
}

public struct ProjectWorkerReadiness: Codable, Sendable, Equatable {
    public var projectId: ProjectID
    public var sourceId: String
    public var workerId: String?
    public var status: WorkerReadinessStatus
    public var checkedAt: Date
    public var probeKind: ProbeKind
    public var probeCommandLabel: String?
    public var lastError: String?
    public var setupHint: String?

    public init(
        projectId: ProjectID,
        sourceId: String,
        workerId: String? = nil,
        status: WorkerReadinessStatus,
        checkedAt: Date,
        probeKind: ProbeKind,
        probeCommandLabel: String? = nil,
        lastError: String? = nil,
        setupHint: String? = nil
    ) {
        self.projectId = projectId
        self.sourceId = sourceId
        self.workerId = workerId
        self.status = status
        self.checkedAt = checkedAt
        self.probeKind = probeKind
        self.probeCommandLabel = probeCommandLabel
        self.lastError = lastError
        self.setupHint = setupHint
    }
}

// MARK: - Project context packet (generated, not durable truth)

/// Compact, source-labeled summary the Manager reasons over. Regenerated each
/// turn from owned truth; may be persisted as a receipt but is never authority.
public struct ProjectContextPacket: Codable, Sendable, Equatable, Identifiable {
    public struct Root: Codable, Sendable, Equatable {
        public var localRootPath: String
        public var kind: ProjectKind
        public var rootState: RootState
        public init(localRootPath: String, kind: ProjectKind, rootState: RootState) {
            self.localRootPath = localRootPath; self.kind = kind; self.rootState = rootState
        }
    }
    public struct Git: Codable, Sendable, Equatable {
        public var branch: String?
        public var head: String?
        public var remote: String?
        public var dirtySummary: String?
        public var recentCommits: [String]
        public init(branch: String? = nil, head: String? = nil, remote: String? = nil,
                    dirtySummary: String? = nil, recentCommits: [String] = []) {
            self.branch = branch; self.head = head; self.remote = remote
            self.dirtySummary = dirtySummary; self.recentCommits = recentCommits
        }
    }
    public struct Docs: Codable, Sendable, Equatable {
        public var entrypoints: [String]
        public var recentlyChanged: [String]
        public var staleCandidates: [String]
        public init(entrypoints: [String] = [], recentlyChanged: [String] = [], staleCandidates: [String] = []) {
            self.entrypoints = entrypoints; self.recentlyChanged = recentlyChanged; self.staleCandidates = staleCandidates
        }
    }
    public struct Threads: Codable, Sendable, Equatable {
        public var managerThreadId: String?
        public var recentThreadSummaries: [String]
        public var unresolvedQuestions: [String]
        public init(managerThreadId: String? = nil, recentThreadSummaries: [String] = [], unresolvedQuestions: [String] = []) {
            self.managerThreadId = managerThreadId; self.recentThreadSummaries = recentThreadSummaries
            self.unresolvedQuestions = unresolvedQuestions
        }
    }
    public struct Work: Codable, Sendable, Equatable {
        public var activeRuns: [String]
        public var pendingItems: [String]
        public var openProposals: [String]
        public var recentReturns: [String]
        public var verificationFindings: [String]
        public init(activeRuns: [String] = [], pendingItems: [String] = [], openProposals: [String] = [],
                    recentReturns: [String] = [], verificationFindings: [String] = []) {
            self.activeRuns = activeRuns; self.pendingItems = pendingItems; self.openProposals = openProposals
            self.recentReturns = recentReturns; self.verificationFindings = verificationFindings
        }
    }
    public struct Workers: Codable, Sendable, Equatable {
        public var readinessSummary: String
        public var readyWorkerIds: [String]
        /// Compact projection of ProjectWorkerReadiness entries whose status != ready.
        public var blockedWorkerSummaries: [String]
        public init(readinessSummary: String, readyWorkerIds: [String] = [], blockedWorkerSummaries: [String] = []) {
            self.readinessSummary = readinessSummary; self.readyWorkerIds = readyWorkerIds
            self.blockedWorkerSummaries = blockedWorkerSummaries
        }
    }
    public struct Proof: Codable, Sendable, Equatable {
        public var commands: [String]
        public var lastResults: [String]
        public init(commands: [String] = [], lastResults: [String] = []) {
            self.commands = commands; self.lastResults = lastResults
        }
    }

    /// Stable id so a turn can reference it (`ProjectManagerTurn.contextPacketId`)
    /// and it can be persisted as a receipt.
    public var id: String
    public var projectId: ProjectID
    public var generatedAt: Date
    public var root: Root
    public var git: Git
    public var docs: Docs
    public var threads: Threads
    public var work: Work
    public var workers: Workers
    public var proof: Proof
    public var warnings: [String]

    public init(id: String, projectId: ProjectID, generatedAt: Date, root: Root, git: Git = .init(),
                docs: Docs = .init(), threads: Threads = .init(), work: Work = .init(),
                workers: Workers, proof: Proof = .init(), warnings: [String] = []) {
        self.id = id; self.projectId = projectId; self.generatedAt = generatedAt; self.root = root
        self.git = git; self.docs = docs; self.threads = threads; self.work = work
        self.workers = workers; self.proof = proof; self.warnings = warnings
    }
}

// MARK: - Project Manager turn

/// What the Manager is doing in a turn. The Manager never auto-fires: `delegate`
/// (send a team) and `dispatch` (make-real) are proposed and human-triggered.
public enum ManagerTurnMode: String, Codable, Sendable, CaseIterable {
    case answer
    case orient
    case propose
    case delegate
    case handoff
    case dispatch
    case verify
    case wait
}

/// A typed next action (never prose-only).
public enum NextActionKind: String, Codable, Sendable, CaseIterable {
    case approve
    case edit
    case postpone
    case reveal
    case dispatch
    case verify
    case sendTeam
    case recheckWorkers
    case openProject
    case askUser
}

public struct ProjectNextAction: Codable, Sendable, Equatable {
    public var kind: NextActionKind
    public var label: String
    public var command: String?
    public init(kind: NextActionKind, label: String, command: String? = nil) {
        self.kind = kind; self.label = label; self.command = command
    }
}

/// The reveal/handoff payload a Manager turn can carry (no dispatch on its own).
public struct ProjectHandoff: Codable, Sendable, Equatable {
    public var workOrderId: WorkOrderID?
    public var revealMarkdown: String?
    public init(workOrderId: WorkOrderID? = nil, revealMarkdown: String? = nil) {
        self.workOrderId = workOrderId; self.revealMarkdown = revealMarkdown
    }
}

/// Every Manager response is a typed turn projected into chat.
public struct ProjectManagerTurn: Codable, Sendable, Equatable, Identifiable {
    public var id: ManagerTurnID
    public var projectId: ProjectID
    public var threadId: String
    public var userMessageId: String
    public var createdAt: Date
    public var mode: ManagerTurnMode
    public var contextPacketId: String?
    public var answerMarkdown: String?
    public var proposals: [ProposalID]
    public var handoff: ProjectHandoff?
    public var verification: VerificationID?
    public var warnings: [String]
    public var nextActions: [ProjectNextAction]

    public init(
        id: ManagerTurnID,
        projectId: ProjectID,
        threadId: String,
        userMessageId: String,
        createdAt: Date,
        mode: ManagerTurnMode,
        contextPacketId: String? = nil,
        answerMarkdown: String? = nil,
        proposals: [ProposalID] = [],
        handoff: ProjectHandoff? = nil,
        verification: VerificationID? = nil,
        warnings: [String] = [],
        nextActions: [ProjectNextAction] = []
    ) {
        self.id = id; self.projectId = projectId; self.threadId = threadId
        self.userMessageId = userMessageId; self.createdAt = createdAt; self.mode = mode
        self.contextPacketId = contextPacketId; self.answerMarkdown = answerMarkdown
        self.proposals = proposals; self.handoff = handoff; self.verification = verification
        self.warnings = warnings; self.nextActions = nextActions
    }

    /// Inference ban (Chat -> work order): a pure answer/orient turn never carries
    /// proposals; proposal creation is explicit (`propose`/`delegate` modes).
    public var isWellFormed: Bool {
        switch mode {
        case .answer, .orient, .wait: return proposals.isEmpty
        case .dispatch: return handoff?.workOrderId != nil
        case .verify: return verification != nil
        case .propose, .delegate, .handoff: return true
        }
    }
}

// MARK: - Proposal

/// The bounded next moves the Manager may propose (Legal Proposal Kinds).
public enum ProposalKind: String, Codable, Sendable, CaseIterable {
    case spec_explore
    case synthesis_review
    case execute_slice
    case docs_reconcile
    case verify_completion
    case audit
    case deslop
    case ask_user
    case wait
}

/// Lifecycle of a proposal. Transition rules are the proposal state machine.
public enum ProposalStatus: String, Codable, Sendable, CaseIterable {
    case proposed
    case approved
    case postponed
    case running
    case returned
    case verified
    case blocked
    case cancelled

    public var isTerminal: Bool { self == .verified || self == .cancelled }

    /// Allowed forward transitions. Anything else is rejected by the engine.
    public func canTransition(to next: ProposalStatus) -> Bool {
        switch self {
        case .proposed:  return [.approved, .postponed, .blocked, .cancelled].contains(next)
        case .approved:  return [.running, .postponed, .blocked, .cancelled].contains(next)
        case .running:   return [.returned, .blocked, .cancelled].contains(next)
        case .returned:  return [.verified, .blocked, .cancelled].contains(next)
        case .postponed: return [.proposed, .approved, .cancelled].contains(next)
        case .blocked:   return [.proposed, .approved, .cancelled].contains(next)
        case .verified, .cancelled: return false   // terminal
        }
    }
}

/// Who approved a proposal, when, and the hash of the approved content.
public struct ProjectApproval: Codable, Sendable, Equatable {
    public var approvedBy: String
    public var approvedAt: Date
    public var approvedContentHash: String
    public init(approvedBy: String, approvedAt: Date, approvedContentHash: String) {
        self.approvedBy = approvedBy; self.approvedAt = approvedAt
        self.approvedContentHash = approvedContentHash
    }
}

/// One bounded next move for one Project. Not Project truth — a derived proposal.
public struct ProjectProposal: Codable, Sendable, Equatable, Identifiable {
    public var id: ProposalID
    public var projectId: ProjectID
    public var threadId: String
    public var createdFromTurnId: ManagerTurnID
    public var kind: ProposalKind
    public var status: ProposalStatus
    public var title: String
    public var whyNow: String
    public var userGoal: String
    public var currentTruth: [String]
    public var scope: String
    public var nonGoals: [String]
    public var likelyFilesOrAreas: [String]
    public var risks: [String]
    public var blockingQuestions: [String]
    public var suggestedLane: WorkLane?
    public var suggestedTeamId: String?
    /// Axis 1 (model reasoning level) where the source supports it — never team depth.
    public var suggestedEffort: EffortLevel?
    public var workOrderId: WorkOrderID?
    public var approval: ProjectApproval?
    public var baseGitHead: String?
    public var expiresWhen: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ProposalID,
        projectId: ProjectID,
        threadId: String,
        createdFromTurnId: ManagerTurnID,
        kind: ProposalKind,
        status: ProposalStatus = .proposed,
        title: String,
        whyNow: String = "",
        userGoal: String = "",
        currentTruth: [String] = [],
        scope: String = "",
        nonGoals: [String] = [],
        likelyFilesOrAreas: [String] = [],
        risks: [String] = [],
        blockingQuestions: [String] = [],
        suggestedLane: WorkLane? = nil,
        suggestedTeamId: String? = nil,
        suggestedEffort: EffortLevel? = nil,
        workOrderId: WorkOrderID? = nil,
        approval: ProjectApproval? = nil,
        baseGitHead: String? = nil,
        expiresWhen: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id; self.projectId = projectId; self.threadId = threadId
        self.createdFromTurnId = createdFromTurnId; self.kind = kind; self.status = status
        self.title = title; self.whyNow = whyNow; self.userGoal = userGoal
        self.currentTruth = currentTruth; self.scope = scope; self.nonGoals = nonGoals
        self.likelyFilesOrAreas = likelyFilesOrAreas; self.risks = risks
        self.blockingQuestions = blockingQuestions; self.suggestedLane = suggestedLane
        self.suggestedTeamId = suggestedTeamId; self.suggestedEffort = suggestedEffort
        self.workOrderId = workOrderId; self.approval = approval; self.baseGitHead = baseGitHead
        self.expiresWhen = expiresWhen; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// MARK: - Work order

/// The craft a work order routes to. `none` = lane-agnostic (e.g. docs/audit).
public enum WorkOrderLane: String, Codable, Sendable, CaseIterable {
    case code
    case design
    case copy
    case none
}

/// Reveal hands the exact prompt to the user; dispatch invokes a worker.
public enum WorkSendMode: String, Codable, Sendable, CaseIterable {
    case reveal
    case dispatch
}

/// The dispatchable payload derived from an approved Proposal.
public struct WorkOrder: Codable, Sendable, Equatable, Identifiable {
    public var id: WorkOrderID
    public var proposalId: ProposalID
    public var projectId: ProjectID
    public var title: String
    public var lane: WorkOrderLane
    public var mode: WorkSendMode
    public var targetWorkerId: String?
    public var targetAgent: String?
    public var promptBody: String
    public var scope: String
    public var nonGoals: [String]
    public var constraints: [String]
    public var expectedReturn: String
    public var proofCommands: [String]
    public var proofWaiver: String?
    public var baseGitHead: String?
    public var localRootPathSnapshot: String
    public var attachmentIds: [String]
    public var createdAt: Date

    public init(
        id: WorkOrderID,
        proposalId: ProposalID,
        projectId: ProjectID,
        title: String,
        lane: WorkOrderLane,
        mode: WorkSendMode,
        targetWorkerId: String? = nil,
        targetAgent: String? = nil,
        promptBody: String,
        scope: String = "",
        nonGoals: [String] = [],
        constraints: [String] = [],
        expectedReturn: String,
        proofCommands: [String] = [],
        proofWaiver: String? = nil,
        baseGitHead: String? = nil,
        localRootPathSnapshot: String,
        attachmentIds: [String] = [],
        createdAt: Date
    ) {
        self.id = id; self.proposalId = proposalId; self.projectId = projectId
        self.title = title; self.lane = lane; self.mode = mode
        self.targetWorkerId = targetWorkerId; self.targetAgent = targetAgent
        self.promptBody = promptBody; self.scope = scope; self.nonGoals = nonGoals
        self.constraints = constraints; self.expectedReturn = expectedReturn
        self.proofCommands = proofCommands; self.proofWaiver = proofWaiver
        self.baseGitHead = baseGitHead; self.localRootPathSnapshot = localRootPathSnapshot
        self.attachmentIds = attachmentIds; self.createdAt = createdAt
    }

    /// A work order must name proof: commands OR an explicit waiver, and an
    /// expected return. (Inference ban: no silent "done".)
    public var isDispatchReady: Bool {
        (!proofCommands.isEmpty || (proofWaiver?.isEmpty == false)) && !expectedReturn.isEmpty
    }
}

// MARK: - Return and verification

/// Worker output. A return is not proof by itself.
public enum WorkReturnStatus: String, Codable, Sendable, CaseIterable {
    case returned
    case failed
    case interrupted
    case cancelled
}

public struct WorkReturn: Codable, Sendable, Equatable, Identifiable {
    public var id: WorkReturnID
    public var projectId: ProjectID
    public var workOrderId: WorkOrderID
    public var runId: String?
    public var targetWorkerId: String?
    public var transcriptRef: String?
    public var summary: String?
    public var reportedFiles: [String]
    public var reportedProof: [String]
    public var status: WorkReturnStatus
    public var createdAt: Date

    public init(
        id: WorkReturnID,
        projectId: ProjectID,
        workOrderId: WorkOrderID,
        runId: String? = nil,
        targetWorkerId: String? = nil,
        transcriptRef: String? = nil,
        summary: String? = nil,
        reportedFiles: [String] = [],
        reportedProof: [String] = [],
        status: WorkReturnStatus,
        createdAt: Date
    ) {
        self.id = id; self.projectId = projectId; self.workOrderId = workOrderId
        self.runId = runId; self.targetWorkerId = targetWorkerId; self.transcriptRef = transcriptRef
        self.summary = summary; self.reportedFiles = reportedFiles; self.reportedProof = reportedProof
        self.status = status; self.createdAt = createdAt
    }
}

/// One proof command's observed result (bounded subprocess; see proof execution).
public struct ProofResult: Codable, Sendable, Equatable {
    public var command: String
    public var exitCode: Int?
    public var outputTail: String?
    public var durationSeconds: Double?
    public var timedOut: Bool
    public init(command: String, exitCode: Int? = nil, outputTail: String? = nil,
                durationSeconds: Double? = nil, timedOut: Bool = false) {
        self.command = command; self.exitCode = exitCode; self.outputTail = outputTail
        self.durationSeconds = durationSeconds; self.timedOut = timedOut
    }
    public var passed: Bool { !timedOut && exitCode == 0 }
}

/// Observed git state at verification time. `committed`/`dirty` are observed, never invented.
public struct GitObservation: Codable, Sendable, Equatable {
    public var head: String?
    public var committed: Bool
    public var dirty: Bool
    public init(head: String? = nil, committed: Bool = false, dirty: Bool = false) {
        self.head = head; self.committed = committed; self.dirty = dirty
    }
}

/// Verification of a return. "Done" requires `verified` or an explicit waiver.
public enum VerificationOutcome: String, Codable, Sendable, CaseIterable {
    case verified
    case notVerified
    case needsHuman
    case waived

    /// Only `verified` or `waived` advance work to done.
    public var isDone: Bool { self == .verified || self == .waived }
}

public struct VerificationRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: VerificationID
    public var projectId: ProjectID
    public var workOrderId: WorkOrderID
    public var returnId: WorkReturnID?
    public var outcome: VerificationOutcome
    public var proofResults: [ProofResult]
    public var gitObservation: GitObservation?
    public var scopeFindings: [String]
    public var docsDriftFindings: [String]
    public var missingProof: [String]
    public var recommendation: String
    public var createdAt: Date

    public init(
        id: VerificationID,
        projectId: ProjectID,
        workOrderId: WorkOrderID,
        returnId: WorkReturnID? = nil,
        outcome: VerificationOutcome,
        proofResults: [ProofResult] = [],
        gitObservation: GitObservation? = nil,
        scopeFindings: [String] = [],
        docsDriftFindings: [String] = [],
        missingProof: [String] = [],
        recommendation: String = "",
        createdAt: Date
    ) {
        self.id = id; self.projectId = projectId; self.workOrderId = workOrderId
        self.returnId = returnId; self.outcome = outcome; self.proofResults = proofResults
        self.gitObservation = gitObservation; self.scopeFindings = scopeFindings
        self.docsDriftFindings = docsDriftFindings; self.missingProof = missingProof
        self.recommendation = recommendation; self.createdAt = createdAt
    }

    /// Commit verification can only be claimed on a git repo with an observed,
    /// non-dirty committed head — never on a folder Project.
    public func claimsCommitVerification(project: Project) -> Bool {
        project.canClaimCommitVerification
            && outcome == .verified
            && (gitObservation?.committed ?? false)
    }
}
