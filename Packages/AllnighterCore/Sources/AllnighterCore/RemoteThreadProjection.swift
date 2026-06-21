import Foundation

/// Mac-derived read state for a remote thread payload. The cursor is source
/// truth; the unread fields are convenience values derived by the Mac.
public struct RemoteThreadReadState: Codable, Equatable, Sendable {
    public var readCursor: ThreadReadCursor?
    public var hasUnread: Bool
    public var unreadNeedsAttention: Bool
    public var firstUnreadTurnId: String?
    public var latestUnreadTurnId: String?

    public init(
        readCursor: ThreadReadCursor?,
        hasUnread: Bool,
        unreadNeedsAttention: Bool,
        firstUnreadTurnId: String?,
        latestUnreadTurnId: String?
    ) {
        self.readCursor = readCursor
        self.hasUnread = hasUnread
        self.unreadNeedsAttention = unreadNeedsAttention
        self.firstUnreadTurnId = firstUnreadTurnId
        self.latestUnreadTurnId = latestUnreadTurnId
    }
}

/// Content-light turn metadata for remote thread lists. It intentionally omits
/// text, reasoning, attachments, file refs, and local paths.
public struct RemoteThreadTurnLight: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: ThreadTurnKind
    public var status: ThreadTurnStatus
    public var author: TurnAuthor
    public var createdAt: Date
    public var completedAt: Date?
    public var workerId: String?
    public var runId: String?
    public var stageId: String?

    public init(
        id: String,
        kind: ThreadTurnKind,
        status: ThreadTurnStatus,
        author: TurnAuthor,
        createdAt: Date,
        completedAt: Date? = nil,
        workerId: String? = nil,
        runId: String? = nil,
        stageId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.author = author
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.workerId = workerId
        self.runId = runId
        self.stageId = stageId
    }
}

/// Content-light thread summary for the remote/iOS spine. Thread bodies are not
/// copied into this payload; detailed content must travel through a separately
/// trusted content path.
public struct RemoteThreadSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var status: ThreadStatus
    public var projectId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var pinnedAt: Date?
    public var displayState: ThreadDisplayState
    public var readState: RemoteThreadReadState
    public var turnCount: Int
    public var latestTurn: RemoteThreadTurnLight?

    public init(
        id: String,
        title: String,
        status: ThreadStatus,
        projectId: String?,
        createdAt: Date,
        updatedAt: Date,
        pinnedAt: Date?,
        displayState: ThreadDisplayState,
        readState: RemoteThreadReadState,
        turnCount: Int,
        latestTurn: RemoteThreadTurnLight?
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.displayState = displayState
        self.readState = readState
        self.turnCount = turnCount
        self.latestTurn = latestTurn
    }
}

public struct RemoteThreadSnapshotEnvelope: Codable, Equatable, Sendable {
    public var threads: [RemoteThreadSummary]
    public var protocolVersion: Int
    public var serverTime: Date

    public init(
        threads: [RemoteThreadSummary],
        protocolVersion: Int = RemoteProtocol.currentMajor,
        serverTime: Date
    ) {
        self.threads = threads
        self.protocolVersion = protocolVersion
        self.serverTime = serverTime
    }

    public func thread(id: String) -> RemoteThreadSummary? {
        threads.first { $0.id == id }
    }
}

public enum RemoteThreadProjection {
    public static func readState(from thread: WorkThread) -> RemoteThreadReadState {
        RemoteThreadReadState(
            readCursor: thread.readCursor,
            hasUnread: UnreadDerivation.hasUnread(thread: thread),
            unreadNeedsAttention: UnreadDerivation.unreadNeedsAttention(thread: thread),
            firstUnreadTurnId: UnreadDerivation.firstUnreadTurnId(thread: thread),
            latestUnreadTurnId: UnreadDerivation.latestUnreadTurnId(thread: thread)
        )
    }

    public static func turnLight(from turn: ThreadTurn) -> RemoteThreadTurnLight {
        RemoteThreadTurnLight(
            id: turn.id,
            kind: turn.kind,
            status: turn.status,
            author: turn.author,
            createdAt: turn.createdAt,
            completedAt: turn.completedAt,
            workerId: turn.workerId,
            runId: turn.runId,
            stageId: turn.stageId
        )
    }

    public static func summary(from thread: WorkThread, hasPendingItem: Bool = false) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: thread.id,
            title: thread.title,
            status: thread.status,
            projectId: thread.projectId,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            pinnedAt: thread.pinnedAt,
            displayState: ThreadStateDerivation.displayState(thread: thread, hasPendingItem: hasPendingItem),
            readState: readState(from: thread),
            turnCount: thread.turns.count,
            latestTurn: thread.turns.last.map(turnLight(from:))
        )
    }

    public static func summaries(
        from threads: [WorkThread],
        pendingThreadIds: Set<String> = []
    ) -> [RemoteThreadSummary] {
        threads.map { thread in
            summary(from: thread, hasPendingItem: pendingThreadIds.contains(thread.id))
        }
    }
}
