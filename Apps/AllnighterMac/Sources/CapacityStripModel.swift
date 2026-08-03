import Foundation
import AllnighterCore
import AllnighterEngine

/// Mac launch-surface owner for the capacity strip.
///
/// **SSOT:** `CapacityResidentService` (CWB-S01a) — every acquire goes through
/// `requestRefresh(reason:)`; the resident owns single-flight, supersede, and
/// the 2-minute floor. Launch paints the resident snapshot when one exists,
/// else placeholders. Probes never run on the main actor.
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
    /// CWB-S01b feature ON/OFF. OFF: the strip renders the Enable CTA instead
    /// of rows, and no acquire ever starts (resident enforces zero probes).
    private(set) var featureEnabled = true

    /// The one refresh funnel. Shared instance in the Dock app; tests inject
    /// their own with a fake clock / fake fetch.
    private let resident: CapacityResidentService

    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var refreshSourceGenerations: [String: Int] = [:]
    private var refreshAllTask: Task<Void, Never>?
    private var refreshAllGeneration = 0

    init(resident: CapacityResidentService = .shared) {
        self.resident = resident
    }

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

    /// Launch path: resident snapshot when one exists (paint-gated), else
    /// placeholders — never history hydrate, never a probe at launch.
    /// OFF paints nothing: the view renders the Enable CTA instead.
    func loadLive(notReadyOrParked: Set<String> = []) async {
        guard !isFixtureSeeded else { return }
        self.notReadyOrParked = notReadyOrParked
        featureEnabled = await resident.isEnabled
        guard featureEnabled else {
            isRefreshingAll = false
            windows = []
            needsLiveRefresh = false
            return
        }
        isRefreshingAll = false
        if let settled = await resident.currentSnapshot() {
            let paintedNow = Date()
            now = paintedNow
            windows = CapacityPaintGate.paintedWindows(
                settled.windows, settledAt: settled.settledAt, now: paintedNow
            )
            needsLiveRefresh = false
        } else {
            let bench = CapacityFetch.launchSnapshot()
            now = bench.now
            windows = bench.windows
            needsLiveRefresh = true
            // Startup when ON fires a silent .launch through the resident;
            // coalesce on it so the strip paints as soon as it settles
            // (launch may show warming — timer ticks never do).
            refreshAll()
        }
    }

    /// Enable CTA: turn the feature on (persisted via the resident) and load.
    func enableFeature() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.resident.setEnabled(true)
            self.featureEnabled = true
            await self.loadLive()
        }
    }

    /// Turn the feature off: resident scoped-cancels in-flight probes, stops
    /// the scheduler, and drops the snapshot (no memo-as-live).
    func disableFeature() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.resident.setEnabled(false)
            self.featureEnabled = false
            self.windows = []
            self.refreshingSources = []
            self.isRefreshingAll = false
            self.needsLiveRefresh = false
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
        needsLiveRefresh = false
    }

    // MARK: - Refresh

    /// Full-bench acquire through the resident funnel. Repeat taps coalesce on
    /// the in-flight generation (resident single-flight); an in-flight targeted
    /// seat refresh is superseded by the resident with a scoped terminate.
    func refreshAll() {
        guard !isFixtureSeeded else { return }
        refreshAllTask?.cancel()
        refreshAllGeneration += 1
        let generation = refreshAllGeneration
        isRefreshingAll = true
        refreshAllTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.refreshAllGeneration {
                    self.isRefreshingAll = false
                    self.refreshAllTask = nil
                }
            }
            let bench = await self.resident.requestRefresh(reason: .userRefresh)
            guard !Task.isCancelled else { return }
            guard generation == self.refreshAllGeneration else { return }
            self.now = bench.now
            self.windows = bench.windows
            self.needsLiveRefresh = false
        }
    }

    /// Targeted seat acquire through the resident funnel. Same-seat taps
    /// coalesce; a different seat takes its turn after the in-flight settle.
    func refreshSource(_ source: String) {
        guard !isFixtureSeeded else { return }
        if let message = CapacityAcquisition.validateRefreshSourceId(source) {
            _ = message
            return
        }
        refreshTasks[source]?.cancel()
        refreshingSources.insert(source)
        let nextGeneration = (refreshSourceGenerations[source] ?? 0) + 1
        refreshSourceGenerations[source] = nextGeneration
        let generation = nextGeneration
        refreshTasks[source] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == self.refreshSourceGenerations[source, default: 0] {
                    self.refreshingSources.remove(source)
                    self.refreshTasks[source] = nil
                }
            }
            let bench = await self.resident.requestRefresh(reason: .userRefreshSeat(source))
            guard !Task.isCancelled else { return }
            guard generation == self.refreshSourceGenerations[source, default: 0] else { return }
            self.now = bench.now
            self.windows = Self.merge(prior: self.windows, acquired: bench.windows, refreshedSource: source)
            self.needsLiveRefresh = false
        }
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
