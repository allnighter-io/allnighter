import Foundation

/// The mailbox that lets Allnighter work from inside a host that sandboxes it.
///
/// A sandboxed caller (today: Codex) can read and write Allnighter's own support
/// directory, but cannot start the vendor CLIs — they need Keychain access the
/// sandbox denies. So the caller drops a request here, a process OUTSIDE the
/// sandbox (the Mac app) picks it up and runs it, and the caller reads the
/// result back from the ordinary run journal.
///
/// Deliberately small: a directory of request files with one claim step. It is
/// not a protocol, not a daemon, and not a second run owner — whoever claims a
/// request runs it through the same `RunService.run` as everyone else.
public struct SandboxHandoffSpool: Sendable {
    public struct Request: Codable, Equatable, Sendable {
        public var id: String
        public var runId: String
        public var message: String
        public var repoRoot: String
        public var presetId: String?
        public var workerId: String?
        public var createdAt: Date
        /// Set when a host outside the sandbox takes ownership. A request is
        /// claimed exactly once; a second claimer must skip it.
        public var claimedAt: Date?
        public var claimedBy: String?

        public init(
            id: String = UUID().uuidString,
            runId: String,
            message: String,
            repoRoot: String,
            presetId: String? = nil,
            workerId: String? = nil,
            createdAt: Date = Date(),
            claimedAt: Date? = nil,
            claimedBy: String? = nil
        ) {
            self.id = id
            self.runId = runId
            self.message = message
            self.repoRoot = repoRoot
            self.presetId = presetId
            self.workerId = workerId
            self.createdAt = createdAt
            self.claimedAt = claimedAt
            self.claimedBy = claimedBy
        }
    }

    public let directory: URL

    private var fileManager: FileManager { .default }

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? AllnighterSupportRoot.support.appendingPathComponent("Handoff", isDirectory: true)
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    /// Drops a request in the mailbox. Called from inside the sandbox.
    @discardableResult
    public func enqueue(_ request: Request) throws -> Request {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(request).write(to: url(for: request.id), options: .atomic)
        return request
    }

    /// Every request still waiting for someone to run it, oldest first.
    public func unclaimed() throws -> [Request] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files
            .map { try CoreJSON.decode(Request.self, from: Data(contentsOf: $0)) }
            .filter { $0.claimedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Takes ownership. Returns nil when someone else already claimed it, so two
    /// hosts can watch the same mailbox without double-running a request.
    public func claim(id: String, by owner: String, now: Date = Date()) throws -> Request? {
        let file = url(for: id)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        var request = try CoreJSON.decode(Request.self, from: Data(contentsOf: file))
        guard request.claimedAt == nil else { return nil }
        request.claimedAt = now
        request.claimedBy = owner
        try CoreJSON.encode(request).write(to: file, options: .atomic)
        return request
    }

    /// Removes a finished request. The run journal is the durable record; this
    /// mailbox holds no results of its own.
    public func remove(id: String) {
        try? fileManager.removeItem(at: url(for: id))
    }
}
