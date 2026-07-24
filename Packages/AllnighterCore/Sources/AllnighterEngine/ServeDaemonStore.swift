import Foundation
import AllnighterCore

/// Durable on-disk record for a running `alln serve` process. Removed on clean
/// shutdown; a stale file with a dead pid reads as daemon `unavailable`.
public struct ServeDaemonRecord: Codable, Equatable, Sendable {
    public var daemonId: String
    public var pid: Int32
    public var startedAt: Date
    public var loopbackHost: String
    public var loopbackPort: UInt16
    public var binaryVersion: String
    public var binaryGitSha: String
    public var contractVersion: String

    public init(
        daemonId: String,
        pid: Int32,
        startedAt: Date,
        loopbackHost: String,
        loopbackPort: UInt16,
        binaryVersion: String,
        binaryGitSha: String = AllnighterBuildInfo.gitSha,
        contractVersion: String
    ) {
        self.daemonId = daemonId
        self.pid = pid
        self.startedAt = startedAt
        self.loopbackHost = loopbackHost
        self.loopbackPort = loopbackPort
        self.binaryVersion = binaryVersion
        self.binaryGitSha = binaryGitSha
        self.contractVersion = contractVersion
    }
}

/// Reads/writes `alln serve` daemon state under `AllnighterPaths.coordinator`.
public struct ServeDaemonStore: Sendable {
    public let directory: URL
    public var stateFile: URL { directory.appendingPathComponent("coordinator.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? AllnighterPaths.coordinator
    }

    public func load() -> ServeDaemonRecord? {
        guard let data = try? Data(contentsOf: stateFile),
              let record = try? CoreJSON.decode(ServeDaemonRecord.self, from: data) else { return nil }
        return record
    }

    @discardableResult
    public func save(_ record: ServeDaemonRecord) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(record).write(to: stateFile)
        return stateFile
    }

    public func clear() {
        try? FileManager.default.removeItem(at: stateFile)
    }
}
