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
    /// Short-window remaining after effective-availability floor, or nil when none.
    public let shortRemainingPercent: Double?
    /// `true` when the seat has no short window (render as `-`).
    public let shortWindowNone: Bool
    public let effectiveRemainingPercent: Double?
    public let observedAt: Date?
    public let observedAgeSeconds: Double?
    public let unknownReason: CapacityStripUnknownKind?
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
}

// MARK: - Renderer

/// Pure strip renderer over `CapacityBenchRow`s. `now` is always a parameter.
///
/// Fixed display order (product law — never sorted by expiry or remaining):
/// Codex/ChatGPT, Claude, Cursor, Grok, Kimi, Antigravity; not-ready / parked last.
public enum CapacityStripRenderer {

    /// Locked product order by source id.
    public static let displayOrder: [String] = [
        "codex",
        "claude_code",
        "cursor_agent",
        "grok",
        "kimi",
        "agy",
    ]

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
        default: return source
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
        // name 16 | plan 12 | weekly bar+pct+clock 28 | short 12 | age 10  ≈ 78
        let nameW = min(16, max(10, cols / 5))
        let planW = min(12, max(6, cols / 7))
        let ageW = 10
        let shortW = 12
        let weeklyW = max(18, cols - nameW - planW - shortW - ageW - 4)

        var lines: [String] = []
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
                let short = pad("-", shortW)
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

        return lines.joined(separator: "\n") + "\n"
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
            shortWindowNone: short?.isNone ?? true,
            effectiveRemainingPercent: row.effectiveRemainingPercent,
            observedAt: observed,
            observedAgeSeconds: age,
            unknownReason: row.unknownReason.map(stripUnknownKind),
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
        return "\(bar) \(pct) \(clock)"
    }

    /// Short column: effective availability when a short window exists; `-` when none.
    private static func shortCell(pool: CapacityBenchPoolMetrics, row: CapacityBenchRow) -> String {
        let pres = shortPresentation(pool: pool, row: row)
        if pres.isNone { return "-" }
        if let remaining = pres.remaining {
            return formatPercent(remaining)
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

    /// Effective availability in the short column when a short window exists.
    /// Kimi weekly 0% + 5h 100% → short shows 0% (row effective), not 100%.
    private static func shortPresentation(
        pool: CapacityBenchPoolMetrics,
        row: CapacityBenchRow
    ) -> ShortPresentation {
        switch pool.shortWindow {
        case .none:
            return ShortPresentation(remaining: nil, isNone: true, reason: nil)
        case .unknown(let reason):
            return ShortPresentation(remaining: nil, isNone: false, reason: reason)
        case .known(let shortRemaining, _, _, _, _):
            // Floor by the tightest known remaining on the row (effective availability).
            let effective = row.effectiveRemainingPercent.map { min($0, shortRemaining) } ?? shortRemaining
            // Also floor by this pool's dashboard when present.
            let floored: Double
            if let dash = pool.dashboardRemainingPercent {
                floored = min(effective, dash)
            } else {
                floored = effective
            }
            return ShortPresentation(remaining: floored, isNone: false, reason: nil)
        }
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

    /// Age of the newest observation on the row: `2m`, `1h`, `3d`.
    public static func ageLabel(for row: CapacityBenchRow, now: Date) -> String {
        guard let observed = observedAt(for: row) else { return "-" }
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
            let day = dayStamp(at)
            return "unknown — parser failed \(day)"
        case .neverSampled:
            return "unknown — never sampled"
        }
    }

    private static func unknownShortCopy(_ reason: CapacityUnknownReason) -> String {
        switch reason {
        case .vendorExposesNothing: return "unknown"
        case .parserFailed: return "unknown"
        case .neverSampled: return "unknown"
        }
    }

    private static func dayStamp(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
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

    private static func observedAt(for row: CapacityBenchRow) -> Date? {
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
