import Foundation
import AllnighterCore

/// Durable on-disk record for a running `alln serve` process. Removed on clean
/// shutdown; a stale file with a dead pid reads as coordinator `unavailable`.
public struct ResidentCoordinatorRecord: Codable, Equatable, Sendable {
    public var coordinatorId: String
    public var pid: Int32
    public var startedAt: Date
    public var loopbackHost: String
    public var loopbackPort: UInt16
    public var binaryVersion: String
    public var contractVersion: String

    public init(
        coordinatorId: String,
        pid: Int32,
        startedAt: Date,
        loopbackHost: String,
        loopbackPort: UInt16,
        binaryVersion: String,
        contractVersion: String
    ) {
        self.coordinatorId = coordinatorId
        self.pid = pid
        self.startedAt = startedAt
        self.loopbackHost = loopbackHost
        self.loopbackPort = loopbackPort
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
    }
}

/// Reads/writes resident coordinator state under `AllnighterPaths.coordinator`.
public struct ResidentCoordinatorStore: Sendable {
    public let directory: URL
    public var stateFile: URL { directory.appendingPathComponent("coordinator.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? AllnighterPaths.coordinator
    }

    public func load() -> ResidentCoordinatorRecord? {
        guard let data = try? Data(contentsOf: stateFile),
              let record = try? CoreJSON.decode(ResidentCoordinatorRecord.self, from: data) else { return nil }
        return record
    }

    @discardableResult
    public func save(_ record: ResidentCoordinatorRecord) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(record).write(to: stateFile)
        return stateFile
    }

    public func clear() {
        try? FileManager.default.removeItem(at: stateFile)
    }
}
