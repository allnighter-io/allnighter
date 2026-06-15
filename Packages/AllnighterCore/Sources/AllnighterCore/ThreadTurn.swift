import Foundation

/// One entry in a `WorkThread` timeline: a user message, a one-worker reply, a
/// rich council/build turn that references a `CouncilRun`, or a system note.
///
/// Heavy turns never copy run data — they point at `CouncilRun` via `runId`
/// (and `stageId` for a specific stage). Chat turns own their `text` directly.
public struct ThreadTurn: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    /// Granular storage kind (see `kind.family` for the simple UI grouping).
    public var kind: ThreadTurnKind
    public var status: ThreadTurnStatus
    public var createdAt: Date
    public var completedAt: Date?
    public var author: TurnAuthor
    /// Chat text, user message, or system note. Nil for pure reference turns.
    public var text: String?
    /// The worker that authored (or is running) this turn, when applicable.
    public var workerId: String?
    /// References a `CouncilRun` for council/design/review/dispatch turns.
    public var runId: String?
    /// A specific `StageOutput` within the referenced run, when applicable.
    public var stageId: String?
    public var artifactRefs: [ArtifactRef]
    /// The context packet the worker was given for this turn.
    public var contextPacketId: String?
    /// An edited/re-run turn that replaces an earlier one in the timeline.
    public var supersedesTurnId: String?
    /// "Continue from this": the turn whose result seeded this one.
    public var seedFromTurnId: String?
    /// Only meaningful for `.system_event` turns: what kind of note this is, so
    /// liveness can tell a blocking note (sign-in/manual-paste) from a benign
    /// one (migration/waiting) without storing a drift-prone attention flag.
    public var systemEvent: SystemEventKind?

    public init(
        id: String,
        threadId: String,
        kind: ThreadTurnKind,
        status: ThreadTurnStatus,
        createdAt: Date,
        completedAt: Date? = nil,
        author: TurnAuthor,
        text: String? = nil,
        workerId: String? = nil,
        runId: String? = nil,
        stageId: String? = nil,
        artifactRefs: [ArtifactRef] = [],
        contextPacketId: String? = nil,
        supersedesTurnId: String? = nil,
        seedFromTurnId: String? = nil,
        systemEvent: SystemEventKind? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.author = author
        self.text = text
        self.workerId = workerId
        self.runId = runId
        self.stageId = stageId
        self.artifactRefs = artifactRefs
        self.contextPacketId = contextPacketId
        self.supersedesTurnId = supersedesTurnId
        self.seedFromTurnId = seedFromTurnId
        self.systemEvent = systemEvent
    }
}

// MARK: - Storage kinds and UI families

/// Granular storage kinds. The UI groups these into `TurnFamily`.
public enum ThreadTurnKind: String, Codable, Sendable, CaseIterable {
    // Message family
    case userMessage = "user_message"
    case userDecision = "user_decision"
    // Reply family
    case workerChat = "worker_chat"
    // Council family
    case councilRun = "council_run"
    case designBoard = "design_board"
    case reviewBoard = "review_board"
    // Build family
    case workOrder = "work_order"
    case dispatch
    case returnReview = "return_review"
    // System family
    case systemEvent = "system_event"
}

/// The simple grouping the timeline renders by.
public enum TurnFamily: String, Codable, Sendable, CaseIterable {
    case message
    case reply
    case council
    case build
    case system
}

public extension ThreadTurnKind {
    var family: TurnFamily {
        switch self {
        case .userMessage, .userDecision:
            return .message
        case .workerChat:
            return .reply
        case .councilRun, .designBoard, .reviewBoard:
            return .council
        case .workOrder, .dispatch, .returnReview:
            return .build
        case .systemEvent:
            return .system
        }
    }

    /// Heavy turns are the long-running run/build kinds. Only one may be active
    /// per thread in v1 (`council_run`, `dispatch`, `return_review`).
    var isHeavy: Bool {
        switch self {
        case .councilRun, .designBoard, .reviewBoard, .dispatch, .returnReview:
            return true
        case .userMessage, .userDecision, .workerChat, .workOrder, .systemEvent:
            return false
        }
    }

    /// A heavy turn that references a `CouncilRun` for its truth.
    var referencesRun: Bool {
        switch self {
        case .councilRun, .designBoard, .reviewBoard, .dispatch, .returnReview:
            return true
        case .userMessage, .userDecision, .workerChat, .workOrder, .systemEvent:
            return false
        }
    }
}

/// Lifecycle of a single turn. `draft` is a composed-but-unsent work order or
/// message; the heavy run/build status lives on the referenced `CouncilRun`.
public enum ThreadTurnStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case queued
    case running
    case done
    case failed
    case timedOut = "timed_out"
    case cancelled
}

public enum TurnAuthor: String, Codable, Sendable, CaseIterable {
    case user
    case worker
    case system
}

/// Sub-kind for `.system_event` turns. Sign-in/manual-paste block on the user
/// and surface as needs-attention; migration/waiting are benign notes.
public enum SystemEventKind: String, Codable, Sendable, CaseIterable {
    case migrationImported = "migration_imported"
    case waiting
    case signInRequired = "sign_in_required"
    case manualPaste = "manual_paste"
}

// MARK: - Turn state machine

public extension ThreadTurnStatus {
    var isTerminal: Bool {
        switch self {
        case .done, .failed, .timedOut, .cancelled:
            return true
        case .draft, .queued, .running:
            return false
        }
    }

    /// Legal next states. A `draft` (e.g. an editable work order) may be sent or
    /// abandoned; a `running` turn settles to a terminal state.
    func allowedTransitions() -> Set<ThreadTurnStatus> {
        switch self {
        case .draft:
            return [.queued, .running, .cancelled]
        case .queued:
            return [.running, .cancelled, .failed]
        case .running:
            return [.done, .failed, .timedOut, .cancelled]
        case .done, .failed, .timedOut, .cancelled:
            return []
        }
    }
}

public extension ThreadTurn {
    var family: TurnFamily { kind.family }

    func canTransition(to next: ThreadTurnStatus) -> Bool {
        status.allowedTransitions().contains(next)
    }

    /// True when this turn should pull the thread into needs-attention triage:
    /// a failed/timed-out turn, or a system note that blocks on the user.
    var requiresUserAttention: Bool {
        switch status {
        case .failed, .timedOut:
            return true
        case .draft, .queued, .running, .done, .cancelled:
            break
        }
        if kind == .systemEvent {
            switch systemEvent {
            case .signInRequired, .manualPaste:
                return true
            case .migrationImported, .waiting, .none:
                return false
            }
        }
        return false
    }
}
