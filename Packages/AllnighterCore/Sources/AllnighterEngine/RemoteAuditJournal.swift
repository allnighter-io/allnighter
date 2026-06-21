import Foundation
import AllnighterCore

public protocol RemoteAuditRecording: Sendable {
    func record(_ envelope: RemoteCommandAckEnvelope) throws
}

public struct NoopRemoteAuditRecorder: RemoteAuditRecording {
    public init() {}

    public func record(_ envelope: RemoteCommandAckEnvelope) throws {}
}

public struct RemoteAuditJournalEntry: Codable, Equatable, Sendable {
    public var accountId: String
    public var macAgentId: String
    public var requestId: String
    public var recordedAt: Date
    public var auditEvent: RemoteAuditEvent

    public init(
        accountId: String,
        macAgentId: String,
        requestId: String,
        recordedAt: Date,
        auditEvent: RemoteAuditEvent
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.requestId = requestId
        self.recordedAt = recordedAt
        self.auditEvent = auditEvent
    }
}

/// Local metadata-only audit trail for remote command handling. The relay may
/// cache acks, but the Mac keeps the durable truth about command decisions.
public struct RemoteAuditJournal: RemoteAuditRecording {
    public let fileURL: URL
    public let lockURL: URL

    public init(fileURL: URL? = nil, lockURL: URL? = nil) {
        let defaultURL = AllnighterPaths.config
            .appendingPathComponent("Remote", isDirectory: true)
            .appendingPathComponent("remote_audit.jsonl")
        self.fileURL = fileURL ?? defaultURL
        self.lockURL = lockURL ?? self.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".remote_audit.lock")
    }

    public func record(_ envelope: RemoteCommandAckEnvelope) throws {
        let entry = RemoteAuditJournalEntry(
            accountId: envelope.accountId,
            macAgentId: envelope.macAgentId,
            requestId: envelope.requestId,
            recordedAt: envelope.createdAt,
            auditEvent: envelope.auditEvent
        )
        try append(entry)
    }

    public func append(_ entry: RemoteAuditJournalEntry) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }
        try appendLine(Self.encodeLine(entry), to: fileURL)
    }

    public func entries(limit: Int? = nil) throws -> [RemoteAuditJournalEntry] {
        if let limit, limit <= 0 { return [] }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }

        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [RemoteAuditJournalEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            entries.append(try Self.decodeLine(RemoteAuditJournalEntry.self, from: Data(line.utf8)))
            if let limit, entries.count >= limit { break }
        }
        return entries
    }

    private func appendLine(_ line: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(line)
        handle.write(Data("\n".utf8))
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        try jsonEncoder.encode(value)
    }

    private static func decodeLine<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try jsonDecoder.decode(type, from: data)
    }
}
