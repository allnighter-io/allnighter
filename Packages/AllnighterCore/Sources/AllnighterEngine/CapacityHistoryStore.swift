import Foundation
import AllnighterCore

// MARK: - CapacityWindowRecord

/// One durable capacity window — peak usage facts for a single logical limit cycle.
///
/// Identity is `(sourceId, scope, resetAt ± tolerance)`, not the exact vendor
/// `resets_at`. Codex re-bases its weekly clock by seconds within a cycle; keying
/// on exact timestamps would shatter one window into many and destroy averages.
///
/// Peaks and counts are **monotone**: `peakUsedPercent` and `observationCount`
/// only rise; `lastObservedAt` only moves forward. Merge is therefore `max`/`+`,
/// never overwrite. A lost update under a concurrent writer loses at most a
/// slightly higher peak; the next observation heals it. Writes use atomic
/// replace (temp + rename) rather than a cross-process lock.
///
/// Closed is derived at read time (`resetAt <= now`) — never stored as a bool
/// that can go stale. Coverage filtering and averages live in later projections;
/// this record stores only raw facts.
///
/// Never carries account emails, org names, session ids, or raw vendor text.
public struct CapacityWindowRecord: Codable, Sendable, Equatable {
    public let sourceId: String
    public let scope: CapacityWindowScope
    public let resetAt: Date
    public let resetPrecision: CapacityResetPrecision
    public let peakUsedPercent: Double
    public let firstObservedAt: Date
    public let lastObservedAt: Date
    public let observationCount: Int
    public let planTier: String?
    public let poolLabel: String?

    public init(
        sourceId: String,
        scope: CapacityWindowScope,
        resetAt: Date,
        resetPrecision: CapacityResetPrecision,
        peakUsedPercent: Double,
        firstObservedAt: Date,
        lastObservedAt: Date,
        observationCount: Int,
        planTier: String? = nil,
        poolLabel: String? = nil
    ) {
        self.sourceId = sourceId
        self.scope = scope
        self.resetAt = resetAt
        self.resetPrecision = resetPrecision
        self.peakUsedPercent = peakUsedPercent
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
        self.observationCount = observationCount
        self.planTier = planTier
        self.poolLabel = poolLabel
    }

    /// Whether this window has already reset at `now`. Derived — not stored.
    public func isClosed(at now: Date) -> Bool {
        resetAt <= now
    }
}

// MARK: - CapacityHistoryStore

/// Durable per-window capacity history under `AllnighterPaths.capacity`.
///
/// One JSON file per source (`Capacity/<sourceId>.json`). Acquisition is
/// per-source, so concurrent writers usually touch different files. Recording
/// never probes, spawns, or scans a vendor directory — it only persists windows
/// the caller already holds.
///
/// Load is fail-soft (missing/corrupt → empty, never throws). No wall-clock
/// reads: callers pass `now` and every observation timestamp.
public struct CapacityHistoryStore: Sendable {

    /// Codex intra-cycle `resets_at` drift is seconds; inter-cycle gap is days.
    /// Fifteen minutes is the named merge window for one logical cycle.
    public static let resetAtMergeTolerance: TimeInterval = 15 * 60

    public static let currentSchemaVersion = 1

    public let rootDirectory: URL

    public init(rootDirectory: URL = AllnighterPaths.capacity) {
        self.rootDirectory = rootDirectory
    }

    /// File for one source. Injectable root keeps tests off real Application Support.
    public func fileURL(sourceId: String) -> URL {
        rootDirectory.appendingPathComponent("\(Self.safeFileStem(sourceId)).json")
    }

    /// Records newest-first. Missing or unreadable file → empty, never throws.
    public func load(sourceId: String) -> [CapacityWindowRecord] {
        let url = fileURL(sourceId: sourceId)
        guard let data = try? Data(contentsOf: url),
              let file = try? CoreJSON.decode(FilePayload.self, from: data)
        else { return [] }
        return file.windows.sorted(by: Self.newestFirst)
    }

    /// Merge known windows into durable history. Skips `unknown` and windows
    /// without a used-% or `resetAt` (identity requires a reset boundary).
    /// Never acquires capacity — caller supplies what is already known.
    public func record(_ windows: [CapacityWindow], now: Date) throws {
        // `now` is part of the no-clock-reads contract; observation times come
        // from each window. Reserved for future retention policy.
        _ = now

        let recordable = windows.compactMap(Self.seed(from:))
        guard !recordable.isEmpty else { return }

        let bySource = Dictionary(grouping: recordable, by: \.sourceId)
        for (sourceId, seeds) in bySource {
            try mergeAndWrite(sourceId: sourceId, seeds: seeds)
        }
    }

    // MARK: - Merge

    private func mergeAndWrite(sourceId: String, seeds: [CapacityWindowRecord]) throws {
        var existing = load(sourceId: sourceId)
        for seed in seeds {
            if let index = existing.firstIndex(where: { Self.sameWindow($0, as: seed) }) {
                existing[index] = Self.merge(existing: existing[index], incoming: seed)
            } else {
                existing.append(seed)
            }
        }
        existing.sort(by: Self.newestFirst)
        try write(sourceId: sourceId, windows: existing)
    }

    private func write(sourceId: String, windows: [CapacityWindowRecord]) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let payload = FilePayload(schemaVersion: Self.currentSchemaVersion, windows: windows)
        try CoreJSON.encode(payload).write(to: fileURL(sourceId: sourceId), options: .atomic)
    }

    /// Same logical window: matching source + scope and `resetAt` within tolerance.
    private static func sameWindow(_ a: CapacityWindowRecord, as b: CapacityWindowRecord) -> Bool {
        a.sourceId == b.sourceId
            && a.scope == b.scope
            && abs(a.resetAt.timeIntervalSince(b.resetAt)) <= resetAtMergeTolerance
    }

    /// Monotone merge: peaks and counts only rise; last observation only advances.
    private static func merge(
        existing: CapacityWindowRecord,
        incoming: CapacityWindowRecord
    ) -> CapacityWindowRecord {
        let laterIsIncoming = incoming.lastObservedAt >= existing.lastObservedAt
        return CapacityWindowRecord(
            sourceId: existing.sourceId,
            scope: existing.scope,
            // Keep the first-seen reset as the stable identity anchor.
            resetAt: existing.resetAt,
            resetPrecision: laterIsIncoming ? incoming.resetPrecision : existing.resetPrecision,
            peakUsedPercent: max(existing.peakUsedPercent, incoming.peakUsedPercent),
            firstObservedAt: min(existing.firstObservedAt, incoming.firstObservedAt),
            lastObservedAt: max(existing.lastObservedAt, incoming.lastObservedAt),
            observationCount: existing.observationCount + incoming.observationCount,
            planTier: laterIsIncoming
                ? (incoming.planTier ?? existing.planTier)
                : (existing.planTier ?? incoming.planTier),
            poolLabel: laterIsIncoming
                ? (incoming.poolLabel ?? existing.poolLabel)
                : (existing.poolLabel ?? incoming.poolLabel)
        )
    }

    private static func seed(from window: CapacityWindow) -> CapacityWindowRecord? {
        // Unknown must never become a stored 0%. Missing used-% or resetAt is not a window.
        guard window.unknownReason == nil,
              let used = window.usedPercent,
              let resetAt = window.resetAt
        else { return nil }

        return CapacityWindowRecord(
            sourceId: window.source,
            scope: window.scope,
            resetAt: resetAt,
            resetPrecision: window.resetPrecision,
            peakUsedPercent: used,
            firstObservedAt: window.observedAt,
            lastObservedAt: window.observedAt,
            observationCount: 1,
            planTier: window.planTier,
            poolLabel: window.poolLabel
        )
    }

    private static func newestFirst(_ a: CapacityWindowRecord, _ b: CapacityWindowRecord) -> Bool {
        if a.resetAt != b.resetAt { return a.resetAt > b.resetAt }
        return a.lastObservedAt > b.lastObservedAt
    }

    private static func safeFileStem(_ sourceId: String) -> String {
        let trimmed = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "_empty" }
        return trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "_")
    }

    // MARK: - File envelope

    private struct FilePayload: Codable, Sendable, Equatable {
        var schemaVersion: Int
        var windows: [CapacityWindowRecord]
    }
}
