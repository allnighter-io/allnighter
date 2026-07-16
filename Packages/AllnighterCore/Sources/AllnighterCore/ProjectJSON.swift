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
    /// The 4-state row treatment (draft/pending/running/replied/idle) — derived once in
    /// Core so the GUI rows + the Pending section don't compute it.
    public var displayState: String
    /// True when the thread has an armed Pending item (drives the Pending section).
    public var pending: Bool
    /// Failed/blocked — an independent attention overlay, not part of displayState.
    public var needsAttention: Bool
    public init(id: String, title: String, status: String, updatedAt: Date, pinned: Bool, unread: Bool,
                unassigned: Bool, displayState: String, pending: Bool, needsAttention: Bool) {
        self.id = id; self.title = title; self.status = status; self.updatedAt = updatedAt
        self.pinned = pinned; self.unread = unread; self.unassigned = unassigned
        self.displayState = displayState; self.pending = pending; self.needsAttention = needsAttention
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
    public var workers: [ProjectWorkerReadinessProjector.Row]
    public var nextActions: [ProjectNextAction]
    public init(schemaVersion: Int = 1, contractVersion: String, projectId: String, readinessSummary: String, cached: Bool, workers: [ProjectWorkerReadinessProjector.Row], nextActions: [ProjectNextAction] = []) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.projectId = projectId; self.readinessSummary = readinessSummary
        self.cached = cached; self.workers = workers; self.nextActions = nextActions
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
