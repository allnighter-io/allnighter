import Foundation

// MARK: - Retrieval contracts (history / thread_status)

/// Local team-run history search results returned by `alln history --json` and the
/// MCP `history` tool. Wrapped (schemaVersion/contractVersion/query) for a stable,
/// schema-backed shape rather than a bare array (M-A).
public struct HistoryJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var query: String
    public var results: [RecallResult]

    public init(schemaVersion: Int = 1, contractVersion: String, query: String, results: [RecallResult]) {
        self.schemaVersion = schemaVersion; self.contractVersion = contractVersion
        self.query = query; self.results = results
    }
}

/// The running/attention state of a work thread, returned by `alln thread status
/// --json` and the MCP `thread_status` tool.
public struct ThreadStatusResponse: Codable, Sendable, Equatable {
    public var threadId: String
    public var isRunning: Bool
    public var needsAttention: Bool

    public init(threadId: String, isRunning: Bool, needsAttention: Bool) {
        self.threadId = threadId; self.isRunning = isRunning; self.needsAttention = needsAttention
    }
}
