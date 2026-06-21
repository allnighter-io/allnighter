import Foundation
import AllnighterCore

public enum RemoteMacAgentEventCursorStoreError: Error, Equatable, Sendable {
    case corruptCursor(String)
}

public struct RemoteMacAgentEventCursorStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.coordinator.appendingPathComponent(
            "remote_event_publish_cursor.json"
        )
    }

    public func load() throws -> Int64 {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
        let data = try Data(contentsOf: fileURL)
        let state = try CoreJSON.decode(State.self, from: data)
        guard state.lastPublishedSeq >= 0 else {
            throw RemoteMacAgentEventCursorStoreError.corruptCursor(String(state.lastPublishedSeq))
        }
        return state.lastPublishedSeq
    }

    public func save(_ seq: Int64) throws {
        guard seq >= 0 else {
            throw RemoteMacAgentEventCursorStoreError.corruptCursor(String(seq))
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lock = try ThreadFlockLock.acquire(lockURL: lockURL)
        defer { _ = lock }
        try CoreJSON.encode(State(lastPublishedSeq: seq)).write(to: fileURL, options: .atomic)
    }

    private var lockURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).lock")
    }

    private struct State: Codable, Equatable, Sendable {
        var lastPublishedSeq: Int64
    }
}

public struct RemoteMacAgentEventSyncResult: Equatable, Sendable {
    public var publishedEventCount: Int
    public var lastPublishedSeq: Int64
    public var journalLastSeq: Int64

    public init(publishedEventCount: Int, lastPublishedSeq: Int64, journalLastSeq: Int64) {
        self.publishedEventCount = publishedEventCount
        self.lastPublishedSeq = lastPublishedSeq
        self.journalLastSeq = journalLastSeq
    }
}

public struct RemoteMacAgentEventSync: Sendable {
    public let publisher: RemoteRunEventPublisher
    public let cursorStore: RemoteMacAgentEventCursorStore

    public init(
        publisher: RemoteRunEventPublisher,
        cursorStore: RemoteMacAgentEventCursorStore = RemoteMacAgentEventCursorStore()
    ) {
        self.publisher = publisher
        self.cursorStore = cursorStore
    }

    public func publishNewEvents() async throws -> RemoteMacAgentEventSyncResult {
        let previousSeq = try cursorStore.load()
        let result = try await publisher.publish(after: previousSeq)
        let lastPublishedSeq = result.lastPublishedSeq ?? previousSeq
        if lastPublishedSeq > previousSeq {
            try cursorStore.save(lastPublishedSeq)
        }
        return RemoteMacAgentEventSyncResult(
            publishedEventCount: result.publishedEventCount,
            lastPublishedSeq: lastPublishedSeq,
            journalLastSeq: result.lastSeq
        )
    }
}
