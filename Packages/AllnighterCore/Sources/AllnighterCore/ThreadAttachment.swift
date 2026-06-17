import Foundation

// MARK: - Refs and delivery records

public struct TurnAttachmentRef: Codable, Sendable, Equatable {
    public var attachmentId: String
    public var sequence: Int

    public init(attachmentId: String, sequence: Int) {
        self.attachmentId = attachmentId
        self.sequence = sequence
    }
}

public struct DraftAttachmentRef: Codable, Sendable, Equatable {
    public var draftId: String
    public var sequence: Int
    public var status: DraftAttachmentStatus

    public init(draftId: String, sequence: Int, status: DraftAttachmentStatus) {
        self.draftId = draftId
        self.sequence = sequence
        self.status = status
    }
}

public struct IncludedAttachmentDelivery: Codable, Sendable, Equatable {
    public var attachmentId: String
    public var sequence: Int
    public var canonicalPath: String
    public var deliveredPathUsed: String
    public var storedSha256: String

    public init(
        attachmentId: String,
        sequence: Int,
        canonicalPath: String,
        deliveredPathUsed: String,
        storedSha256: String
    ) {
        self.attachmentId = attachmentId
        self.sequence = sequence
        self.canonicalPath = canonicalPath
        self.deliveredPathUsed = deliveredPathUsed
        self.storedSha256 = storedSha256
    }
}

// MARK: - Canonical attachment record

public enum DraftAttachmentStatus: String, Codable, Sendable, CaseIterable {
    case ingesting
    case ready
    case failed
}

public enum AttachmentSourceKind: String, Codable, Sendable, CaseIterable {
    case paste
    case cliFile = "cli_file"
    case mcpPath = "mcp_path"
    case mcpBase64 = "mcp_base64"
    case guiAttach = "gui_attach"
}

public struct TurnAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    public var createdAt: Date
    public var storagePath: String
    public var mimeType: String
    public var byteSize: Int
    public var storedSha256: String
    public var sourceSha256: String?
    public var originalWidth: Int?
    public var originalHeight: Int?
    public var storedWidth: Int?
    public var storedHeight: Int?
    public var originalName: String?
    public var sourceKind: AttachmentSourceKind
    public var wasDownscaled: Bool

    public init(
        id: String,
        threadId: String,
        createdAt: Date,
        storagePath: String,
        mimeType: String,
        byteSize: Int,
        storedSha256: String,
        sourceSha256: String? = nil,
        originalWidth: Int? = nil,
        originalHeight: Int? = nil,
        storedWidth: Int? = nil,
        storedHeight: Int? = nil,
        originalName: String? = nil,
        sourceKind: AttachmentSourceKind,
        wasDownscaled: Bool
    ) {
        self.id = id
        self.threadId = threadId
        self.createdAt = createdAt
        self.storagePath = storagePath
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.storedSha256 = storedSha256
        self.sourceSha256 = sourceSha256
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.originalName = originalName
        self.sourceKind = sourceKind
        self.wasDownscaled = wasDownscaled
    }
}

// MARK: - Policy

public struct AttachmentPolicy: Codable, Sendable, Equatable {
    public var maxCount: Int
    public var maxBytesPerImage: Int
    public var maxTotalBytes: Int
    public var maxLongEdgePixels: Int
    public var maxDecodeMegapixels: Int

    public static let `default` = AttachmentPolicy(
        maxCount: 4,
        maxBytesPerImage: 8 * 1024 * 1024,
        maxTotalBytes: 20 * 1024 * 1024,
        maxLongEdgePixels: 2048,
        maxDecodeMegapixels: 40
    )

    public init(
        maxCount: Int,
        maxBytesPerImage: Int,
        maxTotalBytes: Int,
        maxLongEdgePixels: Int,
        maxDecodeMegapixels: Int
    ) {
        self.maxCount = maxCount
        self.maxBytesPerImage = maxBytesPerImage
        self.maxTotalBytes = maxTotalBytes
        self.maxLongEdgePixels = maxLongEdgePixels
        self.maxDecodeMegapixels = maxDecodeMegapixels
    }
}

// MARK: - On-disk indexes

public struct DraftAttachmentIndex: Codable, Sendable, Equatable {
    public var drafts: [DraftAttachmentRef]
    public var nextSequence: Int

    public init(drafts: [DraftAttachmentRef] = [], nextSequence: Int = 0) {
        self.drafts = drafts
        self.nextSequence = nextSequence
    }
}

public struct AttachmentIndex: Codable, Sendable, Equatable {
    public var attachments: [TurnAttachment]

    public init(attachments: [TurnAttachment] = []) {
        self.attachments = attachments
    }
}

// MARK: - Delivery strategy

public enum ImageDeliveryStrategy: String, Codable, Sendable, CaseIterable {
    case promptPathBlock = "prompt_path_block"
}

public struct IngestedAttachment: Sendable, Equatable {
    public var pngData: Data
    public var mimeType: String
    public var byteSize: Int
    public var storedSha256: String
    public var sourceSha256: String?
    public var originalWidth: Int?
    public var originalHeight: Int?
    public var storedWidth: Int
    public var storedHeight: Int
    public var wasDownscaled: Bool

    public init(
        pngData: Data,
        mimeType: String,
        byteSize: Int,
        storedSha256: String,
        sourceSha256: String? = nil,
        originalWidth: Int? = nil,
        originalHeight: Int? = nil,
        storedWidth: Int,
        storedHeight: Int,
        wasDownscaled: Bool
    ) {
        self.pngData = pngData
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.storedSha256 = storedSha256
        self.sourceSha256 = sourceSha256
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.wasDownscaled = wasDownscaled
    }
}

// MARK: - Errors

public enum AttachmentError: Error, Equatable, CustomStringConvertible {
    case hashMismatch
    case tooMany
    case tooLarge
    case unsupportedType
    case decodeFailed
    case base64Invalid
    case stageFailed
    case stageUnignored
    case contextCapExceeded
    case draftNotReady(String)
    case attachmentNotFound(String)
    case fileUnreadable(String)

    public var code: String {
        switch self {
        case .hashMismatch: return "ATTACHMENT_HASH_MISMATCH"
        case .tooMany: return "ATTACHMENT_TOO_MANY"
        case .tooLarge: return "ATTACHMENT_TOO_LARGE"
        case .unsupportedType: return "ATTACHMENT_UNSUPPORTED_TYPE"
        case .decodeFailed: return "ATTACHMENT_DECODE_FAILED"
        case .base64Invalid: return "ATTACHMENT_BASE64_INVALID"
        case .stageFailed: return "ATTACHMENT_STAGE_FAILED"
        case .stageUnignored: return "ATTACHMENT_STAGE_UNIGNORED"
        case .contextCapExceeded: return "CONTEXT_ATTACHMENT_CAP_EXCEEDED"
        case .draftNotReady, .attachmentNotFound, .fileUnreadable: return "ATTACHMENT_DECODE_FAILED"
        }
    }

    public var description: String {
        switch self {
        case .hashMismatch: return "Attachment hash mismatch"
        case .tooMany: return "Too many attachments"
        case .tooLarge: return "Attachment too large"
        case .unsupportedType: return "Unsupported attachment type"
        case .decodeFailed: return "Attachment decode failed"
        case .base64Invalid: return "Invalid base64 attachment"
        case .stageFailed: return "Attachment staging failed"
        case .stageUnignored: return "Attachment staged but git ignore could not be updated"
        case .contextCapExceeded: return "Protected attachment block exceeds context cap"
        case .draftNotReady(let id): return "Draft not ready: \(id)"
        case .attachmentNotFound(let id): return "Attachment not found: \(id)"
        case .fileUnreadable(let path): return "File unreadable: \(path)"
        }
    }
}
