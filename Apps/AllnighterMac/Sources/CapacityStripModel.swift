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
    /// Scheduler health as the resident reports it — never inferred from age.
    private(set) var freshness = CapacityResidentService.Freshness(armed: false, lastSettledAt: nil)
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
    private var clockTask: Task<Void, Never>?

    /// How often the open strip re-reads the wall clock.
    ///
    /// Everything the strip says about time — age chips, reset countdowns, the
    /// header's freshness line — is derived from `now`. Without this the whole
    /// surface freezes at the last settle, and a scheduler that has stopped
    /// renders as a bench that was checked seconds ago. One minute is the
    /// smallest unit any of those labels can show.
    private static let clockInterval: Duration = .seconds(60)

    init(resident: CapacityResidentService = .shared) {
        self.resident = resident
    }

    // MARK: - Derived

    var rows: [CapacityBenchRow] {
        let projected = CapacityBenchProjection.rows(from: windows, now: now)
        return CapacityStripRenderer.ordered(rows: projected, notReadyOrParked: notReadyOrParked)
    }

    var hero: CapacityHeroPresentation? {
        CapacityHeroPresentation.select(from: rows, now: now, restingNames: restingDisplayNames)
    }

    /// Seats on the bench that are spent — nothing left, but they come back.
    ///
    /// Distinct from parked: parked means go fix something, resting means wait.
    var restingDisplayNames: [String] {
        benchRows.filter { row in
            let remaining = row.pools.compactMap(\.dashboardRemainingPercent)
            return !remaining.isEmpty && (remaining.min() ?? 1) <= 0
        }
        .map { CapacityStripRenderer.displayName(for: $0.source) }
    }

    /// Tolerance for calling two seats "sampled together". The bench is probed
    /// in one wave, so members land seconds apart, not minutes.
    private static let sameWaveTolerance: TimeInterval = 90

    /// When the last probe wave ran — the newest sample on the bench.
    ///
    /// This is what the header quotes. Deliberately the newest rather than a
    /// consensus: one straggler must not void the shared time and push a
    /// timestamp back onto all eight rows, which is the noise this replaced.
    /// The straggler marks itself instead.
    var benchObservedAt: Date? {
        benchRows.compactMap { CapacityStripRenderer.observedAt(for: $0) }.max()
    }

    /// Whether this row must show its own age chip.
    ///
    /// Fails loud on purpose. A row is silent only when we can prove it matches
    /// the bench; an undeterminable age, or a bench with no shared time, shows
    /// the chip. Absence of a badge means "verified same as the header", never
    /// "we did not check" — that inversion is exactly how a stale seat starts
    /// looking current.
    func showsOwnAge(_ row: CapacityBenchRow) -> Bool {
        guard let shared = benchObservedAt else { return true }
        guard let rowAge = CapacityStripRenderer.observedAt(for: row) else { return true }
        return abs(rowAge.timeIntervalSince(shared)) > Self.sameWaveTolerance
    }

    var expiringCount: Int {
        rows.filter { CapacityStripRenderer.color(for: $0, now: now) == .amber }.count
    }

    func isRefreshing(_ source: String) -> Bool {
        refreshingSources.contains(source) || isRefreshingAll
    }

    /// Seats the table renders — those that can actually take work.
    ///
    /// A parked seat used to occupy a full dimmed row saying "not ready — probe
    /// failed" in every column. That is a whole row of table to carry one bit,
    /// so the bit moved to the footer and the row left.
    var benchRows: [CapacityBenchRow] {
        rows.filter { !notReadyOrParked.contains($0.source) }
    }

    /// Seats that can actually take work — the header's one number.
    var onBenchCount: Int { benchRows.count }

    /// Parked / not-ready seats by display name, for the footer note.
    ///
    /// Named, not counted: a count sends the reader hunting the table for who
    /// is missing, which is the busyness the header was supposed to remove.
    var parkedDisplayNames: [String] {
        rows.filter { notReadyOrParked.contains($0.source) }
            .map { CapacityStripRenderer.displayName(for: $0.source) }
    }

    /// The header's freshness line — three mutually exclusive sentences.
    ///
    /// Deliberately words, not colour. Amber in this strip means *capacity is
    /// expiring*; spending it on "our scheduler stopped" would tell the user
    /// they are running out when the truth is that we stopped looking.
    var freshnessLine: String {
        Self.freshnessLine(
            freshness: freshness,
            isRefreshingAll: isRefreshingAll,
            benchObservedAt: benchObservedAt,
            now: now
        )
    }

    /// Pure so the sentences can be proven without a live resident.
    ///
    /// `benchObservedAt` is preferred over the scheduler's settle time: the
    /// header now speaks for every row, so it must quote what the rows actually
    /// say. A settle can succeed while a seat's sample is older, and the header
    /// would then vouch for freshness the table does not have.
    static func freshnessLine(
        freshness: CapacityResidentService.Freshness,
        isRefreshingAll: Bool,
        benchObservedAt: Date?,
        now: Date
    ) -> String {
        if isRefreshingAll { return "Checking…" }
        guard freshness.armed else { return "Auto-checks stopped" }
        guard let sampled = benchObservedAt ?? freshness.lastSettledAt else { return "Checking…" }
        return "Checked \(CapacityStripRenderer.elapsedLabel(from: sampled, to: now))"
    }

    // MARK: - Clock

    /// Start the one-minute tick. Idempotent; fixtures never tick (pinned clock).
    func startClock() {
        guard !isFixtureSeeded, clockTask == nil else { return }
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.clockInterval)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    /// Advance the clock and let the expiry gate act on the result.
    ///
    /// Re-applying the gate here is the whole point: it is what makes a dead
    /// scheduler visible. Seats decay to `expired` unknowns on their own instead
    /// of holding confident percentages nobody has verified in hours.
    private func tick() {
        guard featureEnabled, !isFixtureSeeded else { return }
        now = Date()
        windows = CapacityPaintGate.repaintedForOpenWindow(windows, now: now)
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
            freshness = .init(armed: false, lastSettledAt: nil)
            stopClock()
            return
        }
        isRefreshingAll = false
        freshness = await resident.currentFreshness()
        startClock()
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
            self.freshness = .init(armed: false, lastSettledAt: nil)
            self.stopClock()
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
        freshness = .init(armed: true, lastSettledAt: now)
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
            self.freshness = await self.resident.currentFreshness()
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
            self.freshness = await self.resident.currentFreshness()
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

    /// Which question the hero is answering. Both answer "which seat now?" —
    /// one from scarcity, one from abundance.
    ///
    /// There is deliberately no empty case. A slot that vanishes when nothing is
    /// urgent means the top third of the first screen a user sees comes and goes
    /// with a vendor's clock, and on an ordinary day the page opens on a bare
    /// table. A calm bench is not a reason to say nothing — it is a reason to
    /// say something else.
    enum Mood: Equatable {
        /// A seat is near its reset with unspent headroom — spend it or lose it.
        case expiring
        /// Nothing is expiring; name the seat with the most room left.
        case mostRoom
    }

    let mood: Mood
    let source: String
    let displayName: String
    let planTier: String?
    let remainingPercent: Double
    let resetAt: Date?
    let alsoLine: String?

    /// The expiring seat when one qualifies, else the roomiest. Nil only when no
    /// seat has a usable number at all.
    static func select(
        from rows: [CapacityBenchRow],
        now: Date,
        restingNames: [String] = []
    ) -> CapacityHeroPresentation? {
        selectExpiring(from: rows, now: now)
            ?? selectMostRoom(from: rows, now: now, restingNames: restingNames)
    }

    /// Gate then rank: eligibility from Core; dollars-at-risk approximated by plan-tier ordinal.
    static func selectExpiring(from rows: [CapacityBenchRow], now: Date) -> CapacityHeroPresentation? {
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
            mood: .expiring,
            source: top.row.source,
            displayName: CapacityStripRenderer.displayName(for: top.row.source),
            planTier: top.row.planTier,
            remainingPercent: top.remaining,
            resetAt: top.resetAt,
            alsoLine: also
        )
    }

    /// The calm hero: the seat with the most unspent allowance.
    ///
    /// Same shape as the expiring hero on purpose — one seat, one number, one
    /// button — so the eye learns a single place to look. The old calm state
    /// said "Everything has room" in three type sizes and gave the reader
    /// nothing to do with it.
    ///
    /// This is a fact plus a shortcut, never routing advice. Most-room is not
    /// the same as best-fit, and this codebase deliberately has no intent
    /// router.
    static func selectMostRoom(
        from rows: [CapacityBenchRow],
        now: Date,
        restingNames: [String] = []
    ) -> CapacityHeroPresentation? {
        struct Candidate {
            let row: CapacityBenchRow
            let remaining: Double
            let resetAt: Date?
        }
        var candidates: [Candidate] = []
        for row in rows {
            // Tightest pool binds — a seat is only as free as its scarcest bucket.
            let pools = row.pools.compactMap { pool -> (Double, Date?)? in
                guard let remaining = pool.dashboardRemainingPercent else { return nil }
                return (remaining, pool.dashboardResetAt)
            }
            guard let tightest = pools.min(by: { $0.0 < $1.0 }) else { continue }
            guard tightest.0 > 0 else { continue }   // a spent seat is not a recommendation
            candidates.append(Candidate(row: row, remaining: tightest.0, resetAt: tightest.1))
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.remaining > $1.remaining }
        let top = candidates[0]

        // Resting seats are the one thing the roomiest seat does not already
        // say, and the reason the bench is smaller than it looks.
        let also: String?
        switch restingNames.count {
        case 0: also = nil
        case 1: also = "\(restingNames[0]) is resting"
        default: also = restingNames.prefix(2).joined(separator: " and ") + " are resting"
        }

        return CapacityHeroPresentation(
            mood: .mostRoom,
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

    /// An ordinary day: nothing near its reset, so the hero has no scarcity to
    /// sell and must earn the slot some other way.
    ///
    /// This is the state the launch surface is in most of the time, and the one
    /// that used to render as a bare table with a hole above it.
    static func calmWindows(now: Date = now) -> [CapacityWindow] {
        mixedWindows(now: now).map { window in
            // Push every reset well past the 48h hero gate; keep the numbers.
            guard let reset = window.resetAt, let used = window.usedPercent,
                  reset.timeIntervalSince(now) < CapacityBenchProjection.heroNearDeadline
            else { return window }
            return CapacityWindow(
                used: used,
                source: window.source,
                scope: window.scope,
                resetAt: now.addingTimeInterval(5 * 86400),
                resetPrecision: window.resetPrecision,
                observedAt: window.observedAt,
                sourceTier: window.sourceTier,
                poolLabel: window.poolLabel,
                planTier: window.planTier
            )
        }
    }

    static func mixedWindows(now: Date = now) -> [CapacityWindow] {
        [
            CapacityWindow(
                used: 61,
                source: "codex",
                scope: .weekly,
                resetAt: now.addingTimeInterval(6 * 86400 + 3 * 3600),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-45),
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
                observedAt: now.addingTimeInterval(-1_800),
                sourceTier: .tuiProbe,
                planTier: "Ultra"
            ),
            CapacityWindow(
                used: 42,
                source: "grok",
                scope: .weekly,
                resetAt: now.addingTimeInterval(41 * 3600),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe,
                planTier: "X Premium+"
            ),
            CapacityWindow(
                used: 100,
                source: "kimi",
                scope: .weekly,
                resetAt: now.addingTimeInterval(1.5 * 86400),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe,
                planTier: "Kimi Code"
            ),
            CapacityWindow(
                used: 0,
                source: "kimi",
                scope: .fiveHour,
                resetAt: now.addingTimeInterval(3_780),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe
            ),
            CapacityWindow(
                remaining: 93,
                source: "agy",
                scope: .weekly,
                resetAt: now.addingTimeInterval(6 * 86400 + 20 * 3600),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-45),
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
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe,
                poolLabel: "GEMINI MODELS"
            ),
            CapacityWindow(
                remaining: 60,
                source: "agy",
                scope: .weekly,
                resetAt: now.addingTimeInterval(2 * 86400 + 3 * 3600),
                resetPrecision: .minute,
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe,
                poolLabel: "CLAUDE AND GPT MODELS"
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "agy",
                scope: .fiveHour,
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe,
                poolLabel: "CLAUDE AND GPT MODELS"
            ),
        ]
    }

    static func refreshingWindows(now: Date = now) -> [CapacityWindow] {
        mixedWindows(now: now)
    }
}
