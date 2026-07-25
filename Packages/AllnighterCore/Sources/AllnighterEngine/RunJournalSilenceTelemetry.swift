import Foundation
import AgentOSTeam
import AllnighterCore

/// Mines durable run journals for idle-timeout (`timeoutKind: idle` / `RunClockKind.idle`)
/// events into per-driver silence-duration histograms (IDLE-HF-S04 telemetry).
public enum RunJournalSilenceTelemetry {

    public struct Bucket: Codable, Sendable, Equatable {
        public var label: String
        public var count: Int

        public init(label: String, count: Int) {
            self.label = label
            self.count = count
        }
    }

    public struct DriverHistogram: Codable, Sendable, Equatable {
        public var driverId: String
        public var idleTimeoutCount: Int
        public var buckets: [Bucket]

        public init(driverId: String, idleTimeoutCount: Int, buckets: [Bucket]) {
            self.driverId = driverId
            self.idleTimeoutCount = idleTimeoutCount
            self.buckets = buckets
        }
    }

    public struct Report: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var scannedRuns: Int
        public var idleTimeoutCount: Int
        public var byDriver: [DriverHistogram]

        public init(
            schemaVersion: Int = 1,
            scannedRuns: Int,
            idleTimeoutCount: Int,
            byDriver: [DriverHistogram]
        ) {
            self.schemaVersion = schemaVersion
            self.scannedRuns = scannedRuns
            self.idleTimeoutCount = idleTimeoutCount
            self.byDriver = byDriver
        }
    }

    /// Standard silence-duration buckets (seconds) for field histograms.
    public static let bucketUpperBounds: [Int] = [60, 300, 600, 1800]

    public static func bucketLabel(for silenceSeconds: Int) -> String {
        for bound in bucketUpperBounds {
            if silenceSeconds <= bound { return "0-\(bound)" }
        }
        return "1800+"
    }

    /// Scan every `run_*` journal under `runStore` and classify idle timeouts.
    public static func mine(
        runStore: RunStore,
        models: [Model] = [],
        now: Date = Date()
    ) -> Report {
        _ = models
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runStore.rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return Report(scannedRuns: 0, idleTimeoutCount: 0, byDriver: [])
        }

        var scanned = 0
        var perDriver: [String: [Int]] = [:]

        for dir in entries where dir.lastPathComponent.hasPrefix("run_") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("run.json")),
                  let run = try? CoreJSON.decode(TeamRun.self, from: data) else {
                continue
            }
            scanned += 1
            guard run.status.isTerminal, run.endReason == .timedOut else { continue }
            guard let sample = classifyIdleTimeout(run: run, now: now) else { continue }
            perDriver[sample.driverId, default: []].append(sample.silenceSeconds)
        }

        let driverIds = perDriver.keys.sorted()
        let histograms = driverIds.map { driverId -> DriverHistogram in
            let durations = perDriver[driverId] ?? []
            var counts: [String: Int] = [:]
            for seconds in durations {
                let label = bucketLabel(for: seconds)
                counts[label, default: 0] += 1
            }
            let buckets = (counts.keys.sorted { lhs, rhs in
                let li = bucketSortIndex(lhs)
                let ri = bucketSortIndex(rhs)
                return li < ri
            }).map { Bucket(label: $0, count: counts[$0] ?? 0) }
            return DriverHistogram(
                driverId: driverId,
                idleTimeoutCount: durations.count,
                buckets: buckets
            )
        }

        let totalIdle = histograms.reduce(0) { $0 + $1.idleTimeoutCount }
        return Report(scannedRuns: scanned, idleTimeoutCount: totalIdle, byDriver: histograms)
    }

    public struct IdleTimeoutSample: Equatable {
        var driverId: String
        var silenceSeconds: Int
    }

    /// Returns a sample when the journal records (or reconstructs) an idle clock fire.
    public static func classifyIdleTimeout(
        run: TeamRun,
        now: Date = Date()
    ) -> IdleTimeoutSample? {
        guard run.status.isTerminal, run.endReason == .timedOut else { return nil }

        let driver = resolvedDriverId(run: run)
        let terminalAt = terminalTimestamp(run: run) ?? now
        let budgets = run.clockBudgets ?? RunClockBudgets()
        let idleBudget = budgets.idleTimeoutSeconds

        let spawnIdle = run.workerAnswers.contains {
            $0.result.status == .timedOut
                && $0.result.spawnDiagnostics?.timeoutKind == .idle
        }

        let reconstructed = RunClockEnforcer.evaluate(
            budgets: budgets,
            createdAt: run.createdAt,
            lastActivityAt: run.lastActivityAt,
            now: terminalAt,
            lifecycle: .running,
            phase: .working,
            idleBudgetSeconds: idleBudget
        )

        guard spawnIdle || reconstructed == .idle else { return nil }

        let silenceBase = run.lastActivityAt ?? run.createdAt
        let silenceSeconds = max(0, Int(terminalAt.timeIntervalSince(silenceBase).rounded()))
        return IdleTimeoutSample(driverId: driver, silenceSeconds: silenceSeconds)
    }

    private static func resolvedDriverId(run: TeamRun) -> String {
        if let source = run.executionSourceId, !source.isEmpty { return source }
        if let worker = run.workers.first { return worker.modelId }
        if let answer = run.workerAnswers.first { return answer.modelId }
        return "unknown"
    }

    private static func terminalTimestamp(run: TeamRun) -> Date? {
        if let event = run.timing?.event(named: RunTimingKey.runOutcomePersisted) {
            return event.at
        }
        if let event = run.timing?.event(named: RunTimingKey.processExit) {
            return event.at
        }
        for attempt in run.attempts.reversed() {
            if let ended = attempt.endedAt { return ended }
        }
        return nil
    }

    private static func bucketSortIndex(_ label: String) -> Int {
        if label == "1800+" { return bucketUpperBounds.count }
        if let dash = label.firstIndex(of: "-") {
            let upper = label[label.index(after: dash)...]
            if let value = Int(upper) {
                return bucketUpperBounds.firstIndex(of: value) ?? bucketUpperBounds.count
            }
        }
        return bucketUpperBounds.count + 1
    }
}
