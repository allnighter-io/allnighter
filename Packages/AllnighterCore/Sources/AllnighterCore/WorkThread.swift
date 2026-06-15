import Foundation

/// One local thread for one goal: chat, panel, build, review, and keep going
/// without leaving Allnighter or re-explaining yourself.
///
/// A thread is an ordered list of `ThreadTurn`s. It owns chat turns directly;
/// heavy work (council/design/review/dispatch) is referenced by `runId` on a
/// turn — `CouncilRun` stays the run-truth owner (see `Persistent_Work_Threads`).
///
/// Liveness (running/needs-attention/last-worker/preview) is **derived** from
/// turns, never stored, so thread state cannot drift from turn truth.
public struct WorkThread: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Auto from the first user message; editable from the thread header.
    public var title: String
    public var status: ThreadStatus
    public var createdAt: Date
    public var updatedAt: Date
    /// Set when the thread is pinned to the top of the triage list.
    public var pinnedAt: Date?
    /// Context anchor and default dispatch cwd. Attached files resolve here.
    public var workingDir: String?
    public var projectLabel: String?
    /// Composer default worker, if the user has fixed one for this thread.
    public var defaultWorkerId: String?
    /// Append-only, in send order.
    public var turns: [ThreadTurn]

    public init(
        id: String,
        title: String,
        status: ThreadStatus = .active,
        createdAt: Date,
        updatedAt: Date,
        pinnedAt: Date? = nil,
        workingDir: String? = nil,
        projectLabel: String? = nil,
        defaultWorkerId: String? = nil,
        turns: [ThreadTurn] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.workingDir = workingDir
        self.projectLabel = projectLabel
        self.defaultWorkerId = defaultWorkerId
        self.turns = turns
    }
}

public enum ThreadStatus: String, Codable, Sendable, CaseIterable {
    case active
    case archived
}

// MARK: - Derived liveness (never stored; computed from turns)

public extension WorkThread {
    var isPinned: Bool { pinnedAt != nil }

    var isArchived: Bool { status == .archived }

    /// Any turn still queued or running.
    var isRunning: Bool {
        turns.contains { $0.status == .queued || $0.status == .running }
    }

    /// A failed/timed-out turn, or a system turn that blocks on the user
    /// (sign-in required, manual paste). Migration/waiting notes do not count.
    var needsAttention: Bool {
        turns.contains(where: \.requiresUserAttention)
    }

    /// The worker behind the most recent worker-authored turn.
    var lastWorkerId: String? {
        turns.last { $0.author == .worker }?.workerId
    }

    /// The most recent meaningful message/reply excerpt for the list row.
    var preview: String? {
        turns.last { $0.text?.isEmpty == false }?.text
    }

    /// One active heavy turn per thread in v1 (`council_run`, `dispatch`,
    /// `return_review`). While one is live, new heavy actions are disabled.
    var hasActiveHeavyTurn: Bool {
        turns.contains { $0.kind.isHeavy && ($0.status == .queued || $0.status == .running) }
    }

    func turn(id turnId: String) -> ThreadTurn? {
        turns.first { $0.id == turnId }
    }
}
