import Foundation

// MARK: - Short-window column

/// Short-column state for one source (or one pool inside a multi-pool source).
///
/// The strip's short column is labeled `5h` but means **any short limit**:
/// vendor 5-hour windows **or** Claude's rolling **session** window. Grok and
/// Cursor have no short limit (`none`) — that is a product fact, not missing data.
/// Never model that as optional/nil; callers must not confuse it with `unknown`.
public enum CapacityShortWindowState: Sendable, Equatable, Codable {
    /// Source/pool genuinely has no short (5h / session) limit.
    case none
    /// Short window sampled with known remaining (raw vendor value).
    case known(
        remainingPercent: Double,
        usedPercent: Double,
        resetAt: Date?,
        resetPrecision: CapacityResetPrecision,
        observedAt: Date
    )
    /// Short window expected or attempted, but the sample is missing/unreadable.
    case unknown(CapacityUnknownReason)
}

// MARK: - Pool metrics (one bar stack entry)

/// Dashboard + short metrics for one pool inside a multi-pool row, or the sole
/// flat metrics when `poolLabel` is nil.
///
/// Dashboard scope is **weekly or monthly only** — never the short window.
public struct CapacityBenchPoolMetrics: Sendable, Equatable, Codable {
    /// Vendor pool label (e.g. `"GEMINI MODELS"`). Nil for flat single-pool sources.
    public let poolLabel: String?
    /// `.weekly` or `.monthly` when a dashboard window is known.
    public let dashboardScope: CapacityWindowScope?
    public let dashboardRemainingPercent: Double?
    public let dashboardUsedPercent: Double?
    public let dashboardResetAt: Date?
    public let dashboardResetPrecision: CapacityResetPrecision?
    public let shortWindow: CapacityShortWindowState
    /// Set when this pool has no usable dashboard sample (percentages stay nil).
    public let unknownReason: CapacityUnknownReason?

    public init(
        poolLabel: String?,
        dashboardScope: CapacityWindowScope?,
        dashboardRemainingPercent: Double?,
        dashboardUsedPercent: Double?,
        dashboardResetAt: Date?,
        dashboardResetPrecision: CapacityResetPrecision?,
        shortWindow: CapacityShortWindowState,
        unknownReason: CapacityUnknownReason?
    ) {
        self.poolLabel = poolLabel
        self.dashboardScope = dashboardScope
        self.dashboardRemainingPercent = dashboardRemainingPercent
        self.dashboardUsedPercent = dashboardUsedPercent
        self.dashboardResetAt = dashboardResetAt
        self.dashboardResetPrecision = dashboardResetPrecision
        self.shortWindow = shortWindow
        self.unknownReason = unknownReason
    }
}

// MARK: - Row (one CLI)

/// One capacity-strip row — **one source, never two**. Multi-pool CLIs (agy) carry
/// pools inside `pools`, not as sibling rows.
///
/// Pure surface: no clock reads, no IO. `now` is always a call-site parameter.
public struct CapacityBenchRow: Sendable, Equatable, Codable {
    public let source: String
    public let planTier: String?
    /// One entry for flat sources; two+ for pooled sources (agy Gemini + Claude/GPT).
    public let pools: [CapacityBenchPoolMetrics]
    /// Tightest remaining ceiling across **every** known window on this source.
    /// Kimi weekly 0% + 5h 100% → `0`. Nil only when no known remaining exists.
    public let effectiveRemainingPercent: Double?
    /// Raw input windows preserved for disclosure — derive, never hide.
    public let rawWindows: [CapacityWindow]
    /// Whole-row unknown (no usable sample). Never paired with invented zeros.
    public let unknownReason: CapacityUnknownReason?

    public init(
        source: String,
        planTier: String?,
        pools: [CapacityBenchPoolMetrics],
        effectiveRemainingPercent: Double?,
        rawWindows: [CapacityWindow],
        unknownReason: CapacityUnknownReason?
    ) {
        self.source = source
        self.planTier = planTier
        self.pools = pools
        self.effectiveRemainingPercent = effectiveRemainingPercent
        self.rawWindows = rawWindows
        self.unknownReason = unknownReason
    }

    /// Hero eligibility uses the **binding** dashboard window on this row — the
    /// pool with the least remaining headroom — not whichever sub-pool still has
    /// spare credits (e.g. Claude Fable must not shout over a nearly-empty primary).
    public func isHeroEligible(at now: Date) -> Bool {
        heroBinding(at: now) != nil
    }

    /// Binding dashboard window for hero/banner: tightest remaining % and that
    /// pool's reset clock. Nil when no known dashboard sample or not eligible.
    public func heroBinding(at now: Date) -> (remaining: Double, resetAt: Date)? {
        let known = pools.compactMap { pool -> (remaining: Double, resetAt: Date)? in
            guard let remaining = pool.dashboardRemainingPercent,
                  let resetAt = pool.dashboardResetAt
            else { return nil }
            return (remaining, resetAt)
        }
        guard let binding = known.min(by: { $0.remaining < $1.remaining }) else { return nil }
        guard CapacityBenchProjection.isHeroEligible(
            remainingPercent: binding.remaining,
            resetAt: binding.resetAt,
            now: now
        ) else { return nil }
        return binding
    }
}

// MARK: - Projection

/// Pure projection: many `CapacityWindow`s → one row per source.
///
/// Sibling of `SourceCapacityLedger` (observations → cooldowns). No IO, no
/// `Date()`, no ranking of sources — fixed display order is the caller's job.
public enum CapacityBenchProjection {

    // MARK: Hero thresholds (named — never magic numbers)

    /// Outer deadline gate: less than this remaining time, with enough headroom.
    public static let heroNearDeadline: TimeInterval = 48 * 60 * 60
    /// Minimum remaining % paired with `heroNearDeadline`.
    public static let heroNearDeadlineMinRemaining: Double = 20.0
    /// Inner deadline gate: less than this remaining time, with thinner headroom.
    public static let heroUrgentDeadline: TimeInterval = 24 * 60 * 60
    /// Minimum remaining % paired with `heroUrgentDeadline`.
    public static let heroUrgentMinRemaining: Double = 10.0

    /// Pure hero-eligibility predicate on one dashboard window.
    ///
    /// ```
    /// timeLeft < 48h  AND  remaining > 20%  → eligible
    /// timeLeft < 24h  AND  remaining > 10%  → eligible
    /// ```
    ///
    /// Strict inequalities on both sides. Missing `resetAt` or non-positive
    /// time-left is not eligible. Does not forecast future burn.
    public static func isHeroEligible(
        remainingPercent: Double,
        resetAt: Date?,
        now: Date
    ) -> Bool {
        guard let resetAt else { return false }
        let timeLeft = resetAt.timeIntervalSince(now)
        guard timeLeft > 0 else { return false }
        if timeLeft < heroNearDeadline && remainingPercent > heroNearDeadlineMinRemaining {
            return true
        }
        if timeLeft < heroUrgentDeadline && remainingPercent > heroUrgentMinRemaining {
            return true
        }
        return false
    }

    /// Project windows into one row per distinct `source`. First-seen source order
    /// is preserved; callers reorder for display. Does not rank by capacity.
    public static func rows(from windows: [CapacityWindow], now: Date) -> [CapacityBenchRow] {
        // `now` is required so every time-dependent call site is explicit; the
        // projection body is clock-free today. Keep the parameter for API stability
        // with hero checks and future anchored work.
        _ = now

        var order: [String] = []
        var bySource: [String: [CapacityWindow]] = [:]
        for window in windows {
            if bySource[window.source] == nil {
                order.append(window.source)
                bySource[window.source] = []
            }
            bySource[window.source, default: []].append(window)
        }

        return order.compactMap { source in
            guard let group = bySource[source] else { return nil }
            return row(source: source, windows: group)
        }
    }

    // MARK: - Internals

    private static func row(source: String, windows: [CapacityWindow]) -> CapacityBenchRow {
        let planTier = windows.lazy.compactMap(\.planTier).first
        let knownRemainings = windows.compactMap(\.remainingPercent)
        let effective: Double? = knownRemainings.isEmpty ? nil : knownRemainings.min()

        let allUnknown = windows.allSatisfy { $0.unknownReason != nil }
        if allUnknown {
            let reason = windows.lazy.compactMap(\.unknownReason).first ?? .neverSampled
            return CapacityBenchRow(
                source: source,
                planTier: planTier,
                pools: [],
                effectiveRemainingPercent: nil,
                rawWindows: windows,
                unknownReason: reason
            )
        }

        let poolKeys = poolKeyOrder(in: windows)
        let pools = poolKeys.map { key in
            let poolWindows = windows.filter { poolKey(of: $0) == key }
            return poolMetrics(poolLabel: key, windows: poolWindows)
        }

        return CapacityBenchRow(
            source: source,
            planTier: planTier,
            pools: pools,
            effectiveRemainingPercent: effective,
            rawWindows: windows,
            unknownReason: nil
        )
    }

    private static func poolMetrics(
        poolLabel: String?,
        windows: [CapacityWindow]
    ) -> CapacityBenchPoolMetrics {
        let dashboard = selectDashboard(from: windows)
        let short = selectShortWindow(from: windows, poolLabel: poolLabel)

        if let dashboard, dashboard.unknownReason == nil {
            return CapacityBenchPoolMetrics(
                poolLabel: poolLabel,
                dashboardScope: dashboard.scope,
                dashboardRemainingPercent: dashboard.remainingPercent,
                dashboardUsedPercent: dashboard.usedPercent,
                dashboardResetAt: dashboard.resetAt,
                dashboardResetPrecision: dashboard.resetPrecision,
                shortWindow: short,
                unknownReason: nil
            )
        }

        // No known weekly/monthly: surface pool-level unknown if present, else nils.
        let reason = dashboard?.unknownReason
            ?? windows.lazy.compactMap(\.unknownReason).first
        return CapacityBenchPoolMetrics(
            poolLabel: poolLabel,
            dashboardScope: dashboard?.scope,
            dashboardRemainingPercent: nil,
            dashboardUsedPercent: nil,
            dashboardResetAt: nil,
            dashboardResetPrecision: dashboard?.resetPrecision,
            shortWindow: short,
            unknownReason: reason
        )
    }

    /// Weekly preferred, else monthly. Never fiveHour/session/planClass.
    private static func selectDashboard(from windows: [CapacityWindow]) -> CapacityWindow? {
        let weekly = windows.filter { $0.scope == .weekly }
        if let known = newestKnown(in: weekly) { return known }
        if let unknown = newest(in: weekly) { return unknown }

        let monthly = windows.filter { $0.scope == .monthly }
        if let known = newestKnown(in: monthly) { return known }
        if let unknown = newest(in: monthly) { return unknown }
        return nil
    }

    /// Sources that **have** a short (5h / session) limit — a product fact about
    /// the vendor, not a fact about this sample.
    ///
    /// Whether a short window has a limit and whether we currently hold a sample
    /// of it are different questions, and `.none` only ever answers the first.
    /// Deriving `.none` from "no short window in this batch" conflated them:
    /// Claude's session window closes every ~5h, so as soon as the last sample
    /// aged out of the open-history filter the strip printed the same `-` as Grok
    /// and Cursor, which genuinely have no short limit at all.
    public static let sourcesWithShortWindow: Set<String> = [
        "claude_code",
        "kimi",
        "opencode_go",
    ]

    /// Short column: `fiveHour` (agy/kimi) **or** `session` (Claude).
    /// Session is Claude's short limit — treating it as "no short window" blanked
    /// the 5h column while the Usage pane showed Current session.
    ///
    /// `poolLabel` is nil for the flat/primary pool. A short limit belongs to the
    /// seat, not to a weekly sub-pool, so only the primary pool falls back to
    /// `unknown`; a labeled pool with no short sample stays `.none`.
    private static func selectShortWindow(
        from windows: [CapacityWindow],
        poolLabel: String?
    ) -> CapacityShortWindowState {
        let shorts = windows.filter { $0.scope == .fiveHour || $0.scope == .session }
        guard !shorts.isEmpty else {
            guard poolLabel == nil,
                  let source = windows.first?.source,
                  sourcesWithShortWindow.contains(source)
            else { return .none }
            // Declared short limit, no sample of the current window — say so.
            let reason = windows.lazy.compactMap(\.unknownReason).first ?? .neverSampled
            return .unknown(reason)
        }

        if let known = newestKnown(in: shorts),
           let remaining = known.remainingPercent,
           let used = known.usedPercent {
            return .known(
                remainingPercent: remaining,
                usedPercent: used,
                resetAt: known.resetAt,
                resetPrecision: known.resetPrecision,
                observedAt: known.observedAt
            )
        }
        let reason = newest(in: shorts)?.unknownReason ?? .neverSampled
        return .unknown(reason)
    }

    private static func newestKnown(in windows: [CapacityWindow]) -> CapacityWindow? {
        windows
            .filter { $0.unknownReason == nil && $0.remainingPercent != nil }
            .max(by: { $0.observedAt < $1.observedAt })
    }

    private static func newest(in windows: [CapacityWindow]) -> CapacityWindow? {
        windows.max(by: { $0.observedAt < $1.observedAt })
    }

    private static func poolKey(of window: CapacityWindow) -> String? {
        window.poolLabel
    }

    /// First-seen pool labels; nil (flat) comes first when mixed.
    private static func poolKeyOrder(in windows: [CapacityWindow]) -> [String?] {
        var order: [String?] = []
        var seen = Set<String>()
        var sawNil = false
        for window in windows {
            if let label = window.poolLabel {
                if seen.insert(label).inserted {
                    order.append(label)
                }
            } else if !sawNil {
                sawNil = true
                order.insert(nil, at: 0)
            }
        }
        if order.isEmpty { return [nil] }
        return order
    }
}
