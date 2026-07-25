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
        /// What the host should do with this request.
        public enum Kind: String, Codable, Sendable {
            /// Ordinary work: run it through `RunService`.
            case run
            /// A liveness check. The host settles it immediately without touching
            /// `RunService`, so `alln doctor handoff` costs no quota and no seat —
            /// it answers the one question that matters (is anything out there
            /// claiming and journaling my requests?) in seconds.
            case ping
        }

        public var id: String
        public var runId: String
        public var message: String
        public var repoRoot: String
        public var presetId: String?
        public var workerId: String?
        public var createdAt: Date
        /// Absent in requests written before pings existed — decoded as `.run`.
        public var kind: Kind
        /// Set when a host outside the sandbox takes ownership. A request is
        /// claimed exactly once; a second claimer must skip it.
        public var claimedAt: Date?
        public var claimedBy: String?
        /// Identity of the claiming process, so a claim held by a host that has
        /// since died is detectable rather than permanent. `claimedBy` alone was
        /// the literal string "mac-app", which cannot be checked for liveness —
        /// a host that quit mid-request stranded its request forever.
        /// Opaque here: `AllnighterEngine` owns the liveness rule.
        public var claimantPid: Int32?
        public var claimantStartTimeTicks: Int64?

        public init(
            id: String = UUID().uuidString,
            runId: String,
            message: String,
            repoRoot: String,
            presetId: String? = nil,
            workerId: String? = nil,
            createdAt: Date = Date(),
            kind: Kind = .run,
            claimedAt: Date? = nil,
            claimedBy: String? = nil,
            claimantPid: Int32? = nil,
            claimantStartTimeTicks: Int64? = nil
        ) {
            self.id = id
            self.runId = runId
            self.message = message
            self.repoRoot = repoRoot
            self.presetId = presetId
            self.workerId = workerId
            self.createdAt = createdAt
            self.kind = kind
            self.claimedAt = claimedAt
            self.claimedBy = claimedBy
            self.claimantPid = claimantPid
            self.claimantStartTimeTicks = claimantStartTimeTicks
        }

        /// Hand-written so a request already sitting in the mailbox when this
        /// shipped — which has no `kind` key — still decodes, as `.run`. A
        /// request that fails to decode is a request that silently never runs.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            runId = try c.decode(String.self, forKey: .runId)
            message = try c.decode(String.self, forKey: .message)
            repoRoot = try c.decode(String.self, forKey: .repoRoot)
            presetId = try c.decodeIfPresent(String.self, forKey: .presetId)
            workerId = try c.decodeIfPresent(String.self, forKey: .workerId)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .run
            claimedAt = try c.decodeIfPresent(Date.self, forKey: .claimedAt)
            claimedBy = try c.decodeIfPresent(String.self, forKey: .claimedBy)
            claimantPid = try c.decodeIfPresent(Int32.self, forKey: .claimantPid)
            claimantStartTimeTicks = try c.decodeIfPresent(Int64.self, forKey: .claimantStartTimeTicks)
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
    ///
    /// One unreadable file must not hide the rest: this used to decode the whole
    /// directory with `try` inside a `map`, so a single corrupt or half-written
    /// entry threw and made the entire mailbox look empty — every other caller
    /// waiting behind it would be told nothing had picked their request up.
    public func unclaimed() throws -> [Request] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return files
            .compactMap { url -> Request? in
                guard let data = try? Data(contentsOf: url),
                      let request = try? CoreJSON.decode(Request.self, from: data)
                else { return nil }
                return request
            }
            .filter { $0.claimedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// One request by id, claimed or not — the difference between "nothing is
    /// listening" and "something took this and went quiet", which a caller must
    /// never guess at.
    public func request(id: String) -> Request? {
        let file = url(for: id)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? CoreJSON.decode(Request.self, from: data)
    }

    /// Takes ownership. Returns nil when someone else already claimed it, so two
    /// hosts can watch the same mailbox without double-running a request.
    public func claim(
        id: String,
        by owner: String,
        pid: Int32? = nil,
        startTimeTicks: Int64? = nil,
        now: Date = Date()
    ) throws -> Request? {
        let file = url(for: id)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        var request = try CoreJSON.decode(Request.self, from: Data(contentsOf: file))
        guard request.claimedAt == nil else { return nil }
        request.claimedAt = now
        request.claimedBy = owner
        request.claimantPid = pid
        request.claimantStartTimeTicks = startTimeTicks
        try CoreJSON.encode(request).write(to: file, options: .atomic)
        return request
    }

    /// Hands a request back to the mailbox. Used when the host that claimed it is
    /// gone: without this, a claim made by a process that then died is permanent —
    /// `unclaimed()` skips claimed entries forever and the waiting caller is told,
    /// wrongly, that nothing ever picked its work up.
    @discardableResult
    public func release(id: String) -> Bool {
        let file = url(for: id)
        guard let data = try? Data(contentsOf: file),
              var request = try? CoreJSON.decode(Request.self, from: data)
        else { return false }
        request.claimedAt = nil
        request.claimedBy = nil
        request.claimantPid = nil
        request.claimantStartTimeTicks = nil
        guard let encoded = try? CoreJSON.encode(request) else { return false }
        try? encoded.write(to: file, options: .atomic)
        return true
    }

    /// Every request currently claimed, so a host can check whether the claimant is
    /// still alive.
    public func claimed() throws -> [Request] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return files
            .compactMap { url -> Request? in
                guard let data = try? Data(contentsOf: url),
                      let request = try? CoreJSON.decode(Request.self, from: data)
                else { return nil }
                return request
            }
            .filter { $0.claimedAt != nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Removes a finished request. The run journal is the durable record; this
    /// mailbox holds no results of its own.
    public func remove(id: String) {
        try? fileManager.removeItem(at: url(for: id))
    }
}
