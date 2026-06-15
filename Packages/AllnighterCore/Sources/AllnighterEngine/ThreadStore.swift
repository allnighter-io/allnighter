import Foundation
import AllnighterCore

public enum ThreadStoreError: Error, Equatable, CustomStringConvertible {
    case threadNotFound(String)
    case turnNotFound(String)
    case illegalTurnTransition(turnId: String, from: ThreadTurnStatus, to: ThreadTurnStatus)

    public var description: String {
        switch self {
        case .threadNotFound(let id): return "Thread not found: \(id)"
        case .turnNotFound(let id): return "Turn not found: \(id)"
        case .illegalTurnTransition(let id, let from, let to):
            return "Illegal turn transition for \(id): \(from.rawValue) -> \(to.rawValue)"
        }
    }
}

/// Persists work threads to disk as a folder per thread under Application
/// Support, mirroring `RunStore`: `thread.json` is truth, `transcript.md` is
/// derived. Flat files now; GRDB is the documented growth path.
///
/// The run→thread inverse index (PWT-S02) is **derived** by scanning thread
/// turns, never an authoritative stored mapping, so it cannot drift from turn
/// truth. `CouncilRun` is never modified for chat.
public struct ThreadStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.threads
    }

    /// The thread's folder (created if needed).
    @discardableResult
    public func threadDirectory(forThreadId threadId: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("thread_\(threadId)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Read

    public func get(_ id: String) -> WorkThread? {
        let url = rootDirectory
            .appendingPathComponent("thread_\(id)", isDirectory: true)
            .appendingPathComponent("thread.json")
        return try? CoreJSON.decode(WorkThread.self, from: Data(contentsOf: url))
    }

    /// Lists saved threads, most recently updated first. Triage ordering
    /// (pinned/attention/running) is a higher-level concern layered on top.
    public func list() -> [WorkThread] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix("thread_") }
            .compactMap { try? CoreJSON.decode(WorkThread.self, from: Data(contentsOf: $0.appendingPathComponent("thread.json"))) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Write

    @discardableResult
    public func save(_ thread: WorkThread) throws -> URL {
        let directory = try threadDirectory(forThreadId: thread.id)
        try CoreJSON.encode(thread).write(to: directory.appendingPathComponent("thread.json"))
        // Derived transcript, regenerated from thread.json truth on each save.
        let transcript = ThreadMarkdown.transcript(thread)
        try Data(transcript.utf8).write(to: directory.appendingPathComponent("transcript.md"))
        return directory
    }

    /// Appends a turn and bumps `updatedAt`. The turn's `threadId` is normalized
    /// to the target thread.
    @discardableResult
    public func append(_ turn: ThreadTurn, toThreadId threadId: String, now: Date) throws -> WorkThread {
        guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
        var turn = turn
        turn.threadId = threadId
        thread.turns.append(turn)
        thread.updatedAt = now
        try save(thread)
        return thread
    }

    /// Replaces an existing turn (matched by id) in place — used to settle an
    /// optimistic `running` turn to `done`/`failed`/etc. Validates the lifecycle
    /// transition unless the status is unchanged.
    @discardableResult
    public func update(_ turn: ThreadTurn, inThreadId threadId: String, now: Date) throws -> WorkThread {
        guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
        guard let index = thread.turns.firstIndex(where: { $0.id == turn.id }) else {
            throw ThreadStoreError.turnNotFound(turn.id)
        }
        let previous = thread.turns[index].status
        if previous != turn.status, !previous.allowedTransitions().contains(turn.status) {
            throw ThreadStoreError.illegalTurnTransition(turnId: turn.id, from: previous, to: turn.status)
        }
        var turn = turn
        turn.threadId = threadId
        thread.turns[index] = turn
        thread.updatedAt = now
        try save(thread)
        return thread
    }

    @discardableResult
    public func archive(_ id: String, now: Date) throws -> WorkThread {
        guard var thread = get(id) else { throw ThreadStoreError.threadNotFound(id) }
        thread.status = .archived
        thread.updatedAt = now
        try save(thread)
        return thread
    }

    // MARK: - Derived run -> thread index (PWT-S02)

    /// The thread that references a given run, if any. Derived by scan.
    public func threadId(forRunId runId: String) -> String? {
        for thread in list() {
            if thread.turns.contains(where: { $0.runId == runId }) {
                return thread.id
            }
        }
        return nil
    }

    /// Full run→thread map, derived from current thread truth. The latest
    /// thread (by updatedAt) wins if a run is somehow referenced twice.
    public func runToThreadIndex() -> [String: String] {
        var index: [String: String] = [:]
        // list() is newest-first; iterate oldest-first so newer threads win.
        for thread in list().reversed() {
            for turn in thread.turns {
                if let runId = turn.runId {
                    index[runId] = thread.id
                }
            }
        }
        return index
    }
}
