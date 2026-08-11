import Foundation
import AllnighterCore

/// Machine-level receiver configuration for PM Turn wake delivery.
///
/// The command is intentionally a vector: PM turn JSON is streamed on stdin and
/// never interpolated into argv.
public struct PMTurnWakeConfiguration: Codable, Equatable, Sendable {
    public struct Wake: Codable, Equatable, Sendable {
        public var command: [String]
        /// Bounded retry window after the first failed hook invocation.
        public var retryMaxSeconds: Int

        public init(command: [String], retryMaxSeconds: Int = 300) {
            self.command = command
            self.retryMaxSeconds = retryMaxSeconds
        }
    }

    public var pmTurnWake: Wake?

    public init(pmTurnWake: Wake? = nil) {
        self.pmTurnWake = pmTurnWake
    }
}

public struct PMTurnWakeConfigurationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.config.appendingPathComponent("pm_turn_delivery.json")
    }

    public func load() -> PMTurnWakeConfiguration {
        guard let data = try? Data(contentsOf: fileURL),
              let configuration = try? CoreJSON.decode(PMTurnWakeConfiguration.self, from: data) else {
            return .init()
        }
        return configuration
    }

    @discardableResult
    public func save(_ configuration: PMTurnWakeConfiguration) throws -> URL {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CoreJSON.encode(configuration).write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func hasConfiguredCommand() -> Bool {
        guard let command = load().pmTurnWake?.command else { return false }
        return !command.isEmpty && !command[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Durable acknowledgement/retry state, keyed by the PM Turn's delivery key.
public struct PMTurnWakeReceiptLedger: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var kind: PMTurnJSON.Kind
        public var subjectId: String
        public var sequence: Int
        public var attempts: Int
        public var firstAttemptAt: Date
        public var lastAttemptAt: Date
        public var nextAttemptAt: Date?
        public var deliveredAt: Date?
        public var errorMessage: String?

        public init(
            kind: PMTurnJSON.Kind,
            subjectId: String,
            sequence: Int,
            attempts: Int,
            firstAttemptAt: Date,
            lastAttemptAt: Date,
            nextAttemptAt: Date? = nil,
            deliveredAt: Date? = nil,
            errorMessage: String? = nil
        ) {
            self.kind = kind
            self.subjectId = subjectId
            self.sequence = sequence
            self.attempts = attempts
            self.firstAttemptAt = firstAttemptAt
            self.lastAttemptAt = lastAttemptAt
            self.nextAttemptAt = nextAttemptAt
            self.deliveredAt = deliveredAt
            self.errorMessage = errorMessage
        }
    }

    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public static func key(kind: PMTurnJSON.Kind, subjectId: String, sequence: Int) -> String {
        "\(kind.rawValue):\(subjectId):\(sequence)"
    }
}

public struct PMTurnWakeReceiptLedgerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.coordinator.appendingPathComponent("pm_turn_wake_receipts.json")
    }

    public func load() -> PMTurnWakeReceiptLedger {
        guard let data = try? Data(contentsOf: fileURL),
              let ledger = try? CoreJSON.decode(PMTurnWakeReceiptLedger.self, from: data) else {
            return .init()
        }
        return ledger
    }

    @discardableResult
    public func save(_ ledger: PMTurnWakeReceiptLedger) throws -> URL {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CoreJSON.encode(ledger).write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func delivery(for turn: PMTurnJSON) -> PMTurnDeliveryJSON? {
        let key = PMTurnWakeReceiptLedger.key(
            kind: turn.kind, subjectId: turn.subjectId, sequence: turn.sequence)
        guard let entry = load().entries[key] else { return nil }
        if let deliveredAt = entry.deliveredAt {
            return .init(status: "delivered", attempts: entry.attempts, lastAttemptAt: deliveredAt)
        }
        let exhausted = entry.nextAttemptAt == nil
        return .init(
            status: exhausted ? "failed" : "retrying",
            attempts: entry.attempts,
            lastAttemptAt: entry.lastAttemptAt,
            nextAttemptAt: entry.nextAttemptAt,
            errorCode: "PM_TURN_WAKE_FAILED",
            errorMessage: entry.errorMessage
        )
    }
}

/// Read-only serve scheduler for the configured PM Turn receiver. Durable PM
/// turns are discovered directly from Runs/ and Relays/ so a crash between the
/// subject write and any higher-level index never loses a wake.
public struct PMTurnWakeScheduler: Sendable {
    public static let progressId = "pmTurnWake"

    public struct InvocationResult: Sendable, Equatable {
        public var succeeded: Bool
        public var message: String?

        public init(succeeded: Bool, message: String? = nil) {
            self.succeeded = succeeded
            self.message = message
        }
    }

    public typealias Invoker = @Sendable ([String], Data) -> InvocationResult

    public var runsRootDirectory: URL
    public var loopsRootDirectory: URL
    public var configurationStore: PMTurnWakeConfigurationStore
    public var ledgerStore: PMTurnWakeReceiptLedgerStore
    public var invoke: Invoker
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper
    public var pollInterval: TimeInterval
    public var progress: any SchedulerProgressReporting

    public init(
        runsRootDirectory: URL = AllnighterPaths.runs,
        loopsRootDirectory: URL = AllnighterPaths.loops,
        configurationStore: PMTurnWakeConfigurationStore = PMTurnWakeConfigurationStore(),
        ledgerStore: PMTurnWakeReceiptLedgerStore = PMTurnWakeReceiptLedgerStore(),
        invoke: Invoker? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        pollInterval: TimeInterval = 5,
        progress: any SchedulerProgressReporting = NoOpSchedulerProgress()
    ) {
        self.runsRootDirectory = runsRootDirectory
        self.loopsRootDirectory = loopsRootDirectory
        self.configurationStore = configurationStore
        self.ledgerStore = ledgerStore
        self.invoke = invoke ?? Self.invokeHook
        self.now = now
        self.sleeper = sleeper
        self.pollInterval = pollInterval
        self.progress = progress
    }

    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            progress.attempting(id: Self.progressId)
            tick()
            progress.succeeded(id: Self.progressId)
            let sleepUntil = now().addingTimeInterval(pollInterval)
            do {
                progress.waiting(id: Self.progressId, until: sleepUntil)
                try await sleeper.sleep(until: sleepUntil, jitterSeconds: 0)
            } catch {
                if error is CancellationError || isCancelled() {
                    progress.stopped(id: Self.progressId)
                } else {
                    progress.failed(
                        id: Self.progressId,
                        error: "pmTurnWake sleep failed: \(error.localizedDescription)"
                    )
                }
                break
            }
        }
    }

    /// One deterministic scan/attempt pass, exposed for hermetic tests.
    public func tick() {
        guard let wake = configurationStore.load().pmTurnWake,
              !wake.command.isEmpty,
              !wake.command[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let tickTime = now()
        var ledger = ledgerStore.load()
        var changed = false
        for turn in discoverTurns() {
            let key = PMTurnWakeReceiptLedger.key(
                kind: turn.kind, subjectId: turn.subjectId, sequence: turn.sequence)
            if let existing = ledger.entries[key] {
                if existing.deliveredAt != nil { continue }
                if let nextAttemptAt = existing.nextAttemptAt, nextAttemptAt > tickTime { continue }
                let deadline = existing.firstAttemptAt.addingTimeInterval(Double(max(0, wake.retryMaxSeconds)))
                if tickTime >= deadline {
                    var failed = existing
                    failed.nextAttemptAt = nil
                    ledger.entries[key] = failed
                    changed = true
                    continue
                }
            }

            let result = invoke(wake.command, (try? CoreJSON.encode(turn)) ?? Data())
            let previous = ledger.entries[key]
            let firstAttemptAt = previous?.firstAttemptAt ?? tickTime
            let attempts = (previous?.attempts ?? 0) + 1
            if result.succeeded {
                ledger.entries[key] = .init(
                    kind: turn.kind, subjectId: turn.subjectId, sequence: turn.sequence,
                    attempts: attempts, firstAttemptAt: firstAttemptAt, lastAttemptAt: tickTime,
                    deliveredAt: tickTime)
            } else {
                let deadline = firstAttemptAt.addingTimeInterval(Double(max(0, wake.retryMaxSeconds)))
                let backoff = min(60, pow(2, Double(max(0, attempts - 1))))
                let nextAttemptAt = tickTime.addingTimeInterval(backoff) < deadline
                    ? tickTime.addingTimeInterval(backoff) : nil
                ledger.entries[key] = .init(
                    kind: turn.kind, subjectId: turn.subjectId, sequence: turn.sequence,
                    attempts: attempts, firstAttemptAt: firstAttemptAt, lastAttemptAt: tickTime,
                    nextAttemptAt: nextAttemptAt, errorMessage: result.message ?? "wake hook exited non-zero")
            }
            changed = true
        }
        if changed { _ = try? ledgerStore.save(ledger) }
    }

    private func discoverTurns() -> [PMTurnJSON] {
        readTurns(in: runsRootDirectory, kind: .run, stripPrefix: "run_")
            + readTurns(in: loopsRootDirectory, kind: .relay, stripPrefix: nil)
    }

    private func readTurns(in root: URL, kind: PMTurnJSON.Kind, stripPrefix: String?) -> [PMTurnJSON] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return directories.compactMap { directory in
            let name = directory.lastPathComponent
            if let stripPrefix, !name.hasPrefix(stripPrefix) { return nil }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("pm-turn.json")),
                  let turn = try? CoreJSON.decode(PMTurnJSON.self, from: data),
                  turn.kind == kind else { return nil }
            return turn
        }
    }

    private static func invokeHook(command: [String], stdin: Data) -> InvocationResult {
        guard let executable = command.first, !executable.isEmpty else {
            return .init(succeeded: false, message: "wake command is empty")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            input.fileHandleForWriting.write(stdin)
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return .init(succeeded: false, message: "wake hook exited \(process.terminationStatus)")
            }
            return .init(succeeded: true)
        } catch {
            return .init(succeeded: false, message: "could not run wake hook: \(error)")
        }
    }
}
