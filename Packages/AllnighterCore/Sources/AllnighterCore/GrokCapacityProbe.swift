import Foundation

/// One capacity window parsed from a Grok TUI `/usage` render.
///
/// Grok's billing surface is structurally similar to Kimi — weekly limit,
/// percentage used, and a reset duration or absolute date.
public struct GrokProbeWindow: Sendable, Equatable {
    /// Percentage of weekly quota used (0…100+).
    public let usedPercent: Double
    /// Absolute reset timestamp.
    public let resetAt: Date
    /// Subscription tier (e.g. `"X Premium+"`). Nil when not found.
    public let subscriptionTier: String?
    /// Wall clock when the render was captured.
    public let observedAt: Date

    public init(
        usedPercent: Double,
        resetAt: Date,
        subscriptionTier: String?,
        observedAt: Date
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.subscriptionTier = subscriptionTier
        self.observedAt = observedAt
    }

    /// Normalize into the shared `CapacityWindow` surface.
    ///
    /// Used-polarity, weekly scope, minute reset precision, TUI probe tier.
    public func asCapacityWindow() -> CapacityWindow {
        CapacityWindow(
            used: usedPercent,
            source: "grok",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: observedAt,
            sourceTier: .tuiProbe,
            planTier: subscriptionTier
        )
    }
}

/// Screen-text parser for Grok CLI TUI `/usage` renders.
///
/// Grok's exact TUI layout may vary across versions. This parser handles
/// common patterns and fails closed on unrecognized output — the debug dump
/// system in `CapacityProbe` preserves the raw capture for parser iteration.
///
/// This is the **tier-3 probe path** — distinct from `GrokCapacityLog`,
/// which reads the passive `~/.grok/logs/unified.jsonl` side-effect.
///
/// Pure parser — fail closed. Never throws, never calls `Date()`.
public enum GrokCapacityProbe {

    // MARK: - Public API

    /// Parse then normalize into shared `CapacityWindow` values.
    /// Returns `[]` when the render yields no valid quota data.
    public static func capacityWindows(fromRender renderText: String, observedAt: Date) -> [CapacityWindow] {
        guard let w = parse(renderText: renderText, observedAt: observedAt) else { return [] }
        return [w.asCapacityWindow()]
    }

    /// Parse a Grok TUI `/usage` render. Returns `nil` when no valid data found.
    public static func parse(renderText: String, observedAt: Date) -> GrokProbeWindow? {
        let clean = stripANSI(renderText)
        let lines = clean.components(separatedBy: .newlines)

        var usedPercent: Double? = nil
        var resetAt: Date? = nil
        var subscriptionTier: String? = nil

        for line in lines {
            let stripped = stripBoxChars(line)
            let lower = stripped.lowercased()

            // "Weekly limit: 100%" — bare percent, used-polarity (Grok TUI format).
            // Also handles "54% used", "54.0% of weekly limit used".
            if lower.contains("weekly limit") || lower.contains("% used") || lower.contains("credit") {
                // Grok TUI: "Weekly limit: X%" — the number is used-percent.
                let isRemaining = lower.contains("% left") || lower.contains("% remaining")
                if let pct = parsePercent(from: stripped, remainingPolarity: isRemaining) {
                    usedPercent = pct
                }
            }

            // "Next reset: July 31, 11:11" or "Resets in 6d 3h" or other reset forms.
            if lower.contains("next reset") || lower.contains("reset") {
                if let date = parseResetDate(from: stripped, observedAt: observedAt) {
                    resetAt = date
                }
            }

            // "X Premium+", "Plan: Pro", "Tier:", "Subscription:"
            if lower.contains("premium") || lower.contains("plan:") || lower.contains("tier:") || lower.contains("subscription") {
                if let tier = parseTier(from: stripped) {
                    subscriptionTier = tier
                }
            }
        }

        guard let used = usedPercent, let reset = resetAt else { return nil }
        return GrokProbeWindow(
            usedPercent: used,
            resetAt: reset,
            subscriptionTier: subscriptionTier,
            observedAt: observedAt
        )
    }

    // MARK: - Parsers (internal for testability)

    /// Parses the first `X%` from a line. If `remainingPolarity` is true, converts to used-%.
    static func parsePercent(from line: String, remainingPolarity: Bool) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2,
              let val = Double(ns.substring(with: match.range(at: 1))) else { return nil }
        return remainingPolarity ? max(0.0, 100.0 - val) : val
    }

    /// Tries next-reset (local time) → relative-duration → absolute-HHMM → month-day forms.
    static func parseResetDate(from line: String, observedAt: Date) -> Date? {
        // "Next reset: July 31, 11:11" — Grok TUI primary format (local time).
        if let d = parseNextResetLocalDate(from: line, observedAt: observedAt) { return d }
        // "Resets in 6d 3h 20m" / "Resets in 6 days 3 hours"
        if let d = parseRelativeDuration(from: line, observedAt: observedAt) { return d }
        // "Resets 21:32 on 4 Aug"
        if let d = parseAbsoluteDateHHMM(from: line, observedAt: observedAt) { return d }
        // "Resets Aug 4" / "Resets 4 Aug"
        if let d = parseMonthDay(from: line, observedAt: observedAt) { return d }
        return nil
    }

    /// Parses "Next reset: Month DD, HH:MM" → local-timezone `Date`.
    /// This is the primary Grok TUI format: e.g. "Next reset: July 31, 11:11".
    static func parseNextResetLocalDate(from line: String, observedAt: Date) -> Date? {
        // e.g. "Next reset: July 31, 11:11" or "Next reset: August 4, 09:00"
        let pattern = #"[Nn]ext reset:\s+([A-Za-z]+)\s+(\d{1,2}),\s*(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 5,
              let day    = Int(ns.substring(with: match.range(at: 2))),
              let hour   = Int(ns.substring(with: match.range(at: 3))),
              let minute = Int(ns.substring(with: match.range(at: 4))) else { return nil }
        let monthStr = ns.substring(with: match.range(at: 1))
        return resolveLocalDate(hour: hour, minute: minute, day: day, monthStr: monthStr, observedAt: observedAt)
    }

    /// Parses "Xd Yh Zm" relative duration after a "resets in" or "reset in" anchor.
    private static func parseRelativeDuration(from line: String, observedAt: Date) -> Date? {
        let searchStr: String
        if let r = line.range(of: "resets in", options: .caseInsensitive) {
            searchStr = String(line[r.upperBound...])
        } else if let r = line.range(of: "reset in", options: .caseInsensitive) {
            searchStr = String(line[r.upperBound...])
        } else {
            return nil
        }

        let pattern = #"(\d+)\s*(?:(d(?:ay)?s?)|(h(?:our)?s?)|(m(?:in)?s?))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = searchStr as NSString
        let matches = regex.matches(in: searchStr, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        var total: TimeInterval = 0
        for match in matches {
            guard let num = Double(ns.substring(with: match.range(at: 1))) else { continue }
            // Group 2=days, 3=hours, 4=minutes
            if match.range(at: 2).location != NSNotFound { total += num * 86400 }
            else if match.range(at: 3).location != NSNotFound { total += num * 3600 }
            else if match.range(at: 4).location != NSNotFound { total += num * 60 }
        }
        return total > 0 ? observedAt.addingTimeInterval(total) : nil
    }

    /// Parses "resets HH:MM on D Mon" → absolute UTC Date.
    private static func parseAbsoluteDateHHMM(from line: String, observedAt: Date) -> Date? {
        let pattern = #"resets\s+(\d{1,2}):(\d{2})\s+on\s+(\d{1,2})\s+([A-Za-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 5,
              let hour = Int(ns.substring(with: match.range(at: 1))),
              let minute = Int(ns.substring(with: match.range(at: 2))),
              let day = Int(ns.substring(with: match.range(at: 3))) else { return nil }
        let monthStr = ns.substring(with: match.range(at: 4))
        return resolveUTCDate(hour: hour, minute: minute, day: day, monthStr: monthStr, observedAt: observedAt)
    }

    /// Parses bare "Mon D" or "D Mon" → midnight UTC Date.
    private static func parseMonthDay(from line: String, observedAt: Date) -> Date? {
        let pattern = #"(?:([A-Za-z]{3,})\s+(\d{1,2})|(\d{1,2})\s+([A-Za-z]{3,}))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }

        let monthStr: String
        let day: Int
        if match.range(at: 1).location != NSNotFound {
            monthStr = ns.substring(with: match.range(at: 1))
            guard let d = Int(ns.substring(with: match.range(at: 2))) else { return nil }
            day = d
        } else {
            guard let d = Int(ns.substring(with: match.range(at: 3))) else { return nil }
            day = d
            monthStr = ns.substring(with: match.range(at: 4))
        }
        return resolveUTCDate(hour: 0, minute: 0, day: day, monthStr: monthStr, observedAt: observedAt)
    }

    /// Extracts subscription tier label from common display patterns.
    static func parseTier(from line: String) -> String? {
        // "X Premium+" or "Premium+" pattern
        let premPattern = #"(?:[A-Za-z]+\s+)?Premium\+?"#
        if let r = try? NSRegularExpression(pattern: premPattern, options: .caseInsensitive) {
            let ns = line as NSString
            if let m = r.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let t = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { return t }
            }
        }
        // "Plan: X" / "Tier: X" / "Subscription: X"
        let labelPattern = #"(?:Plan|Tier|Subscription):\s*([A-Za-z0-9\+][A-Za-z0-9 \+\-]*)"#
        if let r = try? NSRegularExpression(pattern: labelPattern, options: .caseInsensitive) {
            let ns = line as NSString
            if let m = r.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges >= 2 {
                let t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    // MARK: - Date resolution

    /// Resolves a **local-time** date from parsed components (uses `Calendar.current`).
    /// Used for Grok's "Next reset: Month DD, HH:MM" format which is local time.
    private static func resolveLocalDate(
        hour: Int, minute: Int, day: Int, monthStr: String, observedAt: Date
    ) -> Date? {
        guard let monthInt = monthNumber(monthStr) else { return nil }
        var cal = Calendar.current   // respects the user's local timezone
        let year = cal.component(.year, from: observedAt)
        var comps = DateComponents()
        comps.year = year; comps.month = monthInt; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        guard var candidate = cal.date(from: comps) else { return nil }
        if candidate < observedAt {
            comps.year = year + 1
            candidate = cal.date(from: comps) ?? candidate
        }
        return candidate
    }

    private static func resolveUTCDate(
        hour: Int, minute: Int, day: Int, monthStr: String, observedAt: Date
    ) -> Date? {
        guard let monthInt = monthNumber(monthStr) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let year = cal.component(.year, from: observedAt)

        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = year; comps.month = monthInt; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0

        guard var candidate = cal.date(from: comps) else { return nil }
        if candidate < observedAt {
            comps.year = year + 1
            candidate = cal.date(from: comps) ?? candidate
        }
        return candidate
    }

    // MARK: - Utilities

    private static func monthNumber(_ str: String) -> Int? {
        switch str.lowercased().prefix(3) {
        case "jan": return 1;  case "feb": return 2;  case "mar": return 3
        case "apr": return 4;  case "may": return 5;  case "jun": return 6
        case "jul": return 7;  case "aug": return 8;  case "sep": return 9
        case "oct": return 10; case "nov": return 11; case "dec": return 12
        default: return nil
        }
    }

    private static func stripANSI(_ input: String) -> String {
        guard input.contains("\u{001B}") else { return input }
        return input.replacingOccurrences(
            of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func stripBoxChars(_ line: String) -> String {
        var s = line
        while let first = s.first, "│╭╰┆┊├─╠═╗╝╚╔".contains(first) { s.removeFirst() }
        while let last = s.last,  "│╮╯┆┊┤─╣═╗╝╚╔".contains(last)  { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
