import Foundation

/// Lightweight thread snapshot for notification transition detection.
public struct ThreadNotificationSnapshot: Sendable, Equatable {
    public let threadId: String
    public let title: String
    public let needsAttention: Bool
    public let turns: [TurnNotificationSnapshot]

    public init(threadId: String, title: String, needsAttention: Bool, turns: [TurnNotificationSnapshot]) {
        self.threadId = threadId
        self.title = title
        self.needsAttention = needsAttention
        self.turns = turns
    }
}

public struct TurnNotificationSnapshot: Sendable, Equatable {
    public let id: String
    public let kind: ThreadTurnKind
    public let status: ThreadTurnStatus
    public let workerId: String?
    public let systemEvent: SystemEventKind?

    public init(
        id: String,
        kind: ThreadTurnKind,
        status: ThreadTurnStatus,
        workerId: String?,
        systemEvent: SystemEventKind?
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.workerId = workerId
        self.systemEvent = systemEvent
    }
}

/// Pure detection of notification candidates from thread state diffs (NOTIF-S02).
public enum NotificationCandidateDetection {
    public static func snapshots(from threads: [WorkThread]) -> [String: ThreadNotificationSnapshot] {
        Dictionary(uniqueKeysWithValues: threads.map { thread in
            (thread.id, snapshot(from: thread))
        })
    }

    public static func snapshot(from thread: WorkThread) -> ThreadNotificationSnapshot {
        ThreadNotificationSnapshot(
            threadId: thread.id,
            title: thread.title,
            needsAttention: thread.needsAttention,
            turns: thread.turns.map { turn in
                TurnNotificationSnapshot(
                    id: turn.id,
                    kind: turn.kind,
                    status: turn.status,
                    workerId: turn.workerId,
                    systemEvent: turn.systemEvent
                )
            }
        )
    }

    /// Emits candidates only when `before` is non-nil (no cold-start / relaunch noise).
    public static func candidates(
        before: [String: ThreadNotificationSnapshot]?,
        after: [String: ThreadNotificationSnapshot],
        now: Date
    ) -> [NotificationCandidate] {
        guard let before else { return [] }
        var out: [NotificationCandidate] = []
        for (_, afterSnap) in after {
            let beforeSnap = before[afterSnap.threadId]
            out.append(contentsOf: turnCandidates(before: beforeSnap, after: afterSnap, now: now))
            if let beforeSnap,
               !beforeSnap.needsAttention,
               afterSnap.needsAttention {
                if let turnId = attentionTurnId(in: afterSnap) {
                    out.append(NotificationCandidate(
                        threadId: afterSnap.threadId,
                        turnId: turnId,
                        event: .threadNeedsAttention,
                        threadTitle: afterSnap.title,
                        workerId: afterSnap.turns.first { $0.id == turnId }?.workerId,
                        occurredAt: now
                    ))
                }
            }
        }
        return out
    }

    private static func turnCandidates(
        before: ThreadNotificationSnapshot?,
        after: ThreadNotificationSnapshot,
        now: Date
    ) -> [NotificationCandidate] {
        guard let before else { return [] }
        var out: [NotificationCandidate] = []
        let beforeById = Dictionary(uniqueKeysWithValues: before.turns.map { ($0.id, $0) })
        for turn in after.turns {
            let prev = beforeById[turn.id]
            if let prev {
                if prev.status == turn.status { continue }
                if let event = eventForTransition(from: prev, to: turn) {
                    out.append(NotificationCandidate(
                        threadId: after.threadId,
                        turnId: turn.id,
                        event: event,
                        threadTitle: after.title,
                        workerId: turn.workerId,
                        occurredAt: now
                    ))
                }
            } else if turn.status.isTerminal || isOpenBlockingSystem(turn) {
                if let event = eventForLandedTurn(turn) {
                    out.append(NotificationCandidate(
                        threadId: after.threadId,
                        turnId: turn.id,
                        event: event,
                        threadTitle: after.title,
                        workerId: turn.workerId,
                        occurredAt: now
                    ))
                }
            }
        }
        return out
    }

    private static func eventForTransition(
        from previous: TurnNotificationSnapshot,
        to current: TurnNotificationSnapshot
    ) -> NotificationEventKind? {
        switch current.status {
        case .done:
            return eventForCompletedTurn(current)
        case .failed:
            return .turnFailed
        case .timedOut:
            return .turnTimedOut
        case .running:
            if isOpenBlockingSystem(current), !isOpenBlockingSystem(previous) {
                return blockingSystemEvent(current)
            }
            return nil
        case .draft, .queued, .cancelled:
            return nil
        }
    }

    private static func eventForLandedTurn(_ turn: TurnNotificationSnapshot) -> NotificationEventKind? {
        if isOpenBlockingSystem(turn) { return blockingSystemEvent(turn) }
        switch turn.status {
        case .done:
            return eventForCompletedTurn(turn)
        case .failed:
            return .turnFailed
        case .timedOut:
            return .turnTimedOut
        case .draft, .queued, .running, .cancelled:
            return nil
        }
    }

    private static func eventForCompletedTurn(_ turn: TurnNotificationSnapshot) -> NotificationEventKind? {
        switch turn.kind {
        case .workerChat:
            return .turnCompleted
        case .teamRun, .designBoard, .reviewBoard, .mutatingRun:
            return .teamRunCompleted
        case .userMessage, .userDecision, .systemEvent:
            return nil
        }
    }

    private static func blockingSystemEvent(_ turn: TurnNotificationSnapshot) -> NotificationEventKind? {
        switch turn.systemEvent {
        case .manualPaste:
            return .turnAwaitingManualPaste
        case .signInRequired:
            return .turnAuthRequired
        // `relayEscalated` blocks (see `isOpenBlockingSystem`/`ThreadTurn.requiresUserAttention`)
        // and still raises the thread-level `.threadNeedsAttention` notification via
        // `candidates()`'s generic needsAttention transition — a per-event specific push
        // ("PM Relay needs an answer") is GUI polish deferred to PM_Relay.md R-S08.
        case .migrationImported, .waiting, .relayEscalated, .relayStopped, .none:
            return nil
        }
    }

    private static func isOpenBlockingSystem(_ turn: TurnNotificationSnapshot) -> Bool {
        guard turn.kind == .systemEvent, turn.status == .running else { return false }
        switch turn.systemEvent {
        case .manualPaste, .signInRequired:
            return true
        // Deliberately excluded here (see `blockingSystemEvent` above) — the thread-level
        // needsAttention notification still fires via `ThreadTurn.requiresUserAttention`.
        case .migrationImported, .waiting, .relayEscalated, .relayStopped, .none:
            return false
        }
    }

    private static func attentionTurnId(in snapshot: ThreadNotificationSnapshot) -> String? {
        snapshot.turns.last { turn in
            switch turn.status {
            case .failed, .timedOut:
                return true
            case .running:
                switch turn.systemEvent {
                case .signInRequired, .manualPaste:
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }?.id
    }
}
