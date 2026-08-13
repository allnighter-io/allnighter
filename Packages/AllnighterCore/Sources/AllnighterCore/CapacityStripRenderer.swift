import Foundation

// MARK: - JSON shape (`alln capacity --json` / CapacityStripJSON)

/// Machine-readable capacity strip. Carries `contractVersion` like HistoryJSON /
/// DriverListJSON so agents can detect a stale cached surface.
public struct CapacityStripJSON: Sendable, Equatable, Codable {
    public let schemaVersion: Int
    public let contractVersion: String
    public let generatedAt: Date
    public let rows: [CapacityStripJSONRow]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        generatedAt: Date,
        rows: [CapacityStripJSONRow]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.generatedAt = generatedAt
        self.rows = rows
    }
}

public struct CapacityStripJSONRow: Sendable, Equatable, Codable {
    public let source: String
    public let displayName: String
    public let planTier: String?
    public let color: CapacityStripColor
    /// Weekly/monthly remaining when known.
    public let dashboardRemainingPercent: Double?
    public let dashboardScope: CapacityWindowScope?
    public let dashboardResetAt: Date?
    /// The short window's own remaining, or nil when none/unknown. Not floored by
    /// the row ceiling — that is `effectiveRemainingPercent`.
    public let shortRemainingPercent: Double?
    /// `true` when the seat has no short window at all (rendered `n/a`). Distinct
    /// from a `nil` remaining with `false` here, which means "has one, unsampled".
    public let shortWindowNone: Bool
    public let effectiveRemainingPercent: Double?
    public let observedAt: Date?
    public let observedAgeSeconds: Double?
    public let unknownReason: CapacityStripUnknownKind?
    /// Same shape as `benchTally.nextAction` when the unknown has a known fix.
    public let nextAction: AgentSurfaceNextAction?
    public let pools: [CapacityStripJSONPool]

    public init(
        source: String,
        displayName: String,
        planTier: String?,
        color: CapacityStripColor,
        dashboardRemainingPercent: Double?,
        dashboardScope: CapacityWindowScope?,
        dashboardResetAt: Date?,
        shortRemainingPercent: Double?,
        shortWindowNone: Bool,
        effectiveRemainingPercent: Double?,
        observedAt: Date?,
        observedAgeSeconds: Double?,
        unknownReason: CapacityStripUnknownKind?,
        nextAction: AgentSurfaceNextAction? = nil,
        pools: [CapacityStripJSONPool]
    ) {
        self.source = source
        self.displayName = displayName
        self.planTier = planTier
        self.color = color
        self.dashboardRemainingPercent = dashboardRemainingPercent
        self.dashboardScope = dashboardScope
        self.dashboardResetAt = dashboardResetAt
        self.shortRemainingPercent = shortRemainingPercent
        self.shortWindowNone = shortWindowNone
        self.effectiveRemainingPercent = effectiveRemainingPercent
        self.observedAt = observedAt
        self.observedAgeSeconds = observedAgeSeconds
        self.unknownReason = unknownReason
        self.nextAction = nextAction
        self.pools = pools
    }
}

public struct CapacityStripJSONPool: Sendable, Equatable, Codable {
    public let poolLabel: String?
    public let dashboardRemainingPercent: Double?
    public let dashboardResetAt: Date?
    public let shortRemainingPercent: Double?
    public let shortWindowNone: Bool
    public let unknownReason: CapacityStripUnknownKind?

    public init(
        poolLabel: String?,
        dashboardRemainingPercent: Double?,
        dashboardResetAt: Date?,
        shortRemainingPercent: Double?,
        shortWindowNone: Bool,
        unknownReason: CapacityStripUnknownKind?
    ) {
        self.poolLabel = poolLabel
        self.dashboardRemainingPercent = dashboardRemainingPercent
        self.dashboardResetAt = dashboardResetAt
        self.shortRemainingPercent = shortRemainingPercent
        self.shortWindowNone = shortWindowNone
        self.unknownReason = unknownReason
    }
}

/// Three mutually exclusive strip colours. Nothing is green.
public enum CapacityStripColor: String, Sendable, Equatable, Codable {
    /// Room to work.
    case neutral
    /// Headroom with a deadline (hero-eligible window).
    case amber
    /// No headroom.
    case red
}

/// Stable JSON encoding of `CapacityUnknownReason` (associated values flatten).
public enum CapacityStripUnknownKind: String, Sendable, Equatable, Codable {
    case vendorExposesNothing
    case parserFailed
    case neverSampled
    case spawnFailed
    case probeTimeout
    case emptyCapture
    case expired
    case disabled
    case authRequired
    case notConfigured
    case notInstalled
}

// MARK: - Renderer

/// Pure strip renderer over `CapacityBenchRow`s. `now` is always a parameter.
///
/// Fixed display order (product law — never sorted by expiry or remaining):
/// Codex/ChatGPT, Claude, Cursor, Grok, Kimi, Antigravity; not-ready / parked last.
public enum CapacityStripRenderer {

    /// Locked product order by source id.
    /// Derived, not a second hand-maintained list. It used to be an
    /// independent copy of the bench roster, which meant promoting a seat in
    /// one place silently dropped it from the strip in the other.
    public static let displayOrder: [String] = CapacityAcquisition.benchSourceOrder

    public static let defaultWidth = 80

    // MARK: - Order

    /// Fixed display order. Known seats first in product order; any other
    /// sources next (first-seen); `notReadyOrParked` last in the same relative order.
    public static func ordered(
        rows: [CapacityBenchRow],
        notReadyOrParked: Set<String> = []
    ) -> [CapacityBenchRow] {
        let bySource = Dictionary(uniqueKeysWithValues: rows.map { ($0.source, $0) })
        var seen = Set<String>()
        var ready: [CapacityBenchRow] = []
        var deferred: [CapacityBenchRow] = []

        func place(_ source: String) {
            guard let row = bySource[source], seen.insert(source).inserted else { return }
            if notReadyOrParked.contains(source) {
                deferred.append(row)
            } else {
                ready.append(row)
            }
        }

        for source in displayOrder { place(source) }
        for row in rows where !seen.contains(row.source) {
            place(row.source)
        }
        return ready + deferred
    }

    // MARK: - Display names

    public static func displayName(for source: String) -> String {
        switch source {
        case "codex": return "Codex/ChatGPT"
        case "claude_code": return "Claude"
        case "cursor_agent", "cursor": return "Cursor"
        case "grok": return "Grok"
        case "kimi": return "Kimi"
        case "agy", "antigravity": return "Antigravity"
        // CLI name is OpenCode; "Go" is the plan tier (shown under the name).
        case "opencode_go": return "OpenCode"
        case "bailian_token_plan": return "Qwen"
        default: return source
        }
    }

    // MARK: - Meter lines (GUI: one measured capacity = one row)

    /// Flattened strip row: if we measure it, it gets a row.
    ///
    /// Multi-pool CLIs (Antigravity Gemini + Claude/GPT) become adjacent sibling
    /// lines titled `Antigravity · Gemini`, not nested pool columns inside one
    /// CLI row. Seat count stays "how many CLIs", not how many meter lines.
    public struct CapacityMeterLine: Sendable, Equatable, Identifiable {
        public var id: String { "\(source)#\(poolOrdinal)" }
        public let source: String
        /// Stable index within the parent CLI's pool order (0 for a single meter).
        public let poolOrdinal: Int
        /// `Antigravity · Gemini`, or just `OpenCode` when there is no pool name.
        public let title: String
        public let planTier: String?
        /// First meter of a CLI — owns expand disclosure + trailing age/refresh chrome.
        public let isFirstOfSource: Bool
        public let pool: CapacityBenchPoolMetrics?
        public let rowUnknownReason: CapacityUnknownReason?

        public init(
            source: String,
            poolOrdinal: Int,
            title: String,
            planTier: String?,
            isFirstOfSource: Bool,
            pool: CapacityBenchPoolMetrics?,
            rowUnknownReason: CapacityUnknownReason?
        ) {
            self.source = source
            self.poolOrdinal = poolOrdinal
            self.title = title
            self.planTier = planTier
            self.isFirstOfSource = isFirstOfSource
            self.pool = pool
            self.rowUnknownReason = rowUnknownReason
        }

        /// One meter line per measured pool, CLI siblings kept adjacent in
        /// `rows` order. Unnamed single pools keep the bare CLI title; unnamed
        /// pools on a multi-pool seat read `Total`.
        public static func flatten(rows: [CapacityBenchRow]) -> [CapacityMeterLine] {
            var lines: [CapacityMeterLine] = []
            for row in rows {
                let seat = displayName(for: row.source)
                let ordered = orderedPools(in: row)
                if ordered.isEmpty {
                    lines.append(
                        CapacityMeterLine(
                            source: row.source,
                            poolOrdinal: 0,
                            title: seat,
                            planTier: row.planTier,
                            isFirstOfSource: true,
                            pool: nil,
                            rowUnknownReason: row.unknownReason
                        )
                    )
                    continue
                }
                for (index, pool) in ordered.enumerated() {
                    let suffix = poolTitleSuffix(pool, poolCount: ordered.count)
                    let title = suffix.isEmpty ? seat : "\(seat) · \(suffix)"
                    lines.append(
                        CapacityMeterLine(
                            source: row.source,
                            poolOrdinal: index,
                            title: title,
                            planTier: row.planTier,
                            isFirstOfSource: index == 0,
                            pool: pool,
                            rowUnknownReason: row.unknownReason
                        )
                    )
                }
            }
            return lines
        }

        /// Unnamed pools first (as `Total` when siblings exist), then vendor-named.
        private static func orderedPools(in row: CapacityBenchRow) -> [CapacityBenchPoolMetrics] {
            let unnamed = row.pools.filter { ($0.poolLabel ?? "").isEmpty }
            let named = row.pools.filter { !($0.poolLabel ?? "").isEmpty }
            return unnamed + named
        }

        private static func poolTitleSuffix(
            _ pool: CapacityBenchPoolMetrics,
            poolCount: Int
        ) -> String {
            guard let label = pool.poolLabel, !label.isEmpty else {
                return poolCount > 1 ? "Total" : ""
            }
            return compressPoolLabel(label)
        }
    }

    // MARK: - Colour

    /// Mutual exclusive: red (empty) > amber (headroom with deadline) > neutral.
    public static func color(for row: CapacityBenchRow, now: Date) -> CapacityStripColor {
        if row.unknownReason != nil { return .neutral }
        if let effective = row.effectiveRemainingPercent, effective <= CapacityWindow.emptyRemainingThreshold {
            return .red
        }
        // Any pool with known remaining at 0 also paints red.
        let anyEmpty = row.pools.contains { pool in
            if let r = pool.dashboardRemainingPercent, r <= CapacityWindow.emptyRemainingThreshold {
                return true
            }
            if case .known(let rem, _, _, _, _) = pool.shortWindow,
               rem <= CapacityWindow.emptyRemainingThreshold {
                return true
            }
            return false
        }
        if anyEmpty { return .red }
        if row.isHeroEligible(at: now) { return .amber }
        return .neutral
    }

    // MARK: - Text render

    /// TTY variant: aligned columns, bar glyphs, relative clocks, ANSI colour.
    public static func renderTTY(
        rows: [CapacityBenchRow],
        now: Date,
        width: Int = defaultWidth,
        notReadyOrParked: Set<String> = []
    ) -> String {
        render(rows: rows, now: now, width: width, tty: true, notReadyOrParked: notReadyOrParked)
    }

    /// Non-TTY variant: plain aligned ASCII. Zero ANSI, no box-drawing.
    public static func renderPlain(
        rows: [CapacityBenchRow],
        now: Date,
        width: Int = defaultWidth,
        notReadyOrParked: Set<String> = []
    ) -> String {
        render(rows: rows, now: now, width: width, tty: false, notReadyOrParked: notReadyOrParked)
    }

    /// JSON payload for `alln capacity --json` (and GUI consumers).
    public static func json(
        rows: [CapacityBenchRow],
        now: Date,
        notReadyOrParked: Set<String> = [],
        contractVersion: String = ContractRegistry.contractVersion
    ) -> CapacityStripJSON {
        let orderedRows = ordered(rows: rows, notReadyOrParked: notReadyOrParked)
        let jsonRows = orderedRows.map { jsonRow(from: $0, now: now) }
        return CapacityStripJSON(
            contractVersion: contractVersion,
            generatedAt: now,
            rows: jsonRows
        )
    }

    // MARK: - Internals

    private static func render(
        rows: [CapacityBenchRow],
        now: Date,
        width: Int,
        tty: Bool,
        notReadyOrParked: Set<String>
    ) -> String {
        let cols = max(40, width)
        let orderedRows = ordered(rows: rows, notReadyOrParked: notReadyOrParked)

        // Column budget (default 80):
        // name 16 | plan 12 | weekly bar+pct+left+clock 28 | short 11 | age 10  ≈ 78
        //
        // Weekly worst case is `-------- 52.1% left 20h 47m` = 27, so the column
        // carries one spare char; `pad` hard-cuts, and a silently clipped reset
        // clock is exactly the kind of quiet lie this strip exists to avoid.
        // Short worst case is `52.1% left` / `parse fail` = 10.
        let nameW = min(16, max(10, cols / 5))
        let planW = min(12, max(6, cols / 7))
        let ageW = 10
        let shortW = 11
        let weeklyW = max(18, cols - nameW - planW - shortW - ageW - 4)

        var lines: [String] = []
        lines.append(contentsOf: expiringBanner(rows: orderedRows, now: now, nameW: nameW))
        let header = pad("CLI", nameW) + " " + pad("Plan", planW) + " "
            + pad("Weekly/monthly", weeklyW) + " " + pad("5h", shortW) + " "
            + pad("Age", ageW)
        lines.append(header)
        lines.append(String(repeating: "-", count: min(cols, header.count)))

        for row in orderedRows {
            let color = color(for: row, now: now)
            let name = pad(displayName(for: row.source), nameW)
            let plan = pad(row.planTier ?? "-", planW)
            let age = pad(ageLabel(for: row, now: now), ageW)

            if let reason = row.unknownReason {
                let weekly = pad(unknownCopy(reason), weeklyW)
                // A wholly-unknown row has no pools to consult, but "we know
                // nothing about this seat" must not read as "this seat has no
                // short limit" — that is the one thing `-` is reserved for.
                let short = CapacityBenchProjection.sourcesWithShortWindow.contains(row.source)
                    ? pad(unknownShortCopy(reason), shortW)
                    : pad(noShortWindowCell, shortW)
                var line = "\(name) \(plan) \(weekly) \(short) \(age)"
                if tty { line = ansi(line, color: color) }
                lines.append(line)
                continue
            }

            // Multi-pool: one line per pool; seat name + age on first line only.
            // Pool short label always occupies the plan column so Gemini vs Claude/GPT
            // stay visible without inventing a second seat row.
            if row.pools.count > 1 {
                for (idx, pool) in row.pools.enumerated() {
                    let labelPrefix = idx == 0 ? name : pad("", nameW)
                    let poolTag: String
                    if let label = pool.poolLabel, !label.isEmpty {
                        poolTag = compressPoolLabel(label)
                    } else {
                        poolTag = idx == 0 ? (row.planTier ?? "-") : "-"
                    }
                    let planCell = pad(poolTag, planW)
                    let ageCell = idx == 0 ? age : pad("", ageW)
                    let weekly = pad(dashboardCell(pool: pool, now: now, barWidth: 8), weeklyW)
                    let short = pad(shortCell(pool: pool, row: row), shortW)
                    var line = "\(labelPrefix) \(planCell) \(weekly) \(short) \(ageCell)"
                    if tty { line = ansi(line, color: color) }
                    lines.append(line)
                }
                continue
            }

            let pool = row.pools.first
            let weekly = pad(
                pool.map { dashboardCell(pool: $0, now: now, barWidth: 8) } ?? "-",
                weeklyW
            )
            let short = pad(
                pool.map { shortCell(pool: $0, row: row) } ?? "-",
                shortW
            )
            var line = "\(name) \(plan) \(weekly) \(short) \(age)"
            if tty { line = ansi(line, color: color) }
            lines.append(line)
        }

        var seenCommands = Set<String>()
        var remedies: [AgentSurfaceNextAction] = []
        for row in orderedRows {
            guard let reason = row.unknownReason,
                  let next = CapacityUnknownRemedy.nextAction(source: row.source, reason: reason),
                  seenCommands.insert(next.command).inserted
            else { continue }
            remedies.append(next)
        }
        if !remedies.isEmpty {
            lines.append("")
            for next in remedies {
                lines.append("→ \(next.command)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Expiring banner

    /// Lines above the strip naming capacity that is about to evaporate.
    ///
    /// This is not a second metric — it is the strip's own remaining number with
    /// the opposite valence, which is why it reads `unused` here and `left` in the
    /// table. Headroom you will not reach before the reset is waste; the same
    /// headroom you can still spend is capacity. The reset clock is what decides
    /// which one you are looking at, so it is never omitted.
    ///
    /// Selection is `isHeroEligible` — the already-tested "real headroom on a
    /// window that expires soon" predicate that also paints the row amber. It is
    /// deliberately restricted to dashboard (weekly/monthly) windows: a 5h window
    /// always satisfies "expires soon", so including short windows would fire on
    /// every attended session and mean nothing.
    ///
    /// Observed facts only — `N% unused` and a reset clock. Never a projection of
    /// what will be wasted.
    ///
    /// Multi-pool seats use binding headroom (tightest pool). A sub-pool with spare
    /// credits must not earn a line when the primary pool is nearly exhausted.
    private static func expiringBannerLabel(for row: CapacityBenchRow) -> String {
        let seat = displayName(for: row.source)
        guard row.pools.count == 1,
              let label = row.pools[0].poolLabel
        else { return seat }
        return "\(seat) \(compressPoolLabel(label))"
    }

    static func expiringBanner(
        rows: [CapacityBenchRow],
        now: Date,
        nameW: Int
    ) -> [String] {
        var entries: [(name: String, remaining: Double, resetAt: Date)] = []
        for row in rows where row.unknownReason == nil {
            guard let binding = row.heroBinding(at: now) else { continue }
            entries.append((
                expiringBannerLabel(for: row),
                binding.remaining,
                binding.resetAt
            ))
        }
        guard !entries.isEmpty else { return [] }
        // Soonest reset first — that is the one you lose first.
        entries.sort { $0.resetAt < $1.resetAt }
        // Size to the widest label. The banner is not in the table's column
        // budget, so borrowing the table's name width only bought a hard cut
        // ("Antigravity Claude/GPT" → "Antigravity Clau") — a clipped seat name
        // is the same quiet lie as a clipped reset clock.
        let labelW = max(nameW, entries.map(\.name.count).max() ?? nameW)
        var out = ["Expiring soon with headroom:"]
        for entry in entries {
            let name = pad(entry.name, labelW)
            out.append(
                "  \(name) \(formatPercent(entry.remaining)) unused · resets \(relativeClock(from: now, to: entry.resetAt))"
            )
        }
        out.append("")
        return out
    }

    private static func jsonRow(from row: CapacityBenchRow, now: Date) -> CapacityStripJSONRow {
        let primary = row.pools.first
        let short = primary.map { shortPresentation(pool: $0, row: row) }
        let observed = observedAt(for: row)
        let age: Double? = observed.map { now.timeIntervalSince($0) }
        return CapacityStripJSONRow(
            source: row.source,
            displayName: displayName(for: row.source),
            planTier: row.planTier,
            color: color(for: row, now: now),
            dashboardRemainingPercent: primary?.dashboardRemainingPercent,
            dashboardScope: primary?.dashboardScope,
            dashboardResetAt: primary?.dashboardResetAt,
            shortRemainingPercent: short?.remaining,
            // A wholly-unknown row has no pools to consult. Mirrors the text row:
            // "we know nothing about this seat" must not serialize as "this seat
            // has no short limit" — that is the one claim `true` is reserved for.
            shortWindowNone: short?.isNone
                ?? !CapacityBenchProjection.sourcesWithShortWindow.contains(row.source),
            effectiveRemainingPercent: row.effectiveRemainingPercent,
            observedAt: observed,
            observedAgeSeconds: age,
            unknownReason: row.unknownReason.map(stripUnknownKind),
            nextAction: row.unknownReason.flatMap {
                CapacityUnknownRemedy.nextAction(source: row.source, reason: $0)
            },
            pools: row.pools.map { pool in
                let s = shortPresentation(pool: pool, row: row)
                return CapacityStripJSONPool(
                    poolLabel: pool.poolLabel,
                    dashboardRemainingPercent: pool.dashboardRemainingPercent,
                    dashboardResetAt: pool.dashboardResetAt,
                    shortRemainingPercent: s.remaining,
                    shortWindowNone: s.isNone,
                    unknownReason: pool.unknownReason.map(stripUnknownKind)
                )
            }
        )
    }

    // MARK: - Cells

    private static func dashboardCell(
        pool: CapacityBenchPoolMetrics,
        now: Date,
        barWidth: Int
    ) -> String {
        if let reason = pool.unknownReason, pool.dashboardRemainingPercent == nil {
            return unknownCopy(reason)
        }
        guard let remaining = pool.dashboardRemainingPercent else {
            return "-"
        }
        let pct = formatPercent(remaining)
        let clock: String
        if let resetAt = pool.dashboardResetAt {
            clock = relativeClock(from: now, to: resetAt)
        } else {
            clock = "-"
        }
        let bar = barGlyph(remainingPercent: remaining, width: barWidth)
        return "\(bar) \(pct) \(remainingSuffix) \(clock)"
    }

    /// Six vendors print capacity in three different polarities (Claude and Grok
    /// print used, Codex prints left), so a bare number in a normalized table is
    /// unreadable without knowing which way *we* normalized. The suffix rides on
    /// the value rather than the header because rows get screenshotted and pasted
    /// one at a time, and a header does not survive the trip.
    public static let remainingSuffix = "left"

    /// Short cell for a seat that **has no** 5h/session limit (Grok, Cursor, Codex).
    ///
    /// Not blank: blank already means "not applicable to this line" on the
    /// continuation rows of a pooled seat, and an empty cell reads as a rendering
    /// failure — the same ambiguity `.none` vs `unknown` exists to remove. Not a
    /// bare `-` either: the Plan column spends `-` on "no tier", so it degrades to
    /// generic "nothing here" rather than the specific claim being made.
    public static let noShortWindowCell = "n/a"

    /// Short column: effective availability when a short window exists; `-` when none.
    private static func shortCell(pool: CapacityBenchPoolMetrics, row: CapacityBenchRow) -> String {
        let pres = shortPresentation(pool: pool, row: row)
        if pres.isNone { return noShortWindowCell }
        if let remaining = pres.remaining {
            return "\(formatPercent(remaining)) \(remainingSuffix)"
        }
        if let reason = pres.reason {
            return unknownShortCopy(reason)
        }
        return "-"
    }

    private struct ShortPresentation {
        let remaining: Double?
        let isNone: Bool
        let reason: CapacityUnknownReason?
    }

    /// The short column reports **available** capacity in the short window.
    ///
    /// Two rules, because the old single rule conflated them:
    ///
    /// 1. **Between 0 and 100, report the short window's own number.** A weekly
    ///    percentage and a 5h percentage have different denominators, so `min()`
    ///    across them is not "effective availability" — it is a heuristic. It cost
    ///    us the real number: Claude session 86% under a 47% weekly rendered 47%,
    ///    so a column headed `5h` never once showed the 5h figure while the weekly
    ///    was tighter. Whether spending a full 5h window would exhaust the weekly
    ///    depends on relative allowance sizes no vendor publishes; we must not
    ///    invent that arithmetic.
    ///
    /// 2. **Exhaustion is a hard gate, not a comparison.** A depleted weekly makes
    ///    the 5h window unspendable regardless of what the vendor prints for it.
    ///    Kimi prints `100%` on a 5h window sitting under an exhausted weekly;
    ///    repeating that would invite seating a seat that fails on first dispatch.
    ///    We claim to be more honest than the vendor surface, so 0 available reads
    ///    as 0.
    private static func shortPresentation(
        pool: CapacityBenchPoolMetrics,
        row _: CapacityBenchRow
    ) -> ShortPresentation {
        switch pool.shortWindow {
        case .none:
            return ShortPresentation(remaining: nil, isNone: true, reason: nil)
        case .unknown(let reason):
            return ShortPresentation(remaining: nil, isNone: false, reason: reason)
        case .known(let shortRemaining, _, _, _, _):
            if isBlockedByExhaustedDashboard(pool: pool) {
                return ShortPresentation(remaining: 0, isNone: false, reason: nil)
            }
            return ShortPresentation(remaining: shortRemaining, isNone: false, reason: nil)
        }
    }

    /// True when **this pool's** weekly/monthly window is spent. The short window
    /// cannot be spent through an exhausted long window in the **same** pool.
    ///
    /// Multi-pool seats (agy Gemini vs Claude/GPT) share one CLI row but not one
    /// quota bucket — another pool's exhausted weekly must not zero this pool's
    /// 5h figure while the vendor still shows headroom there.
    private static func isBlockedByExhaustedDashboard(pool: CapacityBenchPoolMetrics) -> Bool {
        guard let dashboard = pool.dashboardRemainingPercent else { return false }
        return dashboard <= CapacityWindow.emptyRemainingThreshold
    }

    // MARK: - Formatting

    public static func formatPercent(_ value: Double) -> String {
        if value == value.rounded(.towardZero) && abs(value - value.rounded()) < 0.05 {
            return "\(Int(value.rounded()))%"
        }
        // One decimal when fractional.
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))%"
        }
        return String(format: "%.1f%%", rounded)
    }

    /// Relative clock: `6d 3h`, `3h 21m`, `41h`, `12m`. Past reset → `now`.
    public static func relativeClock(from now: Date, to resetAt: Date) -> String {
        let seconds = resetAt.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            if hours > 0 { return "\(days)d \(hours)h" }
            return "\(days)d"
        }
        if hours > 0 {
            if minutes > 0 { return "\(hours)h \(minutes)m" }
            return "\(hours)h"
        }
        return "\(max(1, minutes))m"
    }

    /// Age of the newest observation on the row: `2m ago`, `1h ago`, `3d ago`.
    public static func ageLabel(for row: CapacityBenchRow, now: Date) -> String {
        guard let observed = observedAt(for: row) else { return "-" }
        return elapsedLabel(from: observed, to: now)
    }

    /// Row age with no "ago" — `2m`, `1h`, `3d`.
    ///
    /// The suffix is a sentence ending, and a column of eight of them is a
    /// stutter. The header says "ago" once, in prose, where it reads.
    public static func bareAgeLabel(for row: CapacityBenchRow, now: Date) -> String {
        let label = ageLabel(for: row, now: now)
        guard label.hasSuffix(" ago") else { return label }
        return String(label.dropLast(4))
    }

    /// How long ago something happened, in the strip's one age vocabulary.
    ///
    /// Row age chips and the header's freshness line are the same claim at two
    /// scopes; they must never disagree about what "4m ago" means, so they read
    /// the same formatter.
    public static func elapsedLabel(from observed: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(observed))
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 1 { return "now" }
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d ago" }
        if hours > 0 { return "\(hours)h ago" }
        return "\(minutes)m ago"
    }

    public static func unknownCopy(_ reason: CapacityUnknownReason) -> String {
        switch reason {
        case .vendorExposesNothing:
            return "unknown — no usage surface"
        case .parserFailed(let at):
            // Compact day stamp so default 80-col weekly cell never mid-cuts the year
            // ("unknown — parser failed 202…"). Full ISO lives in JSON/observedAt.
            return "unknown — parser failed \(dayStampCompact(at))"
        case .neverSampled:
            return "not checked yet"
        case .spawnFailed(let at):
            return "spawn failed \(dayStampCompact(at))"
        case .probeTimeout(let at):
            return "probe timeout \(dayStampCompact(at))"
        case .emptyCapture(let at):
            return "unknown — empty capture \(dayStampCompact(at))"
        case .expired(let at):
            return "unknown — expired \(dayStampCompact(at))"
        case .disabled:
            return "disabled — capacity feature OFF"
        case .authRequired(let at):
            return "unknown — auth required \(dayStampCompact(at))"
        case .notConfigured:
            return "not set up"
        case .notInstalled:
            return "not installed"
        }
    }

    private static func unknownShortCopy(_ reason: CapacityUnknownReason) -> String {
        switch reason {
        case .vendorExposesNothing: return "unknown"
        case .parserFailed: return "parse fail"
        case .neverSampled: return "not yet"
        case .spawnFailed: return "spawn fail"
        case .probeTimeout: return "timeout"
        case .emptyCapture: return "empty"
        case .expired: return "expired"
        case .disabled: return "disabled"
        case .authRequired: return "auth req"
        case .notConfigured: return "not set up"
        case .notInstalled: return "not inst"
        }
    }

    /// Full ISO day for machine surfaces.
    private static func dayStamp(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Short UTC stamp for the weekly column: `07-30` (year is already on Age / JSON).
    private static func dayStampCompact(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.month, .day], from: date)
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%02d-%02d", m, d)
    }

    private static func barGlyph(remainingPercent: Double, width: Int) -> String {
        let w = max(4, width)
        let clamped = min(100.0, max(0.0, remainingPercent))
        let filled = Int((clamped / 100.0 * Double(w)).rounded(.towardZero))
        let empty = w - filled
        // ASCII only — no box-drawing (TTY colour is applied to the whole line, not the bar).
        return String(repeating: "#", count: filled) + String(repeating: "-", count: empty)
    }

    private static func compressPoolLabel(_ label: String) -> String {
        // "GEMINI MODELS" → "Gemini"; "CLAUDE AND GPT MODELS" → "Claude/GPT"
        let upper = label.uppercased()
        if upper.contains("GEMINI") { return "Gemini" }
        if upper.contains("CLAUDE") && upper.contains("GPT") { return "Claude/GPT" }
        if upper.contains("CLAUDE") { return "Claude" }
        if label.count <= 10 { return label }
        return String(label.prefix(10))
    }

    /// Newest observation on the row, or nil when nothing on it was sampled.
    ///
    /// Public because a surface that hides per-row ages needs to prove they all
    /// agree before hiding them — a row whose age cannot be determined must be
    /// able to say so rather than inherit the bench's timestamp by silence.
    public static func observedAt(for row: CapacityBenchRow) -> Date? {
        if let raw = row.rawWindows.map(\.observedAt).max() {
            return raw
        }
        var dates: [Date] = []
        for pool in row.pools {
            if case .known(_, _, _, _, let at) = pool.shortWindow {
                dates.append(at)
            }
        }
        return dates.max()
    }

    private static func stripUnknownKind(_ reason: CapacityUnknownReason) -> CapacityStripUnknownKind {
        switch reason {
        case .vendorExposesNothing: return .vendorExposesNothing
        case .parserFailed: return .parserFailed
        case .neverSampled: return .neverSampled
        case .spawnFailed: return .spawnFailed
        case .probeTimeout: return .probeTimeout
        case .emptyCapture: return .emptyCapture
        case .expired: return .expired
        case .disabled: return .disabled
        case .authRequired: return .authRequired
        case .notConfigured: return .notConfigured
        case .notInstalled: return .notInstalled
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        if text.count == width { return text }
        if text.count > width {
            // Hard cut — no mid-word ellipsis (reads as noise in agent transcripts).
            return String(text.prefix(width))
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    // MARK: - ANSI (TTY only)

    private static let esc = "\u{1B}"

    private static func ansi(_ line: String, color: CapacityStripColor) -> String {
        let code: String
        switch color {
        case .neutral: return line // quiet is good news — no colour
        case .amber: code = "33" // yellow/amber
        case .red: code = "31"
        }
        return "\(esc)[0;\(code)m\(line)\(esc)[0m"
    }
}
