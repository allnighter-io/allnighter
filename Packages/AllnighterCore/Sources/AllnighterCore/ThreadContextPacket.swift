import Foundation

/// The exact context a worker was given for one turn — captured as truth so the
/// user can always see "what the worker will see" before manual-paste, panel,
/// and dispatch. This is product trust, not a debug drawer.
///
/// The packet records which turns/runs/files were included and whether the body
/// was truncated, but never an estimated token count (no usage theater).
public struct ThreadContextPacket: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    /// The turn this packet was assembled for.
    public var turnId: String
    public var createdAt: Date
    public var strategy: ContextStrategy
    public var includedTurnIds: [String]
    public var includedRunIds: [String]
    public var includedFiles: [String]
    /// The rendered context body handed to the worker.
    public var text: String
    public var truncated: Bool
    /// Human-readable note, e.g. "included last 8 turns; older omitted."
    public var truncationNote: String?
    /// Audit record of attachments delivered to the worker for this turn.
    public var includedAttachments: [IncludedAttachmentDelivery]
    /// Audit record of referenced files whose text was delivered in this packet.
    public var includedFileReferences: [IncludedFileReferenceDelivery]

    public init(
        id: String,
        threadId: String,
        turnId: String,
        createdAt: Date,
        strategy: ContextStrategy,
        includedTurnIds: [String] = [],
        includedRunIds: [String] = [],
        includedFiles: [String] = [],
        text: String,
        truncated: Bool = false,
        truncationNote: String? = nil,
        includedAttachments: [IncludedAttachmentDelivery] = [],
        includedFileReferences: [IncludedFileReferenceDelivery] = []
    ) {
        self.id = id
        self.threadId = threadId
        self.turnId = turnId
        self.createdAt = createdAt
        self.strategy = strategy
        self.includedTurnIds = includedTurnIds
        self.includedRunIds = includedRunIds
        self.includedFiles = includedFiles
        self.text = text
        self.truncated = truncated
        self.truncationNote = truncationNote
        self.includedAttachments = includedAttachments
        self.includedFileReferences = includedFileReferences
    }

    private enum CodingKeys: String, CodingKey {
        case id, threadId, turnId, createdAt, strategy, includedTurnIds, includedRunIds,
             includedFiles, text, truncated, truncationNote, includedAttachments, includedFileReferences
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        threadId = try c.decode(String.self, forKey: .threadId)
        turnId = try c.decode(String.self, forKey: .turnId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        strategy = try c.decode(ContextStrategy.self, forKey: .strategy)
        includedTurnIds = try c.decodeIfPresent([String].self, forKey: .includedTurnIds) ?? []
        includedRunIds = try c.decodeIfPresent([String].self, forKey: .includedRunIds) ?? []
        includedFiles = try c.decodeIfPresent([String].self, forKey: .includedFiles) ?? []
        text = try c.decode(String.self, forKey: .text)
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        truncationNote = try c.decodeIfPresent(String.self, forKey: .truncationNote)
        includedAttachments = try c.decodeIfPresent([IncludedAttachmentDelivery].self, forKey: .includedAttachments) ?? []
        includedFileReferences = try c.decodeIfPresent([IncludedFileReferenceDelivery].self, forKey: .includedFileReferences) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadId, forKey: .threadId)
        try c.encode(turnId, forKey: .turnId)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(strategy, forKey: .strategy)
        try c.encode(includedTurnIds, forKey: .includedTurnIds)
        try c.encode(includedRunIds, forKey: .includedRunIds)
        try c.encode(includedFiles, forKey: .includedFiles)
        try c.encode(text, forKey: .text)
        try c.encode(truncated, forKey: .truncated)
        try c.encodeIfPresent(truncationNote, forKey: .truncationNote)
        try c.encode(includedAttachments, forKey: .includedAttachments)
        try c.encode(includedFileReferences, forKey: .includedFileReferences)
    }
}

public enum ContextStrategy: String, Codable, Sendable, CaseIterable {
    /// Walk back from the latest turn until the cap is hit.
    case recentTurns = "recent_turns"
    /// Only the turns/files/artifacts the user explicitly selected.
    case explicitSelection = "explicit_selection"
}

public extension ThreadContextPacket {
    /// Body size in bytes (UTF-8) — the MLP measures context in bytes/characters,
    /// never estimated tokens.
    var byteCount: Int { text.utf8.count }
}

/// A pointer from a turn into durable artifacts — a run stage, a file, a diff.
/// `runId`/`stageId` keep `TeamRun` as the source of truth; the ref carries
/// only an excerpt for inline display.
public struct ArtifactRef: Codable, Sendable, Equatable {
    public var kind: ArtifactKind
    public var runId: String?
    public var stageId: String?
    public var path: String?
    public var excerpt: String?

    public init(
        kind: ArtifactKind,
        runId: String? = nil,
        stageId: String? = nil,
        path: String? = nil,
        excerpt: String? = nil
    ) {
        self.kind = kind
        self.runId = runId
        self.stageId = stageId
        self.path = path
        self.excerpt = excerpt
    }
}

public enum ArtifactKind: String, Codable, Sendable, CaseIterable {
    case plan = "master_plan"
    case finalSpec = "final_spec"
    case designBoard = "design_board"
    case dispatchResult = "dispatch_result"
    case returnReview = "return_review"
    case screenshot
    case file
    case diff
}
