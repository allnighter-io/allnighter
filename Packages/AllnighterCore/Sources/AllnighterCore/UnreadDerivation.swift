import Foundation

/// Durable read position for a work thread. Stored inside `thread.json`; never
/// a sidecar file or GUI-local flag.
public struct ThreadReadCursor: Codable, Sendable, Equatable {
    /// Primary cursor: the last turn the user has read through.
    public var lastReadTurnId: String?
    /// Fallback boundary when `lastReadTurnId` is missing from the timeline.
    public var lastReadTurnCreatedAt: Date?
    /// When the cursor last advanced. Used for landed-after-read detection and
    /// future reconciliation — not for thread sorting.
    public var readAt: Date

    public init(lastReadTurnId: String? = nil, lastReadTurnCreatedAt: Date? = nil, readAt: Date) {
        self.lastReadTurnId = lastReadTurnId
        self.lastReadTurnCreatedAt = lastReadTurnCreatedAt
        self.readAt = readAt
    }

    /// Empty-timeline cursor for threads created after unread ships.
    public static func empty(at readAt: Date) -> ThreadReadCursor {
        ThreadReadCursor(lastReadTurnId: nil, lastReadTurnCreatedAt: nil, readAt: readAt)
    }
}

/// Pure unread derivation from `WorkThread` turn truth plus the durable read
/// cursor. One canonical algorithm — presenters format and sort only.
public enum UnreadDerivation {
    public static func unreadTurnIds(thread: WorkThread) -> [String] {
        guard let cursor = thread.readCursor else { return [] }
        // Resolve the cursor's turn index ONCE (was an O(turns) firstIndex per candidate
        // → O(turns^2) on long threads). PERF-S03: linear in turn count.
        let cursorIndex = cursorTurnIndex(thread: thread, cursor: cursor)
        return candidateTurns(thread: thread).compactMap { turn, index in
            isUnread(turn: turn, index: index, cursorIndex: cursorIndex, cursor: cursor) ? turn.id : nil
        }
    }

    public static func firstUnreadTurnId(thread: WorkThread) -> String? {
        unreadTurnIds(thread: thread).first
    }

    public static func latestUnreadTurnId(thread: WorkThread) -> String? {
        unreadTurnIds(thread: thread).last
    }

    public static func hasUnread(thread: WorkThread) -> Bool {
        !unreadTurnIds(thread: thread).isEmpty
    }

    public static func unreadNeedsAttention(thread: WorkThread) -> Bool {
        guard let cursor = thread.readCursor else { return false }
        let cursorIndex = cursorTurnIndex(thread: thread, cursor: cursor)
        return candidateTurns(thread: thread).contains { turn, index in
            isUnread(turn: turn, index: index, cursorIndex: cursorIndex, cursor: cursor)
                && turn.requiresUserAttention
        }
    }

    /// Whether a turn can create unread when it lands after the read cursor.
    public static func isUnreadEligible(_ turn: ThreadTurn) -> Bool {
        if isUserAuthored(turn) { return false }
        if turn.status == .cancelled { return false }
        switch turn.kind {
        case .userMessage, .userDecision:
            return false
        case .workerChat, .teamRun, .designBoard, .reviewBoard, .mutatingRun:
            switch turn.status {
            case .done, .failed, .timedOut:
                return true
            case .draft, .queued, .running, .cancelled:
                return false
            }
        case .systemEvent:
            switch turn.status {
            case .failed, .timedOut:
                return true
            case .running:
                switch turn.systemEvent {
                case .signInRequired, .manualPaste, .relayEscalated:
                    return true
                case .migrationImported, .waiting, .relayStopped, .none:
                    return false
                }
            case .draft, .queued, .done, .cancelled:
                return false
            }
        }
    }

    // MARK: - Private

    private static func candidateTurns(thread: WorkThread) -> [(ThreadTurn, Int)] {
        let supersededIds = Set(thread.turns.compactMap(\.supersedesTurnId))
        return thread.turns.enumerated().compactMap { index, turn in
            if isUserAuthored(turn) { return nil }
            if turn.status == .cancelled { return nil }
            if supersededIds.contains(turn.id) { return nil }
            return (turn, index)
        }
    }

    private static func isUserAuthored(_ turn: ThreadTurn) -> Bool {
        turn.author == .user || turn.kind == .userMessage || turn.kind == .userDecision
    }

    /// The index of the cursor's last-read turn, resolved once per derivation. `nil` when
    /// there's no id cursor or it isn't present (callers then fall back to the timestamp).
    private static func cursorTurnIndex(thread: WorkThread, cursor: ThreadReadCursor) -> Int? {
        guard let cursorId = cursor.lastReadTurnId else { return nil }
        return thread.turns.firstIndex { $0.id == cursorId }
    }

    private static func isUnread(
        turn: ThreadTurn,
        index: Int,
        cursorIndex: Int?,
        cursor: ThreadReadCursor
    ) -> Bool {
        guard isUnreadEligible(turn) else { return false }
        let afterCursor = isAfterCursor(turn: turn, index: index, cursorIndex: cursorIndex, cursor: cursor)
        let landedAfterRead = landedAfterRead(turn: turn, cursor: cursor)
        return afterCursor || landedAfterRead
    }

    private static func isAfterCursor(
        turn: ThreadTurn,
        index: Int,
        cursorIndex: Int?,
        cursor: ThreadReadCursor
    ) -> Bool {
        if let cursorIndex {
            return index > cursorIndex
        }
        if let cursorTimestamp = cursor.lastReadTurnCreatedAt {
            return turn.createdAt > cursorTimestamp
        }
        return false
    }

    private static func landedAfterRead(turn: ThreadTurn, cursor: ThreadReadCursor) -> Bool {
        let landedAt = turn.completedAt ?? turn.createdAt
        return landedAt > cursor.readAt
    }
}

public extension WorkThread {
    var hasUnread: Bool { UnreadDerivation.hasUnread(thread: self) }
    var unreadNeedsAttention: Bool { UnreadDerivation.unreadNeedsAttention(thread: self) }
    var firstUnreadTurnId: String? { UnreadDerivation.firstUnreadTurnId(thread: self) }
    var latestUnreadTurnId: String? { UnreadDerivation.latestUnreadTurnId(thread: self) }
}
