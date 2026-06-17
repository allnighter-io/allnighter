import Foundation

/// One local thread for one goal: chat, panel, build, review, and keep going
/// without leaving Allnighter or re-explaining yourself.
///
/// A thread is an ordered list of `ThreadTurn`s. It owns chat turns directly;
/// heavy work (team/design/review/dispatch) is referenced by `runId` on a
/// turn — `TeamRun` stays the run-truth owner (see `Persistent_Work_Threads`).
///
/// Liveness (running/needs-attention/last-worker/preview) is **derived** from
/// turns, never stored, so thread state cannot drift from turn truth.
public struct WorkThread: Codable, Sendable, Equatable, Identifiable {
    /// Schema version for on-disk `thread.json`. Current writers emit `1`.
    /// Legacy files without this field decode as `0`.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
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
    /// Durable read position. `nil` means legacy/no-baseline until the store
    /// seeds a baseline on the next feature-aware append/update.
    public var readCursor: ThreadReadCursor?

    public init(
        id: String,
        title: String,
        status: ThreadStatus = .active,
        createdAt: Date,
        updatedAt: Date,
        formatVersion: Int = WorkThread.currentFormatVersion,
        pinnedAt: Date? = nil,
        workingDir: String? = nil,
        projectLabel: String? = nil,
        defaultWorkerId: String? = nil,
        readCursor: ThreadReadCursor? = nil,
        turns: [ThreadTurn] = []
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.workingDir = workingDir
        self.projectLabel = projectLabel
        self.defaultWorkerId = defaultWorkerId
        self.readCursor = readCursor
        self.turns = turns
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, title, status, createdAt, updatedAt, pinnedAt,
             workingDir, projectLabel, defaultWorkerId, readCursor, turns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(ThreadStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        workingDir = try container.decodeIfPresent(String.self, forKey: .workingDir)
        projectLabel = try container.decodeIfPresent(String.self, forKey: .projectLabel)
        defaultWorkerId = try container.decodeIfPresent(String.self, forKey: .defaultWorkerId)
        readCursor = try container.decodeIfPresent(ThreadReadCursor.self, forKey: .readCursor)
        turns = try container.decode([ThreadTurn].self, forKey: .turns)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encodeIfPresent(workingDir, forKey: .workingDir)
        try container.encodeIfPresent(projectLabel, forKey: .projectLabel)
        try container.encodeIfPresent(defaultWorkerId, forKey: .defaultWorkerId)
        try container.encodeIfPresent(readCursor, forKey: .readCursor)
        try container.encode(turns, forKey: .turns)
    }
}

public enum ThreadStatus: String, Codable, Sendable, CaseIterable {
    case active
    case archived
}

// MARK: - Derived liveness (never stored; computed from turns)

public extension WorkThread {
    /// Upgrades legacy v0 threads to the current on-disk schema before write.
    mutating func upgradeFormatVersionIfNeeded() {
        if formatVersion < Self.currentFormatVersion {
            formatVersion = Self.currentFormatVersion
        }
    }

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

    /// One active heavy turn per thread in v1 (`team_run`, `dispatch`,
    /// `return_review`). While one is live, new heavy actions are disabled.
    var hasActiveHeavyTurn: Bool {
        turns.contains { $0.kind.isHeavy && ($0.status == .queued || $0.status == .running) }
    }

    func turn(id turnId: String) -> ThreadTurn? {
        turns.first { $0.id == turnId }
    }
}
