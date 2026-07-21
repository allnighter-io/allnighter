import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct ThreadSendCanonicalPayload: Codable, Sendable, Equatable {
    public var threadId: String
    public var message: String
    public var workerId: String?
    public var imageHashes: [String]
    public var fileReferences: [FileReferenceInput]

    public init(
        threadId: String,
        message: String,
        workerId: String?,
        imageHashes: [String],
        fileReferences: [FileReferenceInput] = []
    ) {
        self.threadId = threadId
        self.message = message
        self.workerId = workerId
        self.imageHashes = imageHashes
        self.fileReferences = fileReferences
    }
}

/// Durable idempotency for `thread send` / `thread_send` (24h retention).
public struct ThreadSendIdempotencyStore: Sendable {
    public static let retention: TimeInterval = 24 * 60 * 60

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.config.appendingPathComponent("Tool/thread_send_idempotency.json")
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var key: String
        public var payloadDigest: String
        public var userTurnId: String
        public var workerTurnId: String
        public var workerAttachmentIds: [String]?
        public var fileReferenceIds: [String]?
        public var acceptedAt: Date
    }

    private struct File: Codable {
        var entries: [Entry]
    }

    public enum Lookup {
        case miss
        case hit(Entry)
        case conflict
    }

    public func lookup(key: String, payload: ThreadSendCanonicalPayload, now: Date = Date()) -> Lookup {
        prune(now: now)
        guard let existing = load().entries.first(where: { $0.key == key }) else { return .miss }
        if existing.payloadDigest == Self.digest(payload) { return .hit(existing) }
        return .conflict
    }

    @discardableResult
    public func record(
        key: String,
        payload: ThreadSendCanonicalPayload,
        userTurnId: String,
        workerTurnId: String,
        workerAttachmentIds: [String]? = nil,
        fileReferenceIds: [String]? = nil,
        now: Date = Date()
    ) throws -> Entry {
        var file = load()
        pruneEntries(&file.entries, now: now)
        let entry = Entry(
            key: key,
            payloadDigest: Self.digest(payload),
            userTurnId: userTurnId,
            workerTurnId: workerTurnId,
            workerAttachmentIds: workerAttachmentIds,
            fileReferenceIds: fileReferenceIds,
            acceptedAt: now
        )
        file.entries.removeAll { $0.key == key }
        file.entries.append(entry)
        try save(file)
        return entry
    }

    public static func digest(_ payload: ThreadSendCanonicalPayload) -> String {
        let data = (try? CoreJSON.encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func load() -> File {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? CoreJSON.decode(File.self, from: data) else {
            return File(entries: [])
        }
        return file
    }

    private func save(_ file: File) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CoreJSON.encode(file).write(to: fileURL)
    }

    private func prune(now: Date) {
        var file = load()
        let before = file.entries.count
        pruneEntries(&file.entries, now: now)
        guard file.entries.count != before else { return }
        try? save(file)
    }

    private func pruneEntries(_ entries: inout [Entry], now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        entries.removeAll { $0.acceptedAt < cutoff }
    }
}
