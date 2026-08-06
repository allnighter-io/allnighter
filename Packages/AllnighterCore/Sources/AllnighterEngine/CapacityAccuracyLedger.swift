import AllnighterCore
import Foundation

/// Append-only record of what the capacity strip actually showed, so the
/// Capacity Warm Bench trust gate's "accuracy dogfood ledger" row has evidence
/// instead of recollection.
///
/// The gate cannot be passed by a test suite — its rows are lifecycle facts
/// observed over hours. But an unrecorded observation is not evidence either,
/// and "I think it looked right" is exactly the standard the gate exists to
/// replace. This writes one line per acquisition so accuracy can be audited
/// after the fact.
///
/// Deliberately NOT a verdict: it records what was displayed and when. Whether
/// that matched the vendor's own UI is a human comparison, added later against
/// these rows. Nothing here judges its own accuracy — that is the mistake the
/// OpenCode Go qualification ledger was built to avoid.
public enum CapacityAccuracyLedger {

    /// One observation of one seat, as displayed.
    public struct Entry: Codable, Equatable, Sendable {
        public let observedAt: Date
        public let source: String
        public let scope: String
        /// Nil when the seat was unknown — never a zero standing in for absence.
        public let remainingPercent: Double?
        /// Present only when the value was unknown; names why.
        public let unknownReason: String?
        public let tier: String
        /// What caused this acquisition — schedule, explicit refresh, launch.
        public let trigger: String

        public init(
            observedAt: Date, source: String, scope: String,
            remainingPercent: Double?, unknownReason: String?,
            tier: String, trigger: String
        ) {
            self.observedAt = observedAt
            self.source = source
            self.scope = scope
            self.remainingPercent = remainingPercent
            self.unknownReason = unknownReason
            self.tier = tier
            self.trigger = trigger
        }
    }

    /// Where entries go. Injectable so tests never write to the real ledger.
    public protocol Sink: Sendable {
        func append(_ entries: [Entry])
    }

    public struct FileSink: Sink {
        public let url: URL

        public init(url: URL = CapacityAccuracyLedger.defaultURL) {
            self.url = url
        }

        public func append(_ entries: [Entry]) {
            // Backstop, deliberately redundant with sink injection. Injection
            // only protects tests that remember to inject; one that forgets
            // would quietly fabricate rows in the founder's real evidence file.
            // That is not hypothetical — it happened to the OpenCode Go
            // qualification ledger, which accumulated 45 fake successes before
            // anyone noticed. Do not delete this as redundant.
            guard !CapacityAccuracyLedger.isRunningUnderTestRunner else { return }
            CapacityAccuracyLedger.write(entries, to: url)
        }
    }

    public static var defaultURL: URL {
        AllnighterPaths.support
            .appendingPathComponent("Capacity", isDirectory: true)
            .appendingPathComponent("accuracy.jsonl")
    }

    /// Several signals, because no single one covers every runner: Xcode sets
    /// `XCTestConfigurationFilePath`, but a plain `swift test` on macOS sets
    /// neither XCTest env var and is only identifiable by its `.xctest` bundle.
    static var isRunningUnderTestRunner: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        if env["SWIFT_TESTING_ENABLED"] != nil { return true }
        if Bundle.main.bundlePath.contains(".xctest") { return true }
        if ProcessInfo.processInfo.arguments.first?.contains(".xctest") == true { return true }
        return false
    }

    /// Project a settled acquisition into ledger entries.
    ///
    /// Pure — no IO, no `Date()` — so the projection is testable without
    /// touching a filesystem or a clock.
    public static func entries(
        from windows: [CapacityWindow], trigger: String
    ) -> [Entry] {
        windows.map { w in
            Entry(
                observedAt: w.observedAt,
                source: w.source,
                scope: String(describing: w.scope),
                remainingPercent: w.remainingPercent,
                unknownReason: w.unknownReason.map { String(describing: $0) },
                tier: String(describing: w.sourceTier),
                trigger: trigger
            )
        }
    }

    static func write(_ entries: [Entry], to url: URL) {
        guard !entries.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var blob = Data()
            for entry in entries {
                blob.append(try encoder.encode(entry))
                blob.append(0x0A)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: blob)
            } else {
                try blob.write(to: url)
            }
        } catch {
            // Best-effort evidence — never block the capacity strip on it.
        }
    }
}
