import Foundation

// MARK: - Project Spine contract (PRJ-S00)
//
// The durable Core models for Projects (repo binding + readiness), per
// `docs/phases/Unified_Run_Model.md`. Ceremony types (proposals, work orders,
// verification) are deleted — runs are `TeamRun` / RunRecord.
// (PRJ-S01), no engine (PRJ-S08+), no GUI. Public JSON projection (string dates,
// schemaVersion) lands with the CLI in PRJ-S07. Durable models use `Date` and the
// canonical `CoreJSON` (.iso8601) encoding like the rest of Core.

// MARK: Identifiers

public typealias ProjectID = String

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
        public init(activeRuns: [String] = [], pendingItems: [String] = []) {
            self.activeRuns = activeRuns; self.pendingItems = pendingItems
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

    /// Stable id so a receipt can reference this packet if persisted.
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

// MARK: - Project next actions

/// A typed next action (never prose-only).
public enum NextActionKind: String, Codable, Sendable, CaseIterable {
    case addProject
    case projectContext
    case listThreads
    case listPending
    case recheckWorkers
    case openProject
}

public struct ProjectNextAction: Codable, Sendable, Equatable {
    public var kind: NextActionKind
    public var label: String
    public var command: String?
    public init(kind: NextActionKind, label: String, command: String? = nil) {
        self.kind = kind; self.label = label; self.command = command
    }
}
