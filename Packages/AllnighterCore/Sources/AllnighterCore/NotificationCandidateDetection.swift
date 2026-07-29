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

/// Lightweight run snapshot folded into the existing notification pipeline.
public struct RunNotificationSnapshot: Sendable, Equatable {
    public let runId: String
    public let threadId: String
    public let turnId: String
    public let threadTitle: String
    public let workerId: String?
    public let vendorDisplayName: String
    public let wakeAfter: Date?
    public let waitingForVendor: Bool

    public init(
        runId: String,
        threadId: String,
        turnId: String,
        threadTitle: String,
        workerId: String?,
        vendorDisplayName: String,
        wakeAfter: Date?,
        waitingForVendor: Bool
    ) {
        self.runId = runId
        self.threadId = threadId
        self.turnId = turnId
        self.threadTitle = threadTitle
        self.workerId = workerId
        self.vendorDisplayName = vendorDisplayName
        self.wakeAfter = wakeAfter
        self.waitingForVendor = waitingForVendor
    }
}

/// Relay stream stall snapshot for URN (CLP-S08).
public struct RelayStreamNotificationSnapshot: Sendable, Equatable {
    public let relayId: String
    public let threadTitle: String
    public let devWorkerId: String
    public let streamSilenceWarning: Bool

    public init(relayId: String, threadTitle: String, devWorkerId: String, streamSilenceWarning: Bool) {
        self.relayId = relayId
        self.threadTitle = threadTitle
        self.devWorkerId = devWorkerId
        self.streamSilenceWarning = streamSilenceWarning
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

    public static func runSnapshots(
        from threads: [WorkThread],
        runsById: [String: TeamRun],
        sourceDisplayNames: [String: String] = [:]
    ) -> [String: RunNotificationSnapshot] {
        var snapshots: [String: RunNotificationSnapshot] = [:]
        for thread in threads {
            for turn in thread.turns {
                guard let runId = turn.runId, let run = runsById[runId] else { continue }
                let sourceId = run.blocker?.capacityObservation?.source
                    ?? run.attempts.reversed().compactMap(\.capacityObservation?.source).first
                    ?? run.executionSourceId
                    ?? "vendor"
                let vendor = VendorContinuityPresentation.vendorDisplayName(
                    sourceId: sourceId,
                    sourceDisplayName: sourceDisplayNames[sourceId]
                )
                snapshots[runId] = RunNotificationSnapshot(
                    runId: runId,
                    threadId: thread.id,
                    turnId: turn.id,
                    threadTitle: thread.title,
                    workerId: turn.workerId ?? run.workers.first?.modelId,
                    vendorDisplayName: vendor,
                    wakeAfter: run.blocker?.wakeAfter,
                    waitingForVendor: run.status == .queued
                        && run.phase == .waitingForVendor
                        && run.blocker?.resource == .vendorBackoff
                )
            }
        }
        return snapshots
    }

    /// Emits park/recovery transitions into the same candidate stream as turn
    /// notifications. A nil `before` is a cold start and stays quiet.
    public static func runCandidates(
        before: [String: RunNotificationSnapshot]?,
        after: [String: RunNotificationSnapshot],
        now: Date
    ) -> [NotificationCandidate] {
        guard let before else { return [] }
        var candidates: [NotificationCandidate] = []
        for (runId, current) in after {
            let previous = before[runId]
            if current.waitingForVendor, previous?.waitingForVendor != true {
                candidates.append(NotificationCandidate(
                    threadId: current.threadId,
                    turnId: current.turnId,
                    event: .vendorParked,
                    threadTitle: current.threadTitle,
                    workerId: current.workerId,
                    runId: current.runId,
                    vendorDisplayName: current.vendorDisplayName,
                    wakeAfter: current.wakeAfter,
                    occurredAt: now
                ))
            } else if previous?.waitingForVendor == true, !current.waitingForVendor {
                candidates.append(NotificationCandidate(
                    threadId: current.threadId,
                    turnId: current.turnId,
                    event: .vendorResumed,
                    threadTitle: current.threadTitle,
                    workerId: current.workerId,
                    runId: current.runId,
                    vendorDisplayName: previous?.vendorDisplayName ?? current.vendorDisplayName,
                    occurredAt: now
                ))
            }
        }
        return candidates
    }

    /// CLP-S08: emit when a running relay's dev stream crosses the silence warning threshold.
    public static func relayStreamSnapshots(
        relays: [RelayState],
        runStore: RunStoreReading,
        threadTitles: [String: String],
        now: Date
    ) -> [String: RelayStreamNotificationSnapshot] {
        Dictionary(uniqueKeysWithValues: relays.compactMap { relay in
            guard relay.status == .running else { return nil }
            let last = StreamLiveness.relayStreamLastActivityAt(state: relay, runStore: runStore)
            let warning = StreamLiveness.streamSilenceWarning(lastActivityAt: last, now: now)
            let title = threadTitles[relay.id] ?? relay.docPath
            return (relay.id, RelayStreamNotificationSnapshot(
                relayId: relay.id,
                threadTitle: title,
                devWorkerId: relay.devWorkerId,
                streamSilenceWarning: warning
            ))
        })
    }

    public static func relayStreamCandidates(
        before: [String: RelayStreamNotificationSnapshot]?,
        after: [String: RelayStreamNotificationSnapshot],
        now: Date
    ) -> [NotificationCandidate] {
        guard let before else { return [] }
        var out: [NotificationCandidate] = []
        for (relayId, snap) in after where snap.streamSilenceWarning {
            if before[relayId]?.streamSilenceWarning == true { continue }
            out.append(NotificationCandidate(
                threadId: relayId,
                turnId: relayId,
                event: .relayStreamStalled,
                threadTitle: snap.threadTitle,
                workerId: snap.devWorkerId,
                occurredAt: now
            ))
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
        case .systemEvent:
            // `.relayStopped` is always created terminal (`RelayThreadProjector.syncStopped`
            // appends it `.done` directly, never `.running`), so it always lands here rather
            // than through `isOpenBlockingSystem`/`blockingSystemEvent`. Every other terminal
            // system event (a resolved manual-paste/sign-in/relay-escalation note) already got
            // its own notification when it opened; resolving it stays silent.
            return turn.systemEvent == .relayStopped ? .relayStopped : nil
        case .userMessage, .userDecision:
            return nil
        }
    }

    private static func blockingSystemEvent(_ turn: TurnNotificationSnapshot) -> NotificationEventKind? {
        switch turn.systemEvent {
        case .manualPaste:
            return .turnAwaitingManualPaste
        case .signInRequired:
            return .turnAuthRequired
        case .relayEscalated:
            return .relayNeedsAnswer
        case .relayStopped:
            return .relayStopped
        case .migrationImported, .waiting, .none:
            return nil
        }
    }

    private static func isOpenBlockingSystem(_ turn: TurnNotificationSnapshot) -> Bool {
        guard turn.kind == .systemEvent, turn.status == .running else { return false }
        switch turn.systemEvent {
        case .manualPaste, .signInRequired, .relayEscalated:
            return true
        // `.relayStopped` is never open/running (see `eventForCompletedTurn` above) — it
        // lands through the terminal-turn path, not this one.
        case .migrationImported, .waiting, .relayStopped, .none:
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
