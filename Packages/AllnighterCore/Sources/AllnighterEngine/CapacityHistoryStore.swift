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
    /// Usage as of `lastObservedAt` — the CURRENT reading, as opposed to
    /// `peakUsedPercent` which is the monotone high-water mark for the window.
    ///
    /// These are different questions and used to share one answer. The merge
    /// pairs the highest peak ever seen with the newest observation time, so
    /// hydrating `peakUsedPercent` for display reported "80% used, observed just
    /// now" after a real 50% sample. Correct as peak accounting, wrong as
    /// current accounting — and current is what a bench decision is made on.
    ///
    /// Optional so records written before this field decode unchanged; readers
    /// fall back to the peak, which is the old behavior.
    public let lastUsedPercent: Double?
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
        lastUsedPercent: Double? = nil,
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
        self.lastUsedPercent = lastUsedPercent
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

    /// v2 adds `poolLabel` to window identity. v1 files were written with
    /// pool-collapsed records (a merged peak under a borrowed label) — that
    /// damage cannot be unmixed after the fact, so v1 payloads are discarded
    /// on read rather than migrated into a wrong-looking v2.
    public static let currentSchemaVersion = 2

    public let rootDirectory: URL

    public init(rootDirectory: URL = AllnighterPaths.capacity) {
        self.rootDirectory = rootDirectory
    }

    /// File for one source. Injectable root keeps tests off real Application Support.
    public func fileURL(sourceId: String) -> URL {
        rootDirectory.appendingPathComponent("\(Self.safeFileStem(sourceId)).json")
    }

    /// Records newest-first. Missing, unreadable, or pre-`currentSchemaVersion`
    /// file → empty, never throws. Dropping an older payload costs one refresh;
    /// keeping it would serve a known-wrong number as last-known truth.
    ///
    /// Claude primary weekly aliases (`allmodels` / `all models`) are collapsed to
    /// unlabeled and same-identity duplicates are merged on read so a one-shot
    /// bad parse cannot keep a phantom pool alive across bare hydrates.
    public func load(sourceId: String) -> [CapacityWindowRecord] {
        let url = fileURL(sourceId: sourceId)
        guard let data = try? Data(contentsOf: url),
              let file = try? CoreJSON.decode(FilePayload.self, from: data),
              file.schemaVersion >= Self.currentSchemaVersion
        else { return [] }
        return Self.dedupeCanonical(file.windows).sorted(by: Self.newestFirst)
    }

    /// Open last-known windows for strip hydrate (CAP-HF-00).
    ///
    /// Projects durable peak facts into `CapacityWindow` with `lastObservedAt` as
    /// `observedAt` so age stays honest. Closed cycles (`resetAt <= now`) are
    /// dropped. Never probes, never invents a sample without a stored record.
    public func lastKnownWindows(
        sourceIds: [String] = CapacityAcquisition.benchSourceOrder,
        now: Date
    ) -> [CapacityWindow] {
        var out: [CapacityWindow] = []
        for sourceId in sourceIds {
            for record in load(sourceId: sourceId) where !record.isClosed(at: now) {
                out.append(record.asCapacityWindow())
            }
        }
        return out
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
        // Re-canonicalize on write so a prior parse that stored Claude's primary
        // weekly as `poolLabel: "allmodels"` merges into the unlabeled primary
        // and never re-escapes on bare hydrate.
        var existing = load(sourceId: sourceId).map(Self.canonicalized)
        for seed in seeds {
            let seed = Self.canonicalized(seed)
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

    /// Same logical window: matching source + scope + **pool** and `resetAt`
    /// within tolerance.
    ///
    /// The pool term is load-bearing, not decoration. Claude prints two weekly
    /// pools ("Current week (all models)" and "Current week (Fable)") that share
    /// one reset boundary; keying on `(source, scope, resetAt)` alone collapsed
    /// them into a single record whose peak was the worse pool and whose label
    /// was whichever painted last — so the all-models pool vanished and Fable
    /// reported all-models' number.
    private static func sameWindow(_ a: CapacityWindowRecord, as b: CapacityWindowRecord) -> Bool {
        a.sourceId == b.sourceId
            && a.scope == b.scope
            && canonicalPoolLabel(sourceId: a.sourceId, poolLabel: a.poolLabel)
                == canonicalPoolLabel(sourceId: b.sourceId, poolLabel: b.poolLabel)
            && abs(a.resetAt.timeIntervalSince(b.resetAt)) <= resetAtMergeTolerance
    }

    /// Claude primary weekly aliases (`all models` / `allmodels`) collapse to nil.
    /// Other sources keep the vendor label verbatim.
    private static func canonicalPoolLabel(sourceId: String, poolLabel: String?) -> String? {
        guard sourceId == "claude_code" else { return poolLabel }
        return ClaudeCapacityLog.canonicalPoolLabel(poolLabel)
    }

    private static func canonicalized(_ record: CapacityWindowRecord) -> CapacityWindowRecord {
        let label = canonicalPoolLabel(sourceId: record.sourceId, poolLabel: record.poolLabel)
        guard label != record.poolLabel else { return record }
        return CapacityWindowRecord(
            sourceId: record.sourceId,
            scope: record.scope,
            resetAt: record.resetAt,
            resetPrecision: record.resetPrecision,
            peakUsedPercent: record.peakUsedPercent,
            firstObservedAt: record.firstObservedAt,
            lastObservedAt: record.lastObservedAt,
            observationCount: record.observationCount,
            planTier: record.planTier,
            poolLabel: label
        )
    }

    /// Collapse primary aliases then merge same-identity rows (monotone peaks).
    private static func dedupeCanonical(_ records: [CapacityWindowRecord]) -> [CapacityWindowRecord] {
        var out: [CapacityWindowRecord] = []
        for raw in records {
            let record = canonicalized(raw)
            if let index = out.firstIndex(where: { sameWindow($0, as: record) }) {
                out[index] = merge(existing: out[index], incoming: record)
            } else {
                out.append(record)
            }
        }
        return out
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
            // Peak takes the max; the current reading takes the NEWER sample —
            // including when it is lower, which is the whole point.
            lastUsedPercent: laterIsIncoming
                ? (incoming.lastUsedPercent ?? incoming.peakUsedPercent)
                : (existing.lastUsedPercent ?? existing.peakUsedPercent),
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

        let poolLabel: String? = window.source == "claude_code"
            ? ClaudeCapacityLog.canonicalPoolLabel(window.poolLabel)
            : window.poolLabel
        return CapacityWindowRecord(
            sourceId: window.source,
            scope: window.scope,
            resetAt: resetAt,
            resetPrecision: window.resetPrecision,
            peakUsedPercent: used,
            // A fresh seed is both the peak so far and the current reading.
            lastUsedPercent: used,
            firstObservedAt: window.observedAt,
            lastObservedAt: window.observedAt,
            observationCount: 1,
            planTier: window.planTier,
            poolLabel: poolLabel
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

// MARK: - Strip projection

extension CapacityWindowRecord {
    /// Project a stored peak window into a strip `CapacityWindow`.
    ///
    /// Rate-limit windows are monotone within a cycle, so peak used ≈ last used
    /// for display. `observedAt` is `lastObservedAt` — never "now".
    public func asCapacityWindow() -> CapacityWindow {
        let tier: CapacityAcquisitionTier = .tuiProbe
        // Collapse Claude primary weekly aliases so bare hydrate never re-emits
        // a phantom `allmodels` pool line next to the unlabeled primary.
        let label: String? = sourceId == "claude_code"
            ? ClaudeCapacityLog.canonicalPoolLabel(poolLabel)
            : poolLabel
        return CapacityWindow(
            // The latest reading, not the high-water mark. Falls back to the
            // peak for records written before `lastUsedPercent` existed.
            used: lastUsedPercent ?? peakUsedPercent,
            source: sourceId,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: resetPrecision,
            observedAt: lastObservedAt,
            sourceTier: tier,
            poolLabel: label,
            planTier: planTier
        )
    }
}

// MARK: - Display acquisition (live + hydrate)

/// Single display path for `alln capacity` and the Mac strip (CAP-HF-00 + Phase 1).
///
/// Records **live** successes only. Bare path hydrates unknowns from history so
/// `alln capacity` shows last-known + real age. On **refresh**, seats that were
/// attempted and failed keep their failure reason — history is not painted as
/// live for those rows. Unprobed siblings may still hydrate.
///
/// **SSOT:** `snapshot` is the only entry for CLI and GUI — same args, same hydrate law.
public enum CapacityDisplayAcquisition {
    /// Bench snapshot — identical to `alln capacity` / `alln capacity --refresh`.
    public struct Snapshot: Sendable, Equatable {
        public let now: Date
        public let windows: [CapacityWindow]
        public let rows: [CapacityBenchRow]

        public init(now: Date, windows: [CapacityWindow], rows: [CapacityBenchRow]) {
            self.now = now
            self.windows = windows
            self.rows = rows
        }
    }

    /// Single entry for CLI and Mac GUI. `refresh: false` = bare instant snapshot;
    /// `refresh: true` = live acquire (`--refresh` / `--refresh --source`).
    public static func snapshot(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date = Date(),
        refresh: Bool = false,
        refreshSource: String? = nil,
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout
    ) -> Snapshot {
        let windows = windows(
            homeRoot: homeRoot,
            now: now,
            refresh: refresh,
            refreshSource: refreshSource,
            historyStore: historyStore,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout
        )
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        return Snapshot(now: now, windows: windows, rows: rows)
    }

    public static func windows(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date,
        refresh: Bool = false,
        refreshSource: String? = nil,
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout
    ) -> [CapacityWindow] {
        let live = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: refresh,
            refreshSource: refreshSource,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout
        )
        // Record live observations only — never re-count hydrated history.
        try? historyStore.record(live, now: now)
        let history = historyStore.lastKnownWindows(
            sourceIds: CapacityAcquisition.benchSourceOrder,
            now: now
        )
        let suppress: Set<String>
        if refresh {
            let attempted = Set(
                CapacityAcquisition.sourcesProbed(refresh: true, refreshSource: refreshSource)
            )
            let liveBy = Dictionary(grouping: live, by: \.source)
            suppress = Set(attempted.filter { source in
                CapacityHydration.isFailedAttempt(liveBy[source] ?? [])
            })
        } else {
            suppress = []
        }
        return CapacityHydration.apply(
            live: live,
            history: history,
            now: now,
            suppressHistoryForSources: suppress
        )
    }
}
