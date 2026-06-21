import Foundation
import AllnighterCore

/// Durable per-thread store of `ExternalWorkerSession` records — the truth that lets turn 2
/// resume turn 1's vendor CLI session. One JSON sidecar per thread
/// (`…/Allnighter/WorkerSessions/<threadId>.json`) holding that thread's records across
/// every source/model it has used. The visible thread owns this truth; the file is a
/// detail. Injectable `root` for tests.
public final class ExternalWorkerSessionStore: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()

    public static var defaultRoot: URL {
        AllnighterPaths.support.appendingPathComponent("WorkerSessions", isDirectory: true)
    }

    public init(root: URL = ExternalWorkerSessionStore.defaultRoot) {
        self.root = root
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func fileURL(threadId: String) -> URL {
        root.appendingPathComponent("\(threadId).json")
    }

    /// All records for a thread (every source/model it has talked to).
    public func all(threadId: String) -> [ExternalWorkerSession] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked(threadId: threadId)
    }

    /// The record for an exact `(thread, source, model, repoRoot)`, if any.
    public func get(_ key: ExternalWorkerSession.Key) -> ExternalWorkerSession? {
        all(threadId: key.threadId).first { $0.matches(key) }
    }

    /// The live, resumable vendor session for a key — nil unless it has a vendor id and is
    /// active. The resume decision (and the "skip the context dump" decision) keys off this.
    public func resumable(_ key: ExternalWorkerSession.Key) -> ExternalWorkerSession? {
        get(key).flatMap { $0.isResumable ? $0 : nil }
    }

    @discardableResult
    public func upsert(_ session: ExternalWorkerSession) -> ExternalWorkerSession {
        lock.lock(); defer { lock.unlock() }
        var sessions = loadLocked(threadId: session.threadId)
        if let i = sessions.firstIndex(where: { $0.matches(session.key) }) {
            sessions[i] = session
        } else {
            sessions.append(session)
        }
        saveLocked(threadId: session.threadId, sessions)
        return session
    }

    /// Mark a key's session invalidated (e.g. a resume failed / the vendor evicted it), so
    /// the next turn starts fresh + re-seeds context instead of resuming a dead id.
    public func invalidate(_ key: ExternalWorkerSession.Key) {
        lock.lock(); defer { lock.unlock() }
        var sessions = loadLocked(threadId: key.threadId)
        guard let i = sessions.firstIndex(where: { $0.matches(key) }) else { return }
        sessions[i].status = .invalidated
        saveLocked(threadId: key.threadId, sessions)
    }

    // MARK: - File I/O (caller holds `lock`)

    private func loadLocked(threadId: String) -> [ExternalWorkerSession] {
        guard let data = try? Data(contentsOf: fileURL(threadId: threadId)) else { return [] }
        return (try? Self.decoder.decode([ExternalWorkerSession].self, from: data)) ?? []
    }

    private func saveLocked(threadId: String, _ sessions: [ExternalWorkerSession]) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(sessions) else { return }
        try? data.write(to: fileURL(threadId: threadId), options: .atomic)
    }
}
