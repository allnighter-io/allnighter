import Foundation

/// One resolved thread attachment row for CLI/MCP read and Mac timeline rendering.
public struct ResolvedThreadAttachment: Codable, Sendable, Equatable {
    public var attachmentId: String
    public var sequence: Int
    public var canonicalPath: String
    public var storedSha256: String
    public var mimeType: String
    public var sourceKind: AttachmentSourceKind
    public var byteSize: Int
    public var storedWidth: Int?
    public var storedHeight: Int?
    public var originalName: String?
    public var missing: Bool
    public var error: String?

    public init(
        attachmentId: String,
        sequence: Int,
        canonicalPath: String,
        storedSha256: String,
        mimeType: String,
        sourceKind: AttachmentSourceKind,
        byteSize: Int,
        storedWidth: Int? = nil,
        storedHeight: Int? = nil,
        originalName: String? = nil,
        missing: Bool = false,
        error: String? = nil
    ) {
        self.attachmentId = attachmentId
        self.sequence = sequence
        self.canonicalPath = canonicalPath
        self.storedSha256 = storedSha256
        self.mimeType = mimeType
        self.sourceKind = sourceKind
        self.byteSize = byteSize
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.originalName = originalName
        self.missing = missing
        self.error = error
    }
}
