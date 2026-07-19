import Foundation
import AllnighterCore
import CryptoKit

/// Durable idempotency records for async `team start` (24h retention).
public struct IdempotencyStore: Sendable {
    public static let retention: TimeInterval = 24 * 60 * 60

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.config.appendingPathComponent("Tool/idempotency.json")
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var key: String
        public var payloadDigest: String
        public var runId: String
        public var acceptedAt: Date
    }

    /// F5b: result of an atomic same-key claim under the per-file flock.
    public enum ClaimResult: Equatable, Sendable {
        /// This caller owns the key and must mint/spawn `entry.runId`.
        case claimed(Entry)
        /// Another caller already owns this key+payload — replay their run.
        case replay(Entry)
        /// Same key was already used with a different payload.
        case conflict(Entry)
    }

    private struct File: Codable {
        var entries: [Entry]
    }

    public func lookup(key: String, now: Date = Date()) -> Entry? {
        prune(now: now)
        return load().entries.first { $0.key == key }
    }

    /// F5b single-flight: under the flock, either insert this runId as the
    /// sole owner of `key`, return the existing same-digest owner for replay,
    /// or refuse a digest mismatch. Does **not** steal an in-flight claim
    /// (peer may not have persisted the journal yet) — callers wait/replay,
    /// then optionally `forceClaim` if the peer vanished.
    public func claim(
        key: String,
        payload: AsyncTeamCanonicalPayload,
        runId: String,
        now: Date = Date()
    ) throws -> ClaimResult {
        try withLock {
            var file = load()
            pruneEntries(&file.entries, now: now)
            let digest = Self.digest(payload)
            if let existing = file.entries.first(where: { $0.key == key }) {
                if existing.payloadDigest != digest {
                    return .conflict(existing)
                }
                return .replay(existing)
            }
            let entry = Entry(key: key, payloadDigest: digest, runId: runId, acceptedAt: now)
            file.entries.append(entry)
            try save(file)
            return .claimed(entry)
        }
    }

    /// Replace an orphaned same-digest claim whose journal is gone. No-ops into
    /// replay/conflict when the existing owner is still live or digests differ.
    public func forceClaim(
        key: String,
        payload: AsyncTeamCanonicalPayload,
        runId: String,
        now: Date = Date(),
        runExists: (String) -> Bool
    ) throws -> ClaimResult {
        try withLock {
            var file = load()
            pruneEntries(&file.entries, now: now)
            let digest = Self.digest(payload)
            if let existing = file.entries.first(where: { $0.key == key }) {
                if existing.payloadDigest != digest {
                    return .conflict(existing)
                }
                if runExists(existing.runId) {
                    return .replay(existing)
                }
                let entry = Entry(key: key, payloadDigest: digest, runId: runId, acceptedAt: now)
                file.entries.removeAll { $0.key == key }
                file.entries.append(entry)
                try save(file)
                return .claimed(entry)
            }
            let entry = Entry(key: key, payloadDigest: digest, runId: runId, acceptedAt: now)
            file.entries.append(entry)
            try save(file)
            return .claimed(entry)
        }
    }

    @discardableResult
    public func record(key: String, payload: AsyncTeamCanonicalPayload, runId: String, now: Date = Date()) throws -> Entry {
        // F5a (Concurrent Invocation Isolation): the load → mutate → save RMW
        // runs under the per-file flock — concurrent callers used to
        // lost-update the shared file. Prefer `claim` for first ownership;
        // `record` refreshes acceptedAt after a detached handshake.
        try withLock {
            var file = load()
            pruneEntries(&file.entries, now: now)
            let digest = Self.digest(payload)
            let entry = Entry(key: key, payloadDigest: digest, runId: runId, acceptedAt: now)
            file.entries.removeAll { $0.key == key }
            file.entries.append(entry)
            try save(file)
            return entry
        }
    }

    public static func digest(_ payload: AsyncTeamCanonicalPayload) -> String {
        let data = (try? CoreJSON.encode(payload)) ?? Data()
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
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
        try CoreJSON.encode(file).write(to: fileURL, options: .atomic)
    }

    private func prune(now: Date) {
        withLock {
            var file = load()
            let before = file.entries.count
            pruneEntries(&file.entries, now: now)
            guard file.entries.count != before else { return }
            try? save(file)
        }
    }

    /// Per-file flock serializing the load → mutate → save RMW across
    /// concurrent callers (F5). Mirrors `ProcessOwnership.withRunLock`: a
    /// lock-open failure degrades to the prior unlocked behavior rather than
    /// refusing the write.
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        _ = flock(fd, LOCK_EX)
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    private func pruneEntries(_ entries: inout [Entry], now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        entries.removeAll { $0.acceptedAt < cutoff }
    }
}
