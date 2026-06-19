import Foundation

// MARK: - File reference refs and delivery records

public struct FileLineRange: Codable, Sendable, Equatable {
    public var startLine: Int
    public var endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct FileReferenceInput: Codable, Sendable, Equatable {
    public var path: String
    public var lineRange: FileLineRange?

    public init(path: String, lineRange: FileLineRange? = nil) {
        self.path = path
        self.lineRange = lineRange
    }
}

public struct TurnFileReferenceRef: Codable, Sendable, Equatable {
    public var referenceId: String
    public var sequence: Int

    public init(referenceId: String, sequence: Int) {
        self.referenceId = referenceId
        self.sequence = sequence
    }
}

public enum FileReferenceDeliveryMode: String, Codable, Sendable, CaseIterable {
    case attachedFileBlock = "attached_file_block"
    case projectPathBlock = "project_path_block"
}

public struct IncludedFileReferenceDelivery: Codable, Sendable, Equatable {
    public var referenceId: String
    public var sequence: Int
    public var projectId: String?
    public var rootRelativePath: String
    public var lineRange: FileLineRange?
    public var resolvedAbsolutePath: String
    public var deliveredPathUsed: String
    public var storedSha256: String
    public var byteSize: Int
    public var deliveredByteCount: Int
    public var truncated: Bool
    public var languageHint: String?
    public var deliveryMode: FileReferenceDeliveryMode

    public init(
        referenceId: String,
        sequence: Int,
        projectId: String? = nil,
        rootRelativePath: String,
        lineRange: FileLineRange? = nil,
        resolvedAbsolutePath: String,
        deliveredPathUsed: String,
        storedSha256: String,
        byteSize: Int,
        deliveredByteCount: Int,
        truncated: Bool,
        languageHint: String? = nil,
        deliveryMode: FileReferenceDeliveryMode
    ) {
        self.referenceId = referenceId
        self.sequence = sequence
        self.projectId = projectId
        self.rootRelativePath = rootRelativePath
        self.lineRange = lineRange
        self.resolvedAbsolutePath = resolvedAbsolutePath
        self.deliveredPathUsed = deliveredPathUsed
        self.storedSha256 = storedSha256
        self.byteSize = byteSize
        self.deliveredByteCount = deliveredByteCount
        self.truncated = truncated
        self.languageHint = languageHint
        self.deliveryMode = deliveryMode
    }
}

public struct FileReferencePolicy: Codable, Sendable, Equatable {
    public var maxCount: Int
    public var maxDeliveredBytesPerFile: Int
    public var maxTotalDeliveredBytes: Int
    public var maxSourceBytes: Int

    public static let `default` = FileReferencePolicy(
        maxCount: 12,
        maxDeliveredBytesPerFile: 64 * 1024,
        maxTotalDeliveredBytes: 256 * 1024,
        maxSourceBytes: 1024 * 1024
    )

    public init(
        maxCount: Int,
        maxDeliveredBytesPerFile: Int,
        maxTotalDeliveredBytes: Int,
        maxSourceBytes: Int
    ) {
        self.maxCount = maxCount
        self.maxDeliveredBytesPerFile = maxDeliveredBytesPerFile
        self.maxTotalDeliveredBytes = maxTotalDeliveredBytes
        self.maxSourceBytes = maxSourceBytes
    }
}
