import Foundation

/// Typed result for `alln gc [--json]`. Every discovered run/relay directory is
/// classified exactly once; unreadable and removal-failed records are retained.
public struct OwnershipGarbageCollectionJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var retentionCount: Int
    public var consideredCount: Int
    public var prunedCount: Int
    public var keptCount: Int
    public var pruned: [OwnershipGarbageCollectionRecordJSON]
    public var keptAlive: [OwnershipGarbageCollectionRecordJSON]
    public var keptNonTerminal: [OwnershipGarbageCollectionRecordJSON]
    public var keptWithinRetention: [OwnershipGarbageCollectionRecordJSON]
    public var keptThreadReferenced: [OwnershipGarbageCollectionRecordJSON]
    public var keptUnreadable: [OwnershipGarbageCollectionRecordJSON]
    public var keptRemovalFailed: [OwnershipGarbageCollectionRecordJSON]

    public init(
        schemaVersion: Int = 1,
        retentionCount: Int,
        pruned: [OwnershipGarbageCollectionRecordJSON] = [],
        keptAlive: [OwnershipGarbageCollectionRecordJSON] = [],
        keptNonTerminal: [OwnershipGarbageCollectionRecordJSON] = [],
        keptWithinRetention: [OwnershipGarbageCollectionRecordJSON] = [],
        keptThreadReferenced: [OwnershipGarbageCollectionRecordJSON] = [],
        keptUnreadable: [OwnershipGarbageCollectionRecordJSON] = [],
        keptRemovalFailed: [OwnershipGarbageCollectionRecordJSON] = []
    ) {
        self.schemaVersion = schemaVersion
        self.retentionCount = retentionCount
        self.pruned = pruned
        self.keptAlive = keptAlive
        self.keptNonTerminal = keptNonTerminal
        self.keptWithinRetention = keptWithinRetention
        self.keptThreadReferenced = keptThreadReferenced
        self.keptUnreadable = keptUnreadable
        self.keptRemovalFailed = keptRemovalFailed
        prunedCount = pruned.count
        keptCount = keptAlive.count + keptNonTerminal.count + keptWithinRetention.count
            + keptThreadReferenced.count + keptUnreadable.count + keptRemovalFailed.count
        consideredCount = prunedCount + keptCount
    }
}

public struct OwnershipGarbageCollectionRecordJSON: Codable, Sendable, Equatable {
    public var id: String
    /// `run` | `relay` | `pilot`
    public var kind: String
    public var createdAt: Date?
    public var status: String?
    /// Present only for unreadable or removal-failed records.
    public var detail: String?

    public init(
        id: String,
        kind: String,
        createdAt: Date? = nil,
        status: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.status = status
        self.detail = detail
    }
}
