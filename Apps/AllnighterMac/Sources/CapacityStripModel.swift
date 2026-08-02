import Foundation
import AllnighterCore
import AllnighterEngine

/// Mac launch-surface owner for the capacity strip.
///
/// Holds Core rows only — no parallel capacity store, no second JSON shape.
/// Acquisition lives in `CapacityAcquisition`; colour / order / age labels
/// come from `CapacityStripRenderer`.
///
/// **Founder law (2026-08-02):** never paint a capacity percentage unless this
/// process just acquired it live. History is for the CLI bare path only. Launch
/// shows unknowns until refresh completes. Probes never run on the main actor
/// (PTY waits blocked the UI → beach ball + crash).
@MainActor
@Observable
final class CapacityStripModel {
    /// Projected strip rows (fixed product order applied at read).
    private(set) var windows: [CapacityWindow] = []
    /// Clock for relative ages / clocks. Fixture paths pin this; live paths update on load.
    private(set) var now: Date = Date()
    /// Sources currently refreshing (per-row spinner). Never greys sibling rows.
    private(set) var refreshingSources: Set<String> = []
    /// True while refresh-all is in flight.
    private(set) var isRefreshingAll = false
    /// Not-ready / parked seats render last and dimmed (health as absence of numbers).
    private(set) var notReadyOrParked: Set<String> = []
    /// When set, the model is fixture-seeded and live acquire is skipped on appear.
    private(set) var isFixtureSeeded = false

    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var refreshAllTask: Task<Void, Never>?

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

    /// Launch path: paint unknowns only, then refresh off the main actor.
    /// Never hydrates history into the strip — stale % is a trust lie.
    func loadLive(
        notReadyOrParked: Set<String> = [],
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        autoRefresh: Bool = true
    ) {
        guard !isFixtureSeeded else { return }
        self.notReadyOrParked = notReadyOrParked
        let clock = Date()
        now = clock
        windows = Self.untrustedPlaceholders(now: clock)
        if autoRefresh {
            refreshAll(homeRoot: homeRoot, historyStore: historyStore, probeExecutor: probeExecutor)
        }
    }

    /// Honest empty strip: one neverSampled row per bench seat. No percentages.
    static func untrustedPlaceholders(now: Date) -> [CapacityWindow] {
        CapacityAcquisition.benchSourceOrder.map { source in
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: source,
                scope: .weekly,
                observedAt: now,
                sourceTier: CapacityAcquisition.tier3DisklessSources.contains(source)
                    ? .tuiProbe
                    : .onDisk
            )
        }
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
    }

    // MARK: - Refresh

    /// Refresh every seat. Runs probes off the main actor; applies live-only results.
    func refreshAll(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil
    ) {
        guard !isFixtureSeeded else { return }
        refreshAllTask?.cancel()
        isRefreshingAll = true
        // Drop any prior numbers immediately — only live success may repaint them.
        windows = Self.untrustedPlaceholders(now: Date())
        refreshAllTask = Task { @MainActor in
            defer {
                isRefreshingAll = false
                refreshAllTask = nil
            }
            let acquired = await Self.acquireLiveOnly(
                homeRoot: homeRoot,
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                refreshSource: nil
            )
            guard !Task.isCancelled else { return }
            now = acquired.now
            windows = acquired.windows
        }
    }

    /// Age-chip per-row refresh. Only that source spins; other rows stay as-is.
    func refreshSource(
        _ source: String,
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        probeExecutor: (any CapacityProbeExecuting)? = nil
    ) {
        guard !isFixtureSeeded else { return }
        if let message = CapacityAcquisition.validateRefreshSourceId(source) {
            _ = message
            return
        }
        refreshTasks[source]?.cancel()
        refreshingSources.insert(source)
        // Clear this seat's prior numbers until live result lands.
        windows = windows.map { window in
            guard window.source == source else { return window }
            return CapacityWindow.unknown(
                reason: .neverSampled,
                source: source,
                scope: window.scope,
                observedAt: Date(),
                sourceTier: window.sourceTier,
                poolLabel: window.poolLabel,
                planTier: window.planTier
            )
        }
        refreshTasks[source] = Task { @MainActor in
            defer {
                refreshingSources.remove(source)
                refreshTasks[source] = nil
            }
            let acquired = await Self.acquireLiveOnly(
                homeRoot: homeRoot,
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                refreshSource: source
            )
            guard !Task.isCancelled else { return }
            now = acquired.now
            windows = Self.merge(prior: windows, acquired: acquired.windows, refreshedSource: source)
        }
    }

    /// Off-main-actor live acquire. Never hydrates history into Mac strip display.
    private static func acquireLiveOnly(
        homeRoot: URL,
        historyStore: CapacityHistoryStore,
        probeExecutor: (any CapacityProbeExecuting)?,
        refreshSource: String?
    ) async -> (now: Date, windows: [CapacityWindow]) {
        await Task.detached(priority: .userInitiated) {
            let clock = Date()
            let windows = CapacityDisplayAcquisition.windows(
                homeRoot: homeRoot,
                now: clock,
                refresh: true,
                refreshSource: refreshSource,
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                hydrateFromHistory: false
            )
            return (clock, windows)
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
            for pool in row.pools {
                guard let remaining = pool.dashboardRemainingPercent,
                      CapacityBenchProjection.isHeroEligible(
                        remainingPercent: remaining,
                        resetAt: pool.dashboardResetAt,
                        now: now
                      )
                else { continue }
                candidates.append(Candidate(
                    row: row,
                    remaining: remaining,
                    resetAt: pool.dashboardResetAt,
                    rank: planTierRank(row.planTier)
                ))
            }
        }
        guard !candidates.isEmpty else { return nil }
        // Highest plan-tier ordinal first; then most remaining dollars-proxy (remaining %).
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

    /// Ordinal plan tier — zero-setup ranking, no built-in price table.
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
    /// Fixed clock ~2026-07-30 00:48 UTC — matches Core strip tests / CAP-S00 samples.
    static let now = Date(timeIntervalSince1970: 1_753_833_600)

    /// Mixed real states: known seats, unknown, red empty, amber expiring, Antigravity two pools.
    static func mixedWindows(now: Date = now) -> [CapacityWindow] {
        [
            CapacityWindow(
                used: 61,
                source: "codex",
                scope: .weekly,
                resetAt: now.addingTimeInterval(6 * 86400 + 3 * 3600),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-120),
                sourceTier: .onDisk,
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
                sourceTier: .onDisk,
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

    /// Same mixed bench with Grok mid-refresh (only that row spins).
    static func refreshingWindows(now: Date = now) -> [CapacityWindow] {
        mixedWindows(now: now)
    }
}
