import Foundation

/// One capacity window parsed from a Codex `/status` TUI render.
///
/// Codex expresses quota as **remaining** capacity ("X% left"), which is the
/// inverse of the used-polarity reported by most other CLIs.
/// Reset time is an absolute `HH:MM on D Mon` string. Codex's TUI renders this
/// in the **host's local timezone** — confirmed against `account/rateLimits/read`
/// (`resetsAt` unix epoch) and `~/.codex/sessions/…/rollout-*.jsonl`
/// (`resets_at` epoch), both of which agree with each other and disagree with a
/// UTC interpretation of the rendered string by exactly the host's UTC offset.
/// Do not copy this to another vendor's parser — `GrokCapacityProbe` renders
/// the same `HH:MM on D Mon` shape genuinely in UTC and must stay UTC
/// (`Capacity_Native_Channels.md`, 2026-08-08 finding).
public struct CodexProbeWindow: Sendable, Equatable {
    /// Remaining capacity percentage (0…100). `0%` means fully exhausted.
    public let remainingPercent: Double
    /// Absolute reset timestamp, derived from "resets HH:MM on D Mon" as
    /// rendered in the host's local timezone (see type doc).
    public let resetAt: Date
    /// Plan tier extracted from the Account line (e.g. `"Plus"`, `"Pro"`). Nil when absent.
    public let planTier: String?
    /// Wall clock when the render was captured.
    public let observedAt: Date

    public init(
        remainingPercent: Double,
        resetAt: Date,
        planTier: String?,
        observedAt: Date
    ) {
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.planTier = planTier
        self.observedAt = observedAt
    }

    /// Normalize into the shared `CapacityWindow` surface.
    ///
    /// Remaining-polarity, weekly scope, minute reset precision, TUI probe tier.
    public func asCapacityWindow() -> CapacityWindow {
        CapacityWindow(
            remaining: remainingPercent,
            source: "codex",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: observedAt,
            sourceTier: .tuiProbe,
            planTier: planTier
        )
    }
}

/// Screen-text parser for Codex CLI `/status` TUI renders.
///
/// Codex shows plan quota on its `/status` screen (and at startup):
///
///     │  Weekly limit:   [░░░░░░░░░░░░░░░░░░░░] 0% left
///     │                  (resets 21:32 on 4 Aug)
///       Account:         user@example.com (Plus)
///
/// This parser is the **tier-3 probe path** — distinct from `CodexCapacityLog`,
/// which reads the passive `~/.codex/sessions/…/rollout-*.jsonl` side-effect.
///
/// Pure parser — fail closed. Never throws, never calls `Date()`.
public enum CodexCapacityProbe {

    // MARK: - Public API

    /// Parse then normalize into shared `CapacityWindow` values.
    /// Returns `[]` when the render yields no valid quota data.
    ///
    /// - Parameter timeZone: The zone the rendered `HH:MM on D Mon` string is
    ///   in. Defaults to the host's local zone, because that is what codex's
    ///   TUI actually renders — see the type doc. Callers never need to pass
    ///   this in production; it exists so a regression test can pin a fixed,
    ///   non-UTC zone rather than depending on the host running the test suite.
    public static func capacityWindows(
        fromRender renderText: String,
        observedAt: Date,
        timeZone: TimeZone = .current
    ) -> [CapacityWindow] {
        guard let w = parse(renderText: renderText, observedAt: observedAt, timeZone: timeZone) else { return [] }
        return [w.asCapacityWindow()]
    }

    /// Parse a Codex `/status` TUI render. Returns `nil` when no valid data found.
    public static func parse(
        renderText: String,
        observedAt: Date,
        timeZone: TimeZone = .current
    ) -> CodexProbeWindow? {
        let clean = stripANSI(renderText)
        let lines = clean.components(separatedBy: .newlines)

        var remainingPercent: Double? = nil
        var resetAt: Date? = nil
        var planTier: String? = nil

        for line in lines {
            let stripped = stripBoxChars(line)
            let lower = stripped.lowercased()

            // "Weekly limit:  [░░░░░░░░░░░░░░░░░░░░] 0% left"
            if lower.contains("weekly") && lower.contains("limit") {
                if let pct = parseLeftPercent(from: stripped) {
                    remainingPercent = pct
                }
            }

            // "(resets 21:32 on 4 Aug)" — may appear on a separate continuation line
            if lower.contains("resets") {
                if let date = parseResetDateHHMM(from: stripped, observedAt: observedAt, timeZone: timeZone) {
                    resetAt = date
                }
            }

            // "Account:  user@example.com (Plus)"
            if lower.contains("account:") {
                if let tier = parsePlanTierFromAccountLine(from: stripped) {
                    planTier = tier
                }
            }
        }

        guard let remaining = remainingPercent, let reset = resetAt else { return nil }
        return CodexProbeWindow(
            remainingPercent: remaining,
            resetAt: reset,
            planTier: planTier,
            observedAt: observedAt
        )
    }

    // MARK: - Parsers (internal for testability)

    /// Parses "X% left" remaining polarity. Never defaults to 0.
    static func parseLeftPercent(from line: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%\s*left"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return Double(ns.substring(with: match.range(at: 1)))
    }

    /// Parses "resets HH:MM on D Mon" (or with parentheses) → absolute `Date`,
    /// interpreting `HH:MM` in `timeZone` (the host's local zone by default —
    /// see the type doc for why that, and not UTC, is correct for codex).
    static func parseResetDateHHMM(from line: String, observedAt: Date, timeZone: TimeZone = .current) -> Date? {
        let pattern = #"resets\s+(\d{1,2}):(\d{2})\s+on\s+(\d{1,2})\s+([A-Za-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 5 else { return nil }
        guard let hour = Int(ns.substring(with: match.range(at: 1))),
              let minute = Int(ns.substring(with: match.range(at: 2))),
              let day = Int(ns.substring(with: match.range(at: 3))) else { return nil }
        let monthStr = ns.substring(with: match.range(at: 4))
        return resolveDate(hour: hour, minute: minute, day: day, monthStr: monthStr, observedAt: observedAt, timeZone: timeZone)
    }

    /// Extracts plan tier from "Account: user@example.com (Plus)" → `"Plus"`.
    static func parsePlanTierFromAccountLine(from line: String) -> String? {
        // Last parenthesized token at end of line: "(Plus)", "(Pro)", "(Enterprise)"
        let pattern = #"\(([A-Za-z0-9][A-Za-z0-9 \-]*)\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        let tier = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        return tier.isEmpty ? nil : tier
    }

    // MARK: - Date resolution

    /// Resolve an absolute date from parsed HH:MM + day + month, interpreted
    /// in `timeZone`. If the resolved date is already in the past relative to
    /// `observedAt`, advance one year.
    ///
    /// `timeZone` is used only to interpret the wall-clock components read
    /// off the screen — the returned `Date` is the normal timezone-agnostic
    /// absolute instant. The year is still read off `observedAt` using the
    /// SAME zone, so a render captured just after local midnight cannot roll
    /// to the wrong year relative to what the screen actually showed.
    private static func resolveDate(
        hour: Int, minute: Int, day: Int, monthStr: String, observedAt: Date, timeZone: TimeZone
    ) -> Date? {
        guard let monthInt = monthNumber(monthStr) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let year = cal.component(.year, from: observedAt)

        var comps = DateComponents()
        comps.timeZone = timeZone
        comps.year = year
        comps.month = monthInt
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0

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
