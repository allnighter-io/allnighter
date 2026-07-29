import Foundation

/// One entry in a `WorkThread` timeline: a user message, a one-worker reply, a
/// rich team/mutating-run turn that references a `TeamRun`, or a system note.
///
/// Heavy turns never copy run data — they point at `TeamRun` via `runId`
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
    /// The model that authored (or is running) this turn, when applicable.
    public var modelId: String?
    /// References a `TeamRun` for team/design/review/mutating-run turns.
    public var runId: String?
    /// A specific `StageOutput` within the referenced run, when applicable.
    public var stageId: String?
    public var artifactRefs: [ArtifactRef]
    /// Ordered chat image refs (join → `attachments.json` → canonical bytes).
    public var attachmentRefs: [TurnAttachmentRef]
    /// Ordered file refs selected by the user for this turn.
    public var fileReferenceRefs: [TurnFileReferenceRef]
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
    /// Set on a streaming worker turn whose live partial text exceeded the visible
    /// cap (03_Mac_Streaming §Thread Storage): `text` then holds only the newest
    /// visible suffix until the complete final answer replaces it at settlement.
    /// Additive; absent/false on every existing turn.
    public var partialOutputTruncated: Bool
    /// Live streamed REASONING / thinking shown in a separate surface while the
    /// worker runs (kept out of `text`/the answer). Additive; absent on every
    /// existing turn. Local-only, same sensitivity as the answer.
    public var reasoningText: String?

    public init(
        id: String,
        threadId: String,
        kind: ThreadTurnKind,
        status: ThreadTurnStatus,
        createdAt: Date,
        completedAt: Date? = nil,
        author: TurnAuthor,
        text: String? = nil,
        modelId: String? = nil,
        runId: String? = nil,
        stageId: String? = nil,
        artifactRefs: [ArtifactRef] = [],
        attachmentRefs: [TurnAttachmentRef] = [],
        fileReferenceRefs: [TurnFileReferenceRef] = [],
        contextPacketId: String? = nil,
        supersedesTurnId: String? = nil,
        seedFromTurnId: String? = nil,
        systemEvent: SystemEventKind? = nil,
        partialOutputTruncated: Bool = false,
        reasoningText: String? = nil
    ) {
        self.partialOutputTruncated = partialOutputTruncated
        self.reasoningText = reasoningText
        self.id = id
        self.threadId = threadId
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.author = author
        self.text = text
        self.modelId = modelId
        self.runId = runId
        self.stageId = stageId
        self.artifactRefs = artifactRefs
        self.attachmentRefs = attachmentRefs
        self.fileReferenceRefs = fileReferenceRefs
        self.contextPacketId = contextPacketId
        self.supersedesTurnId = supersedesTurnId
        self.seedFromTurnId = seedFromTurnId
        self.systemEvent = systemEvent
    }

    private enum CodingKeys: String, CodingKey {
        case id, threadId, kind, status, createdAt, completedAt, author, text,
             modelId, runId, stageId, artifactRefs, attachmentRefs, fileReferenceRefs,
             contextPacketId, supersedesTurnId, seedFromTurnId, systemEvent,
             partialOutputTruncated, reasoningText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        threadId = try c.decode(String.self, forKey: .threadId)
        kind = try c.decode(ThreadTurnKind.self, forKey: .kind)
        status = try c.decode(ThreadTurnStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        author = try c.decode(TurnAuthor.self, forKey: .author)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
        runId = try c.decodeIfPresent(String.self, forKey: .runId)
        stageId = try c.decodeIfPresent(String.self, forKey: .stageId)
        artifactRefs = try c.decodeIfPresent([ArtifactRef].self, forKey: .artifactRefs) ?? []
        attachmentRefs = try c.decodeIfPresent([TurnAttachmentRef].self, forKey: .attachmentRefs) ?? []
        fileReferenceRefs = try c.decodeIfPresent([TurnFileReferenceRef].self, forKey: .fileReferenceRefs) ?? []
        contextPacketId = try c.decodeIfPresent(String.self, forKey: .contextPacketId)
        supersedesTurnId = try c.decodeIfPresent(String.self, forKey: .supersedesTurnId)
        seedFromTurnId = try c.decodeIfPresent(String.self, forKey: .seedFromTurnId)
        systemEvent = try c.decodeIfPresent(SystemEventKind.self, forKey: .systemEvent)
        partialOutputTruncated = try c.decodeIfPresent(Bool.self, forKey: .partialOutputTruncated) ?? false
        reasoningText = try c.decodeIfPresent(String.self, forKey: .reasoningText)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadId, forKey: .threadId)
        try c.encode(kind, forKey: .kind)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(author, forKey: .author)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(modelId, forKey: .modelId)
        try c.encodeIfPresent(runId, forKey: .runId)
        try c.encodeIfPresent(stageId, forKey: .stageId)
        try c.encode(artifactRefs, forKey: .artifactRefs)
        try c.encode(attachmentRefs, forKey: .attachmentRefs)
        try c.encode(fileReferenceRefs, forKey: .fileReferenceRefs)
        try c.encodeIfPresent(contextPacketId, forKey: .contextPacketId)
        try c.encodeIfPresent(supersedesTurnId, forKey: .supersedesTurnId)
        try c.encodeIfPresent(seedFromTurnId, forKey: .seedFromTurnId)
        try c.encodeIfPresent(systemEvent, forKey: .systemEvent)
        // Encode only when set so every existing turn's JSON stays byte-identical.
        if partialOutputTruncated { try c.encode(true, forKey: .partialOutputTruncated) }
        try c.encodeIfPresent(reasoningText, forKey: .reasoningText)
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
    // Team-run family
    case teamRun = "team_run"
    case designBoard = "design_board"
    case reviewBoard = "review_board"
    case mutatingRun = "mutating_run"
    // System family
    case systemEvent = "system_event"
}

/// The simple grouping the timeline renders by.
public enum TurnFamily: String, Codable, Sendable, CaseIterable {
    case message
    case reply
    case team
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
        case .teamRun, .designBoard, .reviewBoard, .mutatingRun:
            return .team
        case .systemEvent:
            return .system
        }
    }

    /// Heavy turns are the long-running run/build kinds. Only one may be active
    /// per thread in v1 (`team_run`, `design_board`, `review_board`, `mutating_run`).
    var isHeavy: Bool {
        switch self {
        case .teamRun, .designBoard, .reviewBoard, .mutatingRun:
            return true
        case .userMessage, .userDecision, .workerChat, .systemEvent:
            return false
        }
    }

    /// A heavy turn that references a `TeamRun` for its truth.
    var referencesRun: Bool {
        switch self {
        case .teamRun, .designBoard, .reviewBoard, .mutatingRun:
            return true
        case .userMessage, .userDecision, .workerChat, .systemEvent:
            return false
        }
    }
}

/// Lifecycle of a single turn. `draft` is a composed-but-unsent message; the
/// heavy run status lives on the referenced `TeamRun`.
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
    /// A PM Relay round escalated — the founder must answer a real question before
    /// the relay can continue (`docs/phases/PM_Relay.md` §4.1). Blocks like
    /// `signInRequired`/`manualPaste`; clears when `RelayCoordinator.resume` runs
    /// (R-S07 `RelayThreadProjector`).
    case relayEscalated = "relay_escalated"
    /// A PM Relay hit a hard ceiling (`--max-rounds`/`--until`/stagnation) and
    /// stopped. Informational only — never resumable, so never blocking.
    case relayStopped = "relay_stopped"
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

    /// Legal next states. A `draft` (e.g. an editable reply) may be sent or
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
    /// a failed/timed-out turn, or a blocking system note that is still open.
    /// A blocking note (sign-in / manual-paste) is created `running` and
    /// transitioned to a terminal state once resolved, so attention clears.
    var requiresUserAttention: Bool {
        switch status {
        case .failed, .timedOut:
            return true
        case .draft, .queued, .running, .done, .cancelled:
            break
        }
        if kind == .systemEvent {
            switch systemEvent {
            case .signInRequired, .manualPaste, .relayEscalated:
                return !status.isTerminal   // open and blocking
            case .migrationImported, .waiting, .relayStopped, .none:
                return false
            }
        }
        return false
    }
}
