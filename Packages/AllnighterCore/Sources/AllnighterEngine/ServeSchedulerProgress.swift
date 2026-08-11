import Foundation
import AllnighterCore

/// Narrow progress surface schedulers depend on instead of `runtime.json`.
public protocol SchedulerProgressReporting: Sendable {
    func registered(id: String)
    func attempting(id: String)
    func succeeded(id: String)
    func failed(id: String, error: String)
    func waiting(id: String, until: Date)
}

/// No-op reporter so unwired schedulers and existing construction sites compile unchanged.
public struct NoOpSchedulerProgress: SchedulerProgressReporting {
    public init() {}

    public func registered(id: String) {}
    public func attempting(id: String) {}
    public func succeeded(id: String) {}
    public func failed(id: String, error: String) {}
    public func waiting(id: String, until: Date) {}
}

/// Single serialized owner of the scheduler row set. Holds rows in memory and
/// persists the whole set through `ServeRuntimeReceipts.write` on every mutation.
public final class ServeSchedulerProgress: SchedulerProgressReporting, @unchecked Sendable {
    public static let maxErrorLength = 200

    private let receipts: ServeRuntimeReceipts
    private let daemonId: String
    private let pid: Int32
    private let startedAt: Date
    private let clock: @Sendable () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()
    private var rowsById: [String: ServeRuntimeReceipts.SchedulerRow] = [:]

    public init(
        receipts: ServeRuntimeReceipts,
        daemonId: String,
        pid: Int32,
        startedAt: Date,
        clock: @escaping @Sendable () -> Date = { Date() },
        fileManager: FileManager = .default
    ) {
        self.receipts = receipts
        self.daemonId = daemonId
        self.pid = pid
        self.startedAt = startedAt
        self.clock = clock
        self.fileManager = fileManager
    }

    public func registered(id: String) {
        mutate(id: id) { row in
            row.state = .registered
        }
    }

    public func attempting(id: String) {
        let at = clock()
        mutate(id: id) { row in
            row.state = .running
            row.lastAttemptAt = at
        }
    }

    public func succeeded(id: String) {
        let at = clock()
        mutate(id: id) { row in
            row.state = .running
            row.lastSuccessAt = at
            row.lastError = nil
        }
    }

    public func failed(id: String, error: String) {
        mutate(id: id) { row in
            row.state = .failed
            row.lastError = Self.boundedError(error)
        }
    }

    public func waiting(id: String, until: Date) {
        mutate(id: id) { row in
            row.state = .waiting
            row.nextWakeAt = until
        }
    }

    private func mutate(
        id: String,
        update: (inout ServeRuntimeReceipts.SchedulerRow) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        var row = rowsById[id] ?? ServeRuntimeReceipts.SchedulerRow(id: id, state: .registered)
        update(&row)
        rowsById[id] = row
        let rows = rowsById.values.sorted { $0.id < $1.id }
        // Recording failure must never become a scheduling failure.
        _ = receipts.write(
            daemonId: daemonId,
            pid: pid,
            startedAt: startedAt,
            rows: rows,
            fileManager: fileManager
        )
    }

    private static func boundedError(_ error: String) -> String {
        guard error.count > maxErrorLength else { return error }
        return String(error.prefix(maxErrorLength))
    }
}
