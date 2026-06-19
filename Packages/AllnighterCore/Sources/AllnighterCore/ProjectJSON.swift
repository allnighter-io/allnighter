import Foundation

/// `ProjectJSON` family — the public machine contract for the `alln project`
/// commands (docs/phases/Project_Spine_And_Project_Manager.md §CLI Contract,
/// PRJ-S07). Every envelope carries `schemaVersion`, `contractVersion`, and a
/// `projectId` where one applies, plus typed `nextActions` so an agent can chain
/// the next call without parsing prose. Dates serialize as ISO-8601 strings via
/// `CoreJSON` (the durable `Project`/`ProjectContextPacket` types are embedded
/// directly — they are the schema, no hand-mirrored copy to drift).

/// One project (full record) — used by `project add` / `project show`.
public struct ProjectJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var project: Project
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, project: Project, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.project = project; self.nextActions = nextActions
    }
}

/// The active/all project roster — used by `project list`.
public struct ProjectListJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projects: [Project]
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, projects: [Project], nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.projects = projects; self.nextActions = nextActions
    }
}

/// A compact thread row, scoped to one project — used by `project threads`.
public struct ProjectThreadSummary: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: String
    public var updatedAt: Date
    public var pinned: Bool
    public var unread: Bool
    public var unassigned: Bool
    public init(id: String, title: String, status: String, updatedAt: Date, pinned: Bool, unread: Bool, unassigned: Bool) {
        self.id = id; self.title = title; self.status = status; self.updatedAt = updatedAt
        self.pinned = pinned; self.unread = unread; self.unassigned = unassigned
    }
}

public struct ProjectThreadsJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projectId: String
    public var threads: [ProjectThreadSummary]
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, projectId: String, threads: [ProjectThreadSummary], nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.projectId = projectId; self.threads = threads; self.nextActions = nextActions
    }
}

/// A compact pending row, scoped to one project — used by `project pending`.
public struct ProjectPendingSummary: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: String
    public var needsAttention: Bool
    public init(id: String, title: String, status: String, needsAttention: Bool) {
        self.id = id; self.title = title; self.status = status; self.needsAttention = needsAttention
    }
}

public struct ProjectPendingJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projectId: String
    public var items: [ProjectPendingSummary]
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, projectId: String, items: [ProjectPendingSummary], nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.projectId = projectId; self.items = items; self.nextActions = nextActions
    }
}

/// Per-project worker readiness — used by `project workers` (cached) and
/// `project recheck-workers` (fresh probe). Only the canonical readiness facts;
/// never vendor trust/auth state. `cached` is true for the read path.
public struct ProjectWorkersJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projectId: String
    public var readinessSummary: String
    public var cached: Bool
    public var workers: [ProjectWorkerReadiness]
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, projectId: String, readinessSummary: String, cached: Bool, workers: [ProjectWorkerReadiness], nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.projectId = projectId; self.readinessSummary = readinessSummary
        self.cached = cached; self.workers = workers; self.nextActions = nextActions
    }
}

/// One Project Manager turn — used by `project chat`. The turn embeds its own
/// `mode` (answer/wait/…), `modelId`, and `nextActions`; a `wait` turn carries a
/// sourced readiness blocker in `warnings` and no `answerMarkdown` (never faked).
public struct ProjectManagerTurnJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var turn: ProjectManagerTurn
    public init(schemaVersion: Int = 1, contractVersion: String, turn: ProjectManagerTurn) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion; self.turn = turn
    }
}

/// The result of `project propose` — at most one bounded proposal plus the typed
/// turn that produced it. `proposal` is nil when the turn is a `wait`/blocker.
public struct ProjectProposalJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var proposal: ProjectProposal?
    public var turn: ProjectManagerTurn
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, proposal: ProjectProposal?, turn: ProjectManagerTurn, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.proposal = proposal; self.turn = turn; self.nextActions = nextActions
    }
}

/// The result of `project approve` — the now-approved proposal and the work order
/// it produced (still `reveal` mode; dispatch is a separate S11 action).
public struct ProjectWorkOrderJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var proposal: ProjectProposal
    public var workOrder: WorkOrder
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, proposal: ProjectProposal, workOrder: WorkOrder, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.proposal = proposal; self.workOrder = workOrder; self.nextActions = nextActions
    }
}

/// The result of `project handoff` — the exact prompt to hand a worker (reveal,
/// never invokes) plus a dispatch preview: whether the mutating gates WOULD pass
/// right now. Safe to call regardless of gate state.
public struct ProjectHandoffJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var workOrder: WorkOrder
    public var revealMarkdown: String
    public var resolvedSourceId: String?
    public var dispatchPreview: DispatchPreview
    public var nextActions: [ProjectNextAction]

    public struct DispatchPreview: Codable, Equatable, Sendable {
        public var wouldDispatch: Bool
        public var blockerCode: String?
        public var message: String?
        public var warnings: [String]
        public init(wouldDispatch: Bool, blockerCode: String? = nil, message: String? = nil, warnings: [String] = []) {
            self.wouldDispatch = wouldDispatch; self.blockerCode = blockerCode
            self.message = message; self.warnings = warnings
        }
    }

    public init(schemaVersion: Int = 1, contractVersion: String, workOrder: WorkOrder, revealMarkdown: String, resolvedSourceId: String?, dispatchPreview: DispatchPreview, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.workOrder = workOrder; self.revealMarkdown = revealMarkdown
        self.resolvedSourceId = resolvedSourceId; self.dispatchPreview = dispatchPreview
        self.nextActions = nextActions
    }
}

/// The result of `project dispatch` — the captured work return + the dispatched
/// order. A return is NOT proof; `project verify` (S12) decides done.
public struct ProjectDispatchJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var workReturn: WorkReturn
    public var workOrder: WorkOrder
    public var proposalStatus: String
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, workReturn: WorkReturn, workOrder: WorkOrder, proposalStatus: String, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.workReturn = workReturn; self.workOrder = workOrder
        self.proposalStatus = proposalStatus; self.nextActions = nextActions
    }
}

/// The result of `project verify` — the verification record and the resulting
/// proposal status. Only `verified`/`waived` advance the proposal to verified.
public struct ProjectVerificationJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var verification: VerificationRecord
    public var proposalStatus: String?
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, verification: VerificationRecord, proposalStatus: String?, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.verification = verification; self.proposalStatus = proposalStatus; self.nextActions = nextActions
    }
}

/// All proposals for a project — used by `project proposals`.
public struct ProjectProposalsJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var projectId: String
    public var proposals: [ProjectProposal]
    public init(schemaVersion: Int = 1, contractVersion: String, projectId: String, proposals: [ProjectProposal]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.projectId = projectId; self.proposals = proposals
    }
}

/// The on-demand context packet — used by `project context`. The packet is a
/// receipt, regenerated from current truth on every call (never durable truth).
public struct ProjectContextJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var packet: ProjectContextPacket
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, packet: ProjectContextPacket, nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.packet = packet; self.nextActions = nextActions
    }
}
