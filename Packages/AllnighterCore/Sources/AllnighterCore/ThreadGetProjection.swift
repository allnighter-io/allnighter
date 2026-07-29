import Foundation

/// Public read projection for `alln thread get` / MCP `thread_get`. Replaces raw
/// `WorkThread` JSON so every turn carries resolved attachment paths.
public struct ThreadGetResponse: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var contractVersion: String
    public var formatVersion: Int
    public var id: String
    public var title: String
    public var status: ThreadStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var pinnedAt: Date?
    public var workingDir: String?
    public var projectLabel: String?
    public var projectId: String?
    public var localRootPathSnapshot: String?
    public var defaultModelId: String?
    public var readCursor: ThreadReadCursor?
    public var turns: [ThreadTurnProjection]

    public init(thread: WorkThread, turns: [ThreadTurnProjection], contractVersion: String) {
        schemaVersion = Self.schemaVersion
        self.contractVersion = contractVersion
        formatVersion = thread.formatVersion
        id = thread.id
        title = thread.title
        status = thread.status
        createdAt = thread.createdAt
        updatedAt = thread.updatedAt
        pinnedAt = thread.pinnedAt
        workingDir = thread.workingDir
        projectLabel = thread.projectLabel
        projectId = thread.projectId
        localRootPathSnapshot = thread.localRootPathSnapshot
        defaultModelId = thread.defaultModelId
        readCursor = thread.readCursor
        self.turns = turns
    }
}

public struct ThreadTurnProjection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    public var kind: ThreadTurnKind
    public var status: ThreadTurnStatus
    public var createdAt: Date
    public var completedAt: Date?
    public var author: TurnAuthor
    public var text: String?
    public var modelId: String?
    public var runId: String?
    public var stageId: String?
    public var artifactRefs: [ArtifactRef]
    public var attachmentRefs: [TurnAttachmentRef]
    public var fileReferenceRefs: [TurnFileReferenceRef]
    public var contextPacketId: String?
    public var supersedesTurnId: String?
    public var seedFromTurnId: String?
    public var systemEvent: SystemEventKind?
    public var partialOutputTruncated: Bool
    public var reasoningText: String?
    public var resolvedAttachments: [ResolvedThreadAttachment]

    public init(turn: ThreadTurn, resolvedAttachments: [ResolvedThreadAttachment]) {
        id = turn.id
        threadId = turn.threadId
        kind = turn.kind
        status = turn.status
        createdAt = turn.createdAt
        completedAt = turn.completedAt
        author = turn.author
        text = turn.text
        modelId = turn.modelId
        runId = turn.runId
        stageId = turn.stageId
        artifactRefs = turn.artifactRefs
        attachmentRefs = turn.attachmentRefs
        fileReferenceRefs = turn.fileReferenceRefs
        contextPacketId = turn.contextPacketId
        supersedesTurnId = turn.supersedesTurnId
        seedFromTurnId = turn.seedFromTurnId
        systemEvent = turn.systemEvent
        partialOutputTruncated = turn.partialOutputTruncated
        reasoningText = turn.reasoningText
        self.resolvedAttachments = resolvedAttachments
    }
}

public struct ThreadAttachmentGetResponse: Codable, Sendable, Equatable {
    public var threadId: String
    public var attachmentId: String
    public var canonicalPath: String
    public var storedSha256: String
    public var mimeType: String
    public var byteSize: Int
    public var storedWidth: Int?
    public var storedHeight: Int?
    public var sourceKind: AttachmentSourceKind
    public var missing: Bool
    public var error: String?

    public init(resolved: ResolvedThreadAttachment, threadId: String) {
        self.threadId = threadId
        attachmentId = resolved.attachmentId
        canonicalPath = resolved.canonicalPath
        storedSha256 = resolved.storedSha256
        mimeType = resolved.mimeType
        byteSize = resolved.byteSize
        storedWidth = resolved.storedWidth
        storedHeight = resolved.storedHeight
        sourceKind = resolved.sourceKind
        missing = resolved.missing
        error = resolved.error
    }
}
