import Foundation
import AllnighterCore

public enum ThreadStoreError: Error, Equatable, CustomStringConvertible {
    case threadNotFound(String)
    case threadAlreadyExists(String)
    case turnNotFound(String)
    case duplicateTurnId(String)
    case illegalTurnTransition(turnId: String, from: ThreadTurnStatus, to: ThreadTurnStatus)
    case emptyTitle
    case cannotPinArchivedThread(String)
    case missingContextPacket(String)

    public var description: String {
        switch self {
        case .threadNotFound(let id): return "Thread not found: \(id)"
        case .threadAlreadyExists(let id): return "Thread already exists: \(id)"
        case .turnNotFound(let id): return "Turn not found: \(id)"
        case .duplicateTurnId(let id): return "Duplicate turn id: \(id)"
        case .illegalTurnTransition(let id, let from, let to):
            return "Illegal turn transition for \(id): \(from.rawValue) -> \(to.rawValue)"
        case .emptyTitle: return "Thread title cannot be empty"
        case .cannotPinArchivedThread(let id): return "Cannot pin archived thread: \(id)"
        case .missingContextPacket(let id): return "Missing context packet: \(id)"
        }
    }
}

/// Persists work threads to disk as a folder per thread under Application
/// Support, mirroring `RunStore`: `thread.json` is truth, `transcript.md` is
/// derived. Flat files now; GRDB is the documented growth path.
///
/// The run→thread inverse index (PWT-S02) is **derived** by scanning thread
/// turns, never an authoritative stored mapping, so it cannot drift from turn
/// truth. `TeamRun` is never modified for chat.
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

    /// Creates and persists a new thread. `id`/`now` are explicit so callers
    /// stay deterministic (the coordinator injects its own factories).
    @discardableResult
    public func create(
        id: String,
        title: String,
        now: Date,
        workingDir: String? = nil,
        projectLabel: String? = nil,
        defaultWorkerId: String? = nil
    ) throws -> WorkThread {
        try synchronized {
            let threadDirectory = rootDirectory.appendingPathComponent("thread_\(id)", isDirectory: true)
            if get(id) != nil || FileManager.default.fileExists(atPath: threadDirectory.path) {
                throw ThreadStoreError.threadAlreadyExists(id)
            }
            let thread = WorkThread(
                id: id, title: title, status: .active, createdAt: now, updatedAt: now,
                workingDir: workingDir, projectLabel: projectLabel, defaultWorkerId: defaultWorkerId
            )
            _ = try persistContent(thread)
            return thread
        }
    }

    /// Fixture/import-only full-record write. App runtime must use explicit
    /// mutation methods instead of mutating a `WorkThread` and saving it back.
    @discardableResult
    public func saveForImport(_ thread: WorkThread) throws -> URL {
        try synchronized { try persistContent(thread) }
    }

    /// Appends a turn and bumps `updatedAt`. The turn's `threadId` is normalized
    /// to the target thread.
    @discardableResult
    public func appendTurn(_ turn: ThreadTurn, toThreadId threadId: String, now: Date) throws -> WorkThread {
        try synchronized {
            guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            if thread.turns.contains(where: { $0.id == turn.id }) {
                throw ThreadStoreError.duplicateTurnId(turn.id)
            }
            try validateContextPacket(for: turn, threadId: threadId)
            var turn = turn
            turn.threadId = threadId
            thread.turns.append(turn)
            thread.updatedAt = now
            _ = try persistContent(thread)
            return thread
        }
    }

    @available(*, deprecated, renamed: "appendTurn(_:toThreadId:now:)")
    @discardableResult
    public func append(_ turn: ThreadTurn, toThreadId threadId: String, now: Date) throws -> WorkThread {
        try appendTurn(turn, toThreadId: threadId, now: now)
    }

    /// Replaces an existing turn (matched by id) in place — used to settle an
    /// optimistic `running` turn to `done`/`failed`/etc. Validates the lifecycle
    /// transition unless the status is unchanged.
    @discardableResult
    public func updateTurn(_ turn: ThreadTurn, inThreadId threadId: String, now: Date) throws -> WorkThread {
        try synchronized {
            guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            guard let index = thread.turns.firstIndex(where: { $0.id == turn.id }) else {
                throw ThreadStoreError.turnNotFound(turn.id)
            }
            let previous = thread.turns[index].status
            if previous != turn.status, !previous.allowedTransitions().contains(turn.status) {
                throw ThreadStoreError.illegalTurnTransition(turnId: turn.id, from: previous, to: turn.status)
            }
            try validateContextPacket(for: turn, threadId: threadId)
            var turn = turn
            turn.threadId = threadId
            thread.turns[index] = turn
            thread.updatedAt = now
            _ = try persistContent(thread)
            return thread
        }
    }

    @available(*, deprecated, renamed: "updateTurn(_:inThreadId:now:)")
    @discardableResult
    public func update(_ turn: ThreadTurn, inThreadId threadId: String, now: Date) throws -> WorkThread {
        try updateTurn(turn, inThreadId: threadId, now: now)
    }

    @discardableResult
    public func renameThread(threadId: String, title: String) throws -> WorkThread {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThreadStoreError.emptyTitle }
        return try synchronized {
            guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            thread.title = trimmed
            _ = try persistMetadata(thread, regenerateTranscript: true)
            return thread
        }
    }

    @discardableResult
    public func setPinned(threadId: String, pinned: Bool, now: Date) throws -> WorkThread {
        try synchronized {
            guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            if pinned {
                guard !thread.isArchived else { throw ThreadStoreError.cannotPinArchivedThread(threadId) }
                if thread.pinnedAt == nil {
                    thread.pinnedAt = now
                    _ = try persistMetadata(thread, regenerateTranscript: false)
                }
            } else if thread.pinnedAt != nil {
                thread.pinnedAt = nil
                _ = try persistMetadata(thread, regenerateTranscript: false)
            }
            return thread
        }
    }

    @discardableResult
    public func archiveThread(threadId: String) throws -> WorkThread {
        try synchronized {
            guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            thread.status = .archived
            thread.pinnedAt = nil
            _ = try persistMetadata(thread, regenerateTranscript: false)
            return thread
        }
    }

    @discardableResult
    public func unarchiveThread(threadId: String) throws -> WorkThread {
        try synchronized {
            guard var thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            thread.status = .active
            _ = try persistMetadata(thread, regenerateTranscript: false)
            return thread
        }
    }

    // MARK: - Context packets

    /// Persists the exact context a worker was given, under the thread folder,
    /// so "what the worker saw" can be revealed later as truth.
    @discardableResult
    public func savePacket(_ packet: ThreadContextPacket) throws -> URL {
        try synchronized { try persistPacket(packet) }
    }

    public func packet(threadId: String, packetId: String) -> ThreadContextPacket? {
        let url = rootDirectory
            .appendingPathComponent("thread_\(threadId)", isDirectory: true)
            .appendingPathComponent("context", isDirectory: true)
            .appendingPathComponent("\(packetId).json")
        return try? CoreJSON.decode(ThreadContextPacket.self, from: Data(contentsOf: url))
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

    // MARK: - Private persistence

    private func validateContextPacket(for turn: ThreadTurn, threadId: String) throws {
        guard let packetId = turn.contextPacketId else { return }
        if packet(threadId: threadId, packetId: packetId) == nil {
            throw ThreadStoreError.missingContextPacket(packetId)
        }
    }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        try ThreadStoreWriteSerializer.synchronized(rootDirectory: rootDirectory, body)
    }

    /// Append/update turns, create, and fixture import: atomic `thread.json` +
    /// full transcript regeneration.
    private func persistContent(_ thread: WorkThread) throws -> URL {
        let directory = try preparedThreadDirectory(for: thread)
        try writeThreadJSON(thread, to: directory)
        try writeTranscript(for: thread, to: directory)
        return directory
    }

    /// Rename/pin/archive/unarchive: atomic `thread.json`; transcript only when
    /// rename changes the title heading.
    private func persistMetadata(_ thread: WorkThread, regenerateTranscript: Bool) throws -> URL {
        let directory = try preparedThreadDirectory(for: thread)
        try writeThreadJSON(thread, to: directory)
        if regenerateTranscript {
            try writeTranscript(for: thread, to: directory)
        }
        return directory
    }

    /// Read-cursor writes (full `markRead` lands in 06): atomic `thread.json`
    /// only; `transcript.md` bytes must stay identical.
    private func persistCursor(_ thread: WorkThread) throws -> URL {
        let directory = try preparedThreadDirectory(for: thread)
        try writeThreadJSON(thread, to: directory)
        return directory
    }

    /// Test hook for cursor-only persistence before `markRead` ships (06). Reloads
    /// under the write lock so callers cannot pass a stale `WorkThread` snapshot.
    internal func testPersistCursor(threadId: String) throws -> URL {
        try synchronized {
            guard let thread = get(threadId) else { throw ThreadStoreError.threadNotFound(threadId) }
            return try persistCursor(thread)
        }
    }

    private func preparedThreadDirectory(for thread: WorkThread) throws -> URL {
        var thread = thread
        thread.upgradeFormatVersionIfNeeded()
        return try threadDirectory(forThreadId: thread.id)
    }

    private func writeThreadJSON(_ thread: WorkThread, to directory: URL) throws {
        var thread = thread
        thread.upgradeFormatVersionIfNeeded()
        try CoreJSON.encode(thread).write(
            to: directory.appendingPathComponent("thread.json"),
            options: .atomic
        )
    }

    private func writeTranscript(for thread: WorkThread, to directory: URL) throws {
        let transcript = ThreadMarkdown.transcript(thread)
        try Data(transcript.utf8).write(to: directory.appendingPathComponent("transcript.md"))
    }

    private func persistPacket(_ packet: ThreadContextPacket) throws -> URL {
        let directory = try threadDirectory(forThreadId: packet.threadId)
            .appendingPathComponent("context", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(packet.id).json")
        try CoreJSON.encode(packet).write(to: url, options: .atomic)
        return url
    }
}
