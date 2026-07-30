import Foundation

/// Limit window kind for Claude Code plan usage (Usage tab / `/usage`).
public enum ClaudeWindowKind: String, Sendable, Equatable, CaseIterable {
    /// "Current session" bar — short rolling session quota.
    case session
    /// "Current week (all models)" — primary weekly pool.
    case weeklyAllModels
    /// "Current week (<pool>)" — secondary weekly pool (e.g. Fable).
    case weeklyPool
}

/// One capacity limit window from Claude Code Usage.
///
/// Semantics:
/// - Claude prints percentage **used** (e.g. `83% used`, `47% used`).
/// - `usedPercent` is the percentage used (0…100+).
/// - `remainingPercent` is `max(0, 100 − usedPercent)`.
/// - Reset lines are absolute wall-clock text (`Resets 8:49am (America/Vancouver)`,
///   `Resets Aug 3 at 8pm (…)`); we resolve them against `observedAt` when possible.
public struct ClaudeCapacityWindow: Sendable, Equatable {
    public let kind: ClaudeWindowKind
    /// Vendor pool label for secondary weekly windows (e.g. "Fable"). Nil for session / all-models.
    public let poolLabel: String?
    public let usedPercent: Double
    public let remainingPercent: Double
    public let observedAt: Date
    public let resetAt: Date?
    public let resetPrecision: CapacityResetPrecision

    public init(
        kind: ClaudeWindowKind,
        poolLabel: String? = nil,
        usedPercent: Double,
        observedAt: Date,
        resetAt: Date?,
        resetPrecision: CapacityResetPrecision
    ) {
        self.kind = kind
        self.poolLabel = poolLabel
        self.usedPercent = usedPercent
        self.remainingPercent = max(0.0, 100.0 - usedPercent)
        self.observedAt = observedAt
        self.resetAt = resetAt
        self.resetPrecision = resetPrecision
    }

    /// Normalize into the shared `CapacityWindow` surface.
    public func asCapacityWindow(planTier: String? = nil) -> CapacityWindow {
        let scope: CapacityWindowScope
        switch kind {
        case .session: scope = .session
        case .weeklyAllModels, .weeklyPool: scope = .weekly
        }
        return CapacityWindow(
            used: usedPercent,
            source: "claude_code",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: resetPrecision,
            observedAt: observedAt,
            sourceTier: .tuiProbe,
            poolLabel: poolLabel,
            planTier: planTier
        )
    }
}

/// Extractor for Claude Code TUI `/usage` (and `/status` → Usage tab) renders.
/// Pure parser — fail closed. Never throws, never calls `Date()`.
public enum ClaudeCapacityLog {

    /// Parse then normalize into shared `CapacityWindow` values.
    /// Returns `[]` when the render yields no valid windows.
    public static func capacityWindows(fromRender renderText: String, observedAt: Date) -> [CapacityWindow] {
        let tier = planTier(fromRender: renderText)
        return parseWindows(fromRender: renderText, observedAt: observedAt)
            .map { $0.asCapacityWindow(planTier: tier) }
    }

    /// Plan tier from a Claude Code render, or nil when the render does not say.
    ///
    /// Two surfaces carry it and the probe already captures the first for free:
    ///
    /// - the boot banner every session paints — `Opus 5 (1M context) · Claude Max`
    /// - the `/status` pane — `Login method:  Claude Max account`
    ///
    /// `/status` wins when present because it is a labeled field rather than a
    /// banner suffix, but the probe only visits it on the `/usage` fallback path,
    /// so the banner is what normally answers.
    ///
    /// Returns the bare tier (`Max`, `Pro`) to match the other seats — the row is
    /// already labeled Claude, so "Claude Max" would stutter next to Cursor's
    /// "Ultra".
    public static func planTier(fromRender renderText: String) -> String? {
        let clean = stripANSI(renderText)
        // Labeled field first.
        if let tier = firstMatch(
            pattern: #"Login\s+method:\s*Claude\s+(Max|Pro|Team|Enterprise|Free)(\s+\d+x)?"#,
            in: clean
        ) {
            return tier
        }
        return firstMatch(
            pattern: #"·\s*Claude\s+(Max|Pro|Team|Enterprise|Free)(\s+\d+x)?"#,
            in: clean
        )
    }

    /// Tier word plus any multiplier suffix (`Max 20x`), joined and whitespace-normalized.
    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        var tier = ns.substring(with: match.range(at: 1))
        if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
            let suffix = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            if !suffix.isEmpty { tier += " \(suffix)" }
        }
        return tier
    }

    /// Parses capacity windows from a Claude Usage render.
    ///
    /// Expected shape (real capture, 2026-07-30):
    /// ```
    /// Current session
    /// ████… 83% used
    /// Resets 8:49am (America/Vancouver)
    ///
    /// Current week (all models)
    /// ████… 47% used
    /// Resets Aug 3 at 8pm (America/Vancouver)
    ///
    /// Current week (Fable)
    /// ███… 7% used
    /// Resets Aug 3 at 8pm (America/Vancouver)
    /// ```
    public static func parseWindows(fromRender renderText: String, observedAt: Date) -> [ClaudeCapacityWindow] {
        let cleanText = stripANSI(renderText)
        let lines = cleanText.components(separatedBy: .newlines).map(cleanFrame)

        var windows: [ClaudeCapacityWindow] = []
        var pending: PendingWindow?

        func flush() {
            guard let p = pending, let used = p.usedPercent else {
                pending = nil
                return
            }
            windows.append(
                ClaudeCapacityWindow(
                    kind: p.kind,
                    poolLabel: p.poolLabel,
                    usedPercent: used,
                    observedAt: observedAt,
                    resetAt: p.resetAt,
                    resetPrecision: p.resetPrecision
                )
            )
            pending = nil
        }

        for line in lines {
            if line.isEmpty { continue }
            let lower = line.lowercased()

            // Section headers open a new window.
            if lower.hasPrefix("current session") {
                flush()
                pending = PendingWindow(kind: .session, poolLabel: nil)
                // Same-line percent is rare but accept it.
                if let used = parseUsedPercent(from: line) {
                    pending?.usedPercent = used
                }
                continue
            }
            if lower.hasPrefix("current week") {
                flush()
                if let pool = extractWeekPool(from: line) {
                    if pool.lowercased() == "all models" {
                        pending = PendingWindow(kind: .weeklyAllModels, poolLabel: nil)
                    } else {
                        pending = PendingWindow(kind: .weeklyPool, poolLabel: pool)
                    }
                } else {
                    pending = PendingWindow(kind: .weeklyAllModels, poolLabel: nil)
                }
                if let used = parseUsedPercent(from: line) {
                    pending?.usedPercent = used
                }
                continue
            }

            // Stop absorbing once we leave the limit bars.
            if lower.contains("what's contributing")
                || lower.contains("usage credits")
                || lower.hasPrefix("session") && lower.contains("total cost")
                || lower.hasPrefix("total cost")
            {
                // "Session" cost block sits above the limit bars — only stop if we already
                // finished at least one window, else keep scanning.
                if !windows.isEmpty || pending?.usedPercent != nil {
                    flush()
                }
                // Don't hard-stop: bars can appear after a partial "Session" cost header
                // when the tab paints mid-stream. Continue looking for headers/percents.
            }

            guard pending != nil else { continue }

            if let used = parseUsedPercent(from: line), pending?.usedPercent == nil {
                pending?.usedPercent = used
            }
            if lower.contains("resets") {
                if let (resetAt, precision) = parseReset(from: line, observedAt: observedAt) {
                    pending?.resetAt = resetAt
                    pending?.resetPrecision = precision
                }
            }
        }
        flush()
        return windows
    }

    // MARK: - Private

    private struct PendingWindow {
        let kind: ClaudeWindowKind
        let poolLabel: String?
        var usedPercent: Double?
        var resetAt: Date?
        var resetPrecision: CapacityResetPrecision = .minute
    }

    private static func stripANSI(_ input: String) -> String {
        guard input.contains("\u{001B}") else { return input }
        var s = input
        s = s.replacingOccurrences(
            of: #"\x1B\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"\x1B."#,
            with: "",
            options: .regularExpression
        )
        return s
    }

    private static func cleanFrame(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        while let first = s.first, "│╭╰┆┊▔─".contains(first) {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        while let last = s.last, "│╮╯┆┊▔─".contains(last) {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// "Current week (all models)" / "Current week (Fable)" → pool name.
    private static func extractWeekPool(from line: String) -> String? {
        guard let open = line.firstIndex(of: "("),
              let close = line.firstIndex(of: ")"),
              open < close
        else { return nil }
        let inner = line[line.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : String(inner)
    }

    private static func parseUsedPercent(from line: String) -> Double? {
        // "83% used", "47% used" — require "used" so we ignore "50% weekly limits promo".
        let pattern = #"(\d+(?:\.\d+)?)\s*%\s*used"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        return Double(ns.substring(with: match.range(at: 1)))
    }

    /// Parse Claude reset lines into absolute time + precision.
    /// - `Resets 8:49am (America/Vancouver)` → today/tomorrow at that clock, minute precision
    /// - `Resets Aug 3 at 8pm (America/Vancouver)` → next matching date, minute precision
    private static func parseReset(
        from line: String,
        observedAt: Date
    ) -> (Date, CapacityResetPrecision)? {
        let tz = extractTimeZone(from: line) ?? TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        // "Resets Aug 3 at 8pm" / "Resets August 3 at 8:00pm"
        let dated = #"Resets\s+([A-Za-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#
        if let regex = try? NSRegularExpression(pattern: dated, options: .caseInsensitive) {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 6
            {
                let monthStr = ns.substring(with: match.range(at: 1))
                let dayStr = ns.substring(with: match.range(at: 2))
                let hourStr = ns.substring(with: match.range(at: 3))
                let minuteStr = match.range(at: 4).location != NSNotFound
                    ? ns.substring(with: match.range(at: 4)) : "0"
                let ampm = ns.substring(with: match.range(at: 5)).lowercased()
                if let month = monthNumber(monthStr),
                   let day = Int(dayStr),
                   let hour12 = Int(hourStr),
                   let minute = Int(minuteStr),
                   let hour = hour24(hour12, ampm: ampm)
                {
                    let obs = calendar.dateComponents([.year], from: observedAt)
                    var comps = DateComponents()
                    comps.year = obs.year
                    comps.month = month
                    comps.day = day
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = 0
                    if var candidate = calendar.date(from: comps) {
                        if candidate < observedAt {
                            comps.year = (obs.year ?? 0) + 1
                            if let next = calendar.date(from: comps) {
                                candidate = next
                            }
                        }
                        return (candidate, .minute)
                    }
                }
            }
        }

        // "Resets 8:49am (America/Vancouver)" — same calendar day, roll forward if past.
        let clock = #"Resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#
        if let regex = try? NSRegularExpression(pattern: clock, options: .caseInsensitive) {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 4
            {
                let hourStr = ns.substring(with: match.range(at: 1))
                let minuteStr = match.range(at: 2).location != NSNotFound
                    ? ns.substring(with: match.range(at: 2)) : "0"
                let ampm = ns.substring(with: match.range(at: 3)).lowercased()
                if let hour12 = Int(hourStr),
                   let minute = Int(minuteStr),
                   let hour = hour24(hour12, ampm: ampm)
                {
                    var comps = calendar.dateComponents(
                        [.year, .month, .day],
                        from: observedAt
                    )
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = 0
                    if var candidate = calendar.date(from: comps) {
                        if candidate < observedAt {
                            candidate = calendar.date(byAdding: .day, value: 1, to: candidate)
                                ?? candidate
                        }
                        return (candidate, .minute)
                    }
                }
            }
        }

        return nil
    }

    private static func extractTimeZone(from line: String) -> TimeZone? {
        // "(America/Vancouver)" etc.
        guard let open = line.lastIndex(of: "("),
              let close = line.lastIndex(of: ")"),
              open < close
        else { return nil }
        let id = line[line.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TimeZone(identifier: String(id))
    }

    private static func hour24(_ hour12: Int, ampm: String) -> Int? {
        guard (1...12).contains(hour12) else { return nil }
        if ampm == "am" {
            return hour12 == 12 ? 0 : hour12
        }
        if ampm == "pm" {
            return hour12 == 12 ? 12 : hour12 + 12
        }
        return nil
    }

    private static func monthNumber(_ str: String) -> Int? {
        let lower = str.lowercased()
        let months = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12,
        ]
        return months[lower]
    }
}
