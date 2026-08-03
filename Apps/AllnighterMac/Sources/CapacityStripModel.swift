import Foundation
import AllnighterCore
import AllnighterEngine

/// Mac launch-surface owner for the capacity strip.
///
/// **SSOT:** `CapacityFetch` — live PTY only for painted %. Launch shows
/// placeholders until the user taps Refresh (or a fresh in-process memo exists).
/// Probes never run on the main actor.
@MainActor
@Observable
final class CapacityStripModel {
    /// Projected strip rows (fixed product order applied at read).
    private(set) var windows: [CapacityWindow] = []
    /// Clock for relative ages / clocks. Fixture paths pin this; live paths update on load.
    private(set) var now: Date = Date()
    /// Sources currently refreshing (per-row spinner). Never greys sibling rows.
    private(set) var refreshingSources: Set<String> = []
    /// True while any acquire is in flight (refresh-all).
    private(set) var isRefreshingAll = false
    /// Launch showed placeholders — user should tap Refresh for live numbers.
    private(set) var needsLiveRefresh = true
    /// Not-ready / parked seats render last and dimmed (health as absence of numbers).
    private(set) var notReadyOrParked: Set<String> = []
    /// When set, the model is fixture-seeded and live acquire is skipped on appear.
    private(set) var isFixtureSeeded = false

    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var refreshScopes: [String: CapacityProbeScope] = [:]
    private var refreshSourceGenerations: [String: Int] = [:]
    private var refreshAllTask: Task<Void, Never>?
    private var refreshAllScope: CapacityProbeScope?
    private var refreshAllGeneration = 0
    private var loadTask: Task<Void, Never>?

    // MARK: - Derived

    var rows: [CapacityBenchRow] {
        let projected = CapacityBenchProjection.rows(from: windows, now: now)
        return CapacityStripRenderer.ordered(rows: projected, notReadyOrParked: notReadyOrParked)
    }

    var hero: CapacityHeroPresentation? {
        CapacityHeroPresentation.select(from: rows, now: now)
    }

    var expiringCount: Int {
        rows.filter { CapacityStripRenderer.color(for: $0, now: now) == .amber }.count
    }

    func isRefreshing(_ source: String) -> Bool {
        refreshingSources.contains(source) || isRefreshingAll
    }

    // MARK: - Load

    func updateNotReadyOrParked(_ ids: Set<String>) {
        notReadyOrParked = ids
    }

    /// Launch path: placeholders or in-process memo — never history hydrate.
    func loadLive(
        notReadyOrParked: Set<String> = [],
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil
    ) {
        guard !isFixtureSeeded else { return }
        self.notReadyOrParked = notReadyOrParked
        loadTask?.cancel()
        isRefreshingAll = false
        let bench = CapacityFetch.launchSnapshot()
        now = bench.now
        windows = bench.windows
        needsLiveRefresh = bench.windows.allSatisfy { $0.unknownReason == .neverSampled }
    }

    /// Fixture / proof path: inject Core windows directly. No IO.
    func seedFixture(
        windows: [CapacityWindow],
        now: Date,
        notReadyOrParked: Set<String> = [],
        refreshingSource: String? = nil
    ) {
        isFixtureSeeded = true
        self.now = now
        self.windows = windows
        self.notReadyOrParked = notReadyOrParked
        refreshingSources = refreshingSource.map { [$0] } ?? []
        isRefreshingAll = false
        needsLiveRefresh = false
    }

    // MARK: - Refresh

    /// Live PTY acquire for every seat (`CapacityFetch.liveSnapshot`).
    func refreshAll(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeScope: CapacityProbeScope? = nil
    ) {
        guard !isFixtureSeeded else { return }
        // Full refresh supersedes every in-flight generation. Terminate scopes
        // before cancelling so the cancellation path always reaps PTYs.
        refreshAllScope?.terminate()
        refreshAllScope = nil
        refreshAllTask?.cancel()
        for scope in refreshScopes.values { scope.terminate() }
        refreshScopes.removeAll()
        for task in refreshTasks.values { task.cancel() }
        refreshTasks.removeAll()
        refreshingSources.removeAll()
        refreshSourceGenerations.removeAll()

        refreshAllGeneration += 1
        let generation = refreshAllGeneration
        isRefreshingAll = true
        let scope = probeScope ?? CapacityProbeScope()
        refreshAllScope = scope
        refreshAllTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.refreshAllGeneration {
                    self.isRefreshingAll = false
                    self.refreshAllTask = nil
                    self.refreshAllScope = nil
                }
            }
            let bench = await Self.acquireLive(
                homeRoot: homeRoot,
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                refreshSource: nil,
                probeScope: scope
            )
            guard !Task.isCancelled else { return }
            self.now = bench.now
            self.windows = bench.windows
            self.needsLiveRefresh = false
        }
    }

    /// Live PTY acquire for one seat.
    func refreshSource(
        _ source: String,
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeScope: CapacityProbeScope? = nil
    ) {
        guard !isFixtureSeeded else { return }
        if let message = CapacityAcquisition.validateRefreshSourceId(source) {
            _ = message
            return
        }
        // Supersede any in-flight targeted refresh for this source.
        refreshScopes[source]?.terminate()
        refreshScopes.removeValue(forKey: source)
        refreshTasks[source]?.cancel()
        refreshingSources.insert(source)
        let nextGeneration = (refreshSourceGenerations[source] ?? 0) + 1
        refreshSourceGenerations[source] = nextGeneration
        let generation = nextGeneration
        let scope = probeScope ?? CapacityProbeScope()
        refreshScopes[source] = scope
        refreshTasks[source] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.refreshSourceGenerations[source, default: 0] {
                    self.refreshingSources.remove(source)
                    self.refreshTasks[source] = nil
                    self.refreshScopes.removeValue(forKey: source)
                }
            }
            let bench = await Self.acquireLive(
                homeRoot: homeRoot,
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                refreshSource: source,
                probeScope: scope
            )
            guard !Task.isCancelled else { return }
            self.now = bench.now
            self.windows = Self.merge(prior: self.windows, acquired: bench.windows, refreshedSource: source)
            self.needsLiveRefresh = false
        }
    }

    /// Off-main-actor live acquire — CapacityFetch, no history hydrate.
    private static func acquireLive(
        homeRoot: URL,
        historyStore: CapacityHistoryStore,
        probeExecutor: (any CapacityProbeExecuting)?,
        refreshSource: String?,
        probeScope: CapacityProbeScope?
    ) async -> CapacityFetch.Snapshot {
        await Task.detached(priority: .userInitiated) {
            CapacityFetch.liveSnapshot(
                homeRoot: homeRoot,
                refreshSource: refreshSource,
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                updateMemo: refreshSource == nil,
                probeScope: probeScope
            )
        }.value
    }

    /// Keep prior windows for every source except `refreshedSource`, which is
    /// replaced by the fresh acquisition slice for that source.
    static func merge(
        prior: [CapacityWindow],
        acquired: [CapacityWindow],
        refreshedSource: String
    ) -> [CapacityWindow] {
        let kept = prior.filter { $0.source != refreshedSource }
        let fresh = acquired.filter { $0.source == refreshedSource }
        return kept + fresh
    }
}

// MARK: - Hero (pure selection over Core rows)

/// Fixed-height hero presentation derived from Core eligibility — no parallel store.
struct CapacityHeroPresentation: Equatable {
    let source: String
    let displayName: String
    let planTier: String?
    let remainingPercent: Double
    let resetAt: Date?
    let alsoLine: String?

    /// Gate then rank: eligibility from Core; dollars-at-risk approximated by plan-tier ordinal.
    static func select(from rows: [CapacityBenchRow], now: Date) -> CapacityHeroPresentation? {
        struct Candidate {
            let row: CapacityBenchRow
            let remaining: Double
            let resetAt: Date?
            let rank: Int
        }
        var candidates: [Candidate] = []
        for row in rows {
            guard let binding = row.heroBinding(at: now) else { continue }
            candidates.append(Candidate(
                row: row,
                remaining: binding.remaining,
                resetAt: binding.resetAt,
                rank: planTierRank(row.planTier)
            ))
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort {
            if $0.rank != $1.rank { return $0.rank > $1.rank }
            return $0.remaining > $1.remaining
        }
        let top = candidates[0]
        let also: String?
        if candidates.count > 1 {
            let others = candidates.dropFirst().prefix(2).map {
                "\(CapacityStripRenderer.displayName(for: $0.row.source)) \(CapacityStripRenderer.formatPercent($0.remaining))"
            }
            also = "Also: " + others.joined(separator: " · ")
        } else {
            also = nil
        }
        return CapacityHeroPresentation(
            source: top.row.source,
            displayName: CapacityStripRenderer.displayName(for: top.row.source),
            planTier: top.row.planTier,
            remainingPercent: top.remaining,
            resetAt: top.resetAt,
            alsoLine: also
        )
    }

    private static func planTierRank(_ tier: String?) -> Int {
        guard let raw = tier?.lowercased() else { return 0 }
        if raw.contains("ultra") { return 5 }
        if raw.contains("max") { return 4 }
        if raw.contains("premium") || raw.contains("pro") { return 3 }
        if raw.contains("plus") { return 2 }
        if raw.contains("team") { return 2 }
        return 1
    }
}

// MARK: - Fixture windows (proof harness)

enum CapacityStripFixtures {
    static let now = Date(timeIntervalSince1970: 1_753_833_600)

    static func mixedWindows(now: Date = now) -> [CapacityWindow] {
        [
            CapacityWindow(
                used: 61,
                source: "codex",
                scope: .weekly,
                resetAt: now.addingTimeInterval(6 * 86400 + 3 * 3600),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-120),
                sourceTier: .tuiProbe,
                planTier: "Plus"
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe,
                planTier: "Max"
            ),
            CapacityWindow(
                used: 27,
                source: "cursor_agent",
                scope: .monthly,
                resetAt: now.addingTimeInterval(26 * 86400),
                resetPrecision: .day,
                observedAt: now.addingTimeInterval(-300),
                sourceTier: .tuiProbe,
                planTier: "Ultra"
            ),
            CapacityWindow(
                used: 42,
                source: "grok",
                scope: .weekly,
                resetAt: now.addingTimeInterval(41 * 3600),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-90),
                sourceTier: .tuiProbe,
                planTier: "X Premium+"
            ),
            CapacityWindow(
                used: 100,
                source: "kimi",
                scope: .weekly,
                resetAt: now.addingTimeInterval(1.5 * 86400),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-180),
                sourceTier: .tuiProbe,
                planTier: "Kimi Code"
            ),
            CapacityWindow(
                used: 0,
                source: "kimi",
                scope: .fiveHour,
                resetAt: now.addingTimeInterval(3_780),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-180),
                sourceTier: .tuiProbe
            ),
            CapacityWindow(
                remaining: 93,
                source: "agy",
                scope: .weekly,
                resetAt: now.addingTimeInterval(6 * 86400 + 20 * 3600),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-60),
                sourceTier: .tuiProbe,
                poolLabel: "GEMINI MODELS",
                planTier: "Pro"
            ),
            CapacityWindow(
                remaining: 58,
                source: "agy",
                scope: .fiveHour,
                resetAt: now.addingTimeInterval(3 * 3600 + 21 * 60),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-60),
                sourceTier: .tuiProbe,
                poolLabel: "GEMINI MODELS"
            ),
            CapacityWindow(
                remaining: 60,
                source: "agy",
                scope: .weekly,
                resetAt: now.addingTimeInterval(2 * 86400 + 3 * 3600),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-60),
                sourceTier: .tuiProbe,
                poolLabel: "CLAUDE AND GPT MODELS"
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "agy",
                scope: .fiveHour,
                observedAt: now.addingTimeInterval(-60),
                sourceTier: .tuiProbe,
                poolLabel: "CLAUDE AND GPT MODELS"
            ),
        ]
    }

    static func refreshingWindows(now: Date = now) -> [CapacityWindow] {
        mixedWindows(now: now)
    }
}
