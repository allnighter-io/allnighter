import Foundation
import AllnighterCore

public enum SliceQueueStatus: String, Codable, Sendable, CaseIterable {
    case pending, running, passed, failed, escalated
}

public struct SliceQueueEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { packet.sliceId }
    public var packet: WorkSlicePacket
    public var status: SliceQueueStatus
    public var retries: Int
    public var parentRunId: String?
    public var childRunId: String?
    public var checkExitCode: Int32?
    public var lastStdoutTail: String?
    public var escalatedReason: String?
    /// `executor` when GLM passed the check; `planner` after planner takeover.
    public var resolvedBy: String?
    public var plannerRunId: String?

    public init(
        packet: WorkSlicePacket,
        status: SliceQueueStatus = .pending,
        retries: Int = 0,
        parentRunId: String? = nil,
        childRunId: String? = nil,
        checkExitCode: Int32? = nil,
        lastStdoutTail: String? = nil,
        escalatedReason: String? = nil,
        resolvedBy: String? = nil,
        plannerRunId: String? = nil
    ) {
        self.packet = packet
        self.status = status
        self.retries = retries
        self.parentRunId = parentRunId
        self.childRunId = childRunId
        self.checkExitCode = checkExitCode
        self.lastStdoutTail = lastStdoutTail
        self.escalatedReason = escalatedReason
        self.resolvedBy = resolvedBy
        self.plannerRunId = plannerRunId
    }
}

public struct SliceQueue: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var entries: [SliceQueueEntry]

    public init(schemaVersion: Int = 1, entries: [SliceQueueEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    public var nextPending: SliceQueueEntry? {
        entries.first { $0.status == .pending }
    }
}
