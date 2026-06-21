import Foundation

/// How a driver can carry conversation continuity across turns in one Allnighter thread.
public enum ContinuityTier: String, Codable, Sendable, CaseIterable {
    /// The CLI exposes a real resume-by-id handle (claude/cursor/codex/grok). We piggyback
    /// on ONE vendor session per thread; resumed turns send only the new prompt.
    case vendorSession
    /// No usable headless session id (antigravity v1) — continuity is a bounded
    /// `ThreadContextBuilder` packet attached each turn. Honest, lossy, never a fake id.
    case promptContextOnly
    /// The driver promises no continuity at all.
    case unsupported
}

/// The durable mapping from a visible Allnighter conversation to the worker CLI's OWN
/// session, so turn 2 resumes turn 1 instead of spawning a fresh, amnesiac process.
///
/// Keyed by `threadId + sourceId + modelId + repoRoot`: one vendor session per
/// (thread, source, model) in a repo. A model switch within a thread forks a new record
/// (a new vendor session on the CLI side); switching back resumes the prior one if valid.
public struct ExternalWorkerSession: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable { case active, stale, invalidated }

    /// Alln-local record id (NOT the vendor id).
    public var id: String
    public var threadId: String
    /// Driver source — `claude_code` | `cursor_agent` | `codex` | `grok` | `antigravity`.
    public var sourceId: String
    public var modelId: String
    public var repoRoot: String
    /// The CLI's own chat/session/conversation id we resume with. Empty for
    /// `promptContextOnly`/`unsupported` records (no vendor id exists).
    public var vendorSessionId: String
    public var continuityTier: ContinuityTier
    public var createdAt: Date
    public var lastUsedAt: Date
    public var lastRunId: String?
    public var status: Status

    public init(
        id: String = UUID().uuidString,
        threadId: String,
        sourceId: String,
        modelId: String,
        repoRoot: String,
        vendorSessionId: String,
        continuityTier: ContinuityTier,
        createdAt: Date,
        lastUsedAt: Date,
        lastRunId: String? = nil,
        status: Status = .active
    ) {
        self.id = id
        self.threadId = threadId
        self.sourceId = sourceId
        self.modelId = modelId
        self.repoRoot = repoRoot
        self.vendorSessionId = vendorSessionId
        self.continuityTier = continuityTier
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastRunId = lastRunId
        self.status = status
    }

    /// The composite identity two turns must share to count as the same conversation.
    public struct Key: Hashable, Sendable {
        public let threadId: String
        public let sourceId: String
        public let modelId: String
        public let repoRoot: String
        public init(threadId: String, sourceId: String, modelId: String, repoRoot: String) {
            self.threadId = threadId
            self.sourceId = sourceId
            self.modelId = modelId
            self.repoRoot = repoRoot
        }
    }

    public var key: Key {
        Key(threadId: threadId, sourceId: sourceId, modelId: modelId, repoRoot: repoRoot)
    }

    public func matches(_ key: Key) -> Bool { self.key == key }

    /// A live `vendorSession` record we can actually resume (has an id, not invalidated).
    public var isResumable: Bool {
        continuityTier == .vendorSession && status == .active && !vendorSessionId.isEmpty
    }
}

/// Agent-facing return for `alln sessions` / the `worker_sessions_list` MCP tool: the vendor
/// CLI sessions a thread is piggybacking, so an agent can SEE/verify continuity. ONE
/// contract — CLI, MCP, and the GUI present this.
public struct WorkerSessionsJSON: Codable, Sendable, Equatable {
    public let threadId: String?
    public let sessions: [ExternalWorkerSession]

    public init(threadId: String?, sessions: [ExternalWorkerSession]) {
        self.threadId = threadId
        self.sessions = sessions.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
}
