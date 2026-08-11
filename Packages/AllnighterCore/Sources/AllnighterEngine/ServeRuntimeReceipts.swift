import Foundation
import AllnighterCore

public struct ServeRuntimeReceipts: Sendable {

    public enum SchedulerState: String, Codable, Sendable, Equatable {
        case registered
        case running
        case waiting
        case failed
    }

    public struct SchedulerRow: Codable, Equatable, Sendable {
        public var id: String
        public var state: SchedulerState
        public var lastAttemptAt: Date?
        public var lastSuccessAt: Date?
        public var lastError: String?
        public var nextWakeAt: Date?

        public init(
            id: String,
            state: SchedulerState,
            lastAttemptAt: Date? = nil,
            lastSuccessAt: Date? = nil,
            lastError: String? = nil,
            nextWakeAt: Date? = nil
        ) {
            self.id = id
            self.state = state
            self.lastAttemptAt = lastAttemptAt
            self.lastSuccessAt = lastSuccessAt
            self.lastError = lastError
            self.nextWakeAt = nextWakeAt
        }
    }

    public enum Reading: Equatable, Sendable {
        case absent
        case present(daemonId: String, pid: Int32, startedAt: Date, rows: [SchedulerRow])
        case unreadable(reason: String)
    }

    public struct Failure: Error, Equatable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    private struct Record: Codable {
        let schemaVersion: Int
        let daemonId: String
        let pid: Int32
        let startedAt: Date
        let schedulers: [SchedulerRow]
    }

    public static let requiredSchedulerIds: Set<String> = [
        "pendingWake",
        "pmTurnWake",
        "boostSeed",
        "vendorBackoff",
        "notifications",
        "capacityRefresh",
        "probeRecordRefresh",
    ]

    public static let optionalSchedulerIds: Set<String> = [
        "cloudRelay",
    ]

    private static let currentSchemaVersion = 1

    public let directory: URL
    private let clock: @Sendable () -> Date

    public var runtimeFile: URL {
        directory.appendingPathComponent("runtime.json")
    }

    public init(
        directory: URL? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory ?? AllnighterPaths.coordinator
        self.clock = clock
    }

    public func read(fileManager: FileManager = .default) -> Reading {
        let url = runtimeFile
        guard fileManager.fileExists(atPath: url.path) else {
            return .absent
        }
        guard let data = try? Data(contentsOf: url) else {
            return .unreadable(reason: "file exists but cannot be read")
        }
        guard let record = try? CoreJSON.decode(Record.self, from: data) else {
            return .unreadable(reason: "corrupt or truncated JSON")
        }
        guard record.schemaVersion <= Self.currentSchemaVersion else {
            return .unreadable(reason: "future schema version \(record.schemaVersion) > current \(Self.currentSchemaVersion)")
        }
        return .present(daemonId: record.daemonId, pid: record.pid, startedAt: record.startedAt, rows: record.schedulers)
    }

    public func write(
        daemonId: String,
        pid: Int32,
        startedAt: Date,
        rows: [SchedulerRow],
        fileManager: FileManager = .default
    ) -> Result<Void, Failure> {
        let url = runtimeFile
        let record = Record(
            schemaVersion: Self.currentSchemaVersion,
            daemonId: daemonId,
            pid: pid,
            startedAt: startedAt,
            schedulers: rows
        )
        let parent = url.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            return .failure(Failure(
                code: "SERVE_RUNTIME_RECEIPTS_WRITE_FAILED",
                message: "could not create directory \(parent.path): \(error.localizedDescription)"
            ))
        }

        let encoded: Data
        do {
            encoded = try CoreJSON.encode(record)
        } catch {
            return .failure(Failure(
                code: "SERVE_RUNTIME_RECEIPTS_WRITE_FAILED",
                message: "encoding failed: \(error.localizedDescription)"
            ))
        }

        let tempURL = parent.appendingPathComponent(".runtime.staging.\(UUID().uuidString)")
        do {
            try encoded.write(to: tempURL, options: .atomic)
        } catch {
            return .failure(Failure(
                code: "SERVE_RUNTIME_RECEIPTS_WRITE_FAILED",
                message: "temp write failed: \(error.localizedDescription)"
            ))
        }

        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItem(at: url, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return .failure(Failure(
                code: "SERVE_RUNTIME_RECEIPTS_WRITE_FAILED",
                message: "write to \(url.path) failed: \(error.localizedDescription)"
            ))
        }

        return .success(())
    }
}
