import Foundation

/// Pure HTML parser for OpenCode Go `/go` dashboard capacity (no IO, no `Date()`).
///
/// Atomic rule: all three windows (rolling / weekly / monthly) or none. Partial
/// parse is total failure. Behavior reference: `@slkiser/opencode-quota` — not
/// a runtime dependency.
public enum OpenCodeGoCapacityProbe {

    public static let sourceId = CapacityAcquisition.dogfoodSourceId

    public enum ParseStrategy: String, Sendable, Equatable {
        case solidSSR = "solid_ssr_v1"
        case dataSlot = "data_slot_v1"
    }

    public struct WindowSample: Sendable, Equatable {
        public let usedPercent: Double
        public let resetInSec: TimeInterval
    }

    public struct ParsedSample: Sendable, Equatable {
        public let strategy: ParseStrategy
        public let rolling: WindowSample
        public let weekly: WindowSample
        public let monthly: WindowSample
    }

    public enum ParseFailure: Sendable, Equatable, Error {
        case authRequired
        case schemaDrift(strategy: String?, missing: [String])
        case strategyMismatch
        case invalidValue(field: String)
        case duplicateWindow(String)
    }

    private static let number = #"(-?\d+(?:\.\d+)?)"#

    private static let rollingPctFirst = solidRegex(
        window: "rollingUsage", pctFirst: true
    )
    private static let rollingResetFirst = solidRegex(
        window: "rollingUsage", pctFirst: false
    )
    private static let weeklyPctFirst = solidRegex(
        window: "weeklyUsage", pctFirst: true
    )
    private static let weeklyResetFirst = solidRegex(
        window: "weeklyUsage", pctFirst: false
    )
    private static let monthlyPctFirst = solidRegex(
        window: "monthlyUsage", pctFirst: true
    )
    private static let monthlyResetFirst = solidRegex(
        window: "monthlyUsage", pctFirst: false
    )

    /// Parse dashboard HTML into capacity windows for `observedAt`.
    ///
    /// Always returns three windows (rolling / weekly / monthly). All known or
    /// all unknown — never a partial numeric sample.
    public static func capacityWindows(
        html: String,
        observedAt: Date
    ) -> [CapacityWindow] {
        if looksLikeLoginPage(html) {
            return unknownWindows(reason: .authRequired(observedAt: observedAt), at: observedAt)
        }
        switch parseSample(html: html) {
        case .success(let sample):
            return windows(from: sample, observedAt: observedAt)
        case .failure(let failure):
            let reason: CapacityUnknownReason
            switch failure {
            case .authRequired:
                reason = .authRequired(observedAt: observedAt)
            default:
                reason = .parserFailed(observedAt: observedAt)
            }
            return unknownWindows(reason: reason, at: observedAt)
        }
    }

    /// Parse-only surface for tests and diagnostics.
    public static func parseSample(html: String) -> Result<ParsedSample, ParseFailure> {
        if looksLikeLoginPage(html) {
            return .failure(.authRequired)
        }

        let solid = parseSolidBundle(html: html)
        let slot = parseDataSlotBundle(html: html)

        let candidate: ParsedSample
        switch (solid, slot) {
        case (.success(let s), .success(let d)):
            // Both formats often coexist on the live page. SSR carries exact
            // resetInSec; data-slot parses rounded human text ("4h 59m" vs 18000s).
            // Percentages must agree; prefer SSR for reset clocks.
            guard percentagesAgree(s, d) else { return .failure(.strategyMismatch) }
            candidate = s
        case (.success(let s), .failure):
            candidate = s
        case (.failure, .success(let d)):
            candidate = d
        case (.failure, .failure):
            let missing = missingWindows(solid: solid, slot: slot)
            return .failure(.schemaDrift(strategy: nil, missing: missing))
        }
        if let invalid = firstInvalidField(in: candidate) {
            return .failure(.invalidValue(field: invalid))
        }
        return .success(candidate)
    }

    // MARK: - Bounds

    /// Ordered window layout: field name, scope, and the credible upper bound on
    /// `resetInSec` for that scope (small clock tolerance included).
    private static let windowLayout:
        [(field: String, scope: CapacityWindowScope, resetMax: TimeInterval)] = [
            ("rolling", .fiveHour, 5 * 3600 + 600),
            ("weekly", .weekly, 7 * 86400 + 3600),
            ("monthly", .monthly, 31 * 86400 + 3600),
        ]

    private static func sample(
        _ parsed: ParsedSample,
        for field: String
    ) -> WindowSample {
        switch field {
        case "rolling": return parsed.rolling
        case "weekly": return parsed.weekly
        default: return parsed.monthly
        }
    }

    /// Name of the first window whose percentage or reset is out of bounds.
    ///
    /// Atomic rule: one bad value poisons the whole sample. Never clamp, and
    /// never emit the siblings that happened to parse — a plausible wrong
    /// number is more dangerous than an honest unknown.
    private static func firstInvalidField(in parsed: ParsedSample) -> String? {
        windowLayout.first { entry in
            let window = sample(parsed, for: entry.field)
            return !isValidPercent(window.usedPercent)
                || !isValidReset(window.resetInSec, max: entry.resetMax)
        }?.field
    }

    // MARK: - Window construction

    private static func windows(
        from sample: ParsedSample,
        observedAt: Date
    ) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        return windowLayout.map { entry in
            window(
                sample: self.sample(sample, for: entry.field),
                scope: entry.scope,
                observedAt: observedAt,
                tier: tier
            )
        }
    }

    private static func window(
        sample: WindowSample,
        scope: CapacityWindowScope,
        observedAt: Date,
        tier: CapacityAcquisitionTier
    ) -> CapacityWindow {
        let resetAt = observedAt.addingTimeInterval(sample.resetInSec)
        return CapacityWindow(
            used: sample.usedPercent,
            source: sourceId,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: observedAt,
            sourceTier: tier,
            planTier: "Go"
        )
    }

    private static func unknownWindows(
        reason: CapacityUnknownReason,
        at observedAt: Date
    ) -> [CapacityWindow] {
        let tier = CapacityAcquisitionTier.dashboardScrape
        let scopes: [CapacityWindowScope] = [.fiveHour, .weekly, .monthly]
        let windows = scopes.map {
            CapacityWindow.unknown(
                reason: reason,
                source: sourceId,
                scope: $0,
                observedAt: observedAt,
                sourceTier: tier,
                planTier: "Go"
            )
        }
        return windows
    }

    // MARK: - Solid SSR

    private static func parseSolidBundle(html: String) -> Result<ParsedSample, ParseFailure> {
        guard let rolling = parseSolidWindow(
            html: html, pctFirst: rollingPctFirst, resetFirst: rollingResetFirst, name: "rolling"
        ),
        let weekly = parseSolidWindow(
            html: html, pctFirst: weeklyPctFirst, resetFirst: weeklyResetFirst, name: "weekly"
        ),
        let monthly = parseSolidWindow(
            html: html, pctFirst: monthlyPctFirst, resetFirst: monthlyResetFirst, name: "monthly"
        ) else {
            return .failure(.schemaDrift(strategy: ParseStrategy.solidSSR.rawValue, missing: ["rolling", "weekly", "monthly"]))
        }
        return .success(
            ParsedSample(
                strategy: .solidSSR,
                rolling: rolling,
                weekly: weekly,
                monthly: monthly
            )
        )
    }

    private static func parseSolidWindow(
        html: String,
        pctFirst: NSRegularExpression,
        resetFirst: NSRegularExpression,
        name: String
    ) -> WindowSample? {
        switch uniqueSolidMatch(html: html, regex: pctFirst, name: name, pctIsFirstCapture: true) {
        case .success(let sample):
            return sample
        case .failure(.duplicateWindow):
            return nil
        case .failure:
            break
        }
        switch uniqueSolidMatch(html: html, regex: resetFirst, name: name, pctIsFirstCapture: false) {
        case .success(let sample):
            return sample
        default:
            return nil
        }
    }

    private enum SolidMatchResult {
        case success(WindowSample)
        case failure(ParseFailure)
    }

    private static func uniqueSolidMatch(
        html: String,
        regex: NSRegularExpression,
        name: String,
        pctIsFirstCapture: Bool
    ) -> SolidMatchResult {
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        guard !matches.isEmpty else { return .failure(.schemaDrift(strategy: nil, missing: [name])) }
        var samples: [WindowSample] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let firstRange = Range(match.range(at: 1), in: html),
                  let secondRange = Range(match.range(at: 2), in: html),
                  let first = Double(html[firstRange]),
                  let second = TimeInterval(html[secondRange])
            else {
                return .failure(.invalidValue(field: name))
            }
            let usedPercent = pctIsFirstCapture ? first : second
            let resetInSec = pctIsFirstCapture ? second : first
            samples.append(WindowSample(usedPercent: usedPercent, resetInSec: resetInSec))
        }
        let distinct = Set(samples.map { "\($0.usedPercent)|\($0.resetInSec)" })
        guard distinct.count == 1, let sample = samples.first else {
            return .failure(.duplicateWindow(name))
        }
        return .success(sample)
    }

    private static func solidRegex(window: String, pctFirst: Bool) -> NSRegularExpression {
        let pattern: String
        if pctFirst {
            pattern = #"\#(window):\$R\[\d+\]=\{[^}]*usagePercent:\#(number)[^}]*resetInSec:\#(number)[^}]*\}"#
        } else {
            pattern = #"\#(window):\$R\[\d+\]=\{[^}]*resetInSec:\#(number)[^}]*usagePercent:\#(number)[^}]*\}"#
        }
        return try! NSRegularExpression(pattern: pattern)
    }

    // MARK: - data-slot HTML

    private static func parseDataSlotBundle(html: String) -> Result<ParsedSample, ParseFailure> {
        let map = parseDataSlotFormat(html: html)
        guard let rolling = map["rolling"],
              let weekly = map["weekly"],
              let monthly = map["monthly"]
        else {
            let missing = ["rolling", "weekly", "monthly"].filter { map[$0] == nil }
            return .failure(.schemaDrift(strategy: ParseStrategy.dataSlot.rawValue, missing: missing))
        }
        return .success(
            ParsedSample(
                strategy: .dataSlot,
                rolling: rolling,
                weekly: weekly,
                monthly: monthly
            )
        )
    }

    private static func parseDataSlotFormat(html: String) -> [String: WindowSample] {
        var result: [String: WindowSample] = [:]
        let parts = html.components(separatedBy: "data-slot=\"usage-item\"")
        guard parts.count > 1 else { return result }
        for part in parts.dropFirst() {
            guard let label = firstMatch(in: part, pattern: #"data-slot="usage-label">([^<]+)<"#),
                  let usageRaw = firstMatch(in: part, pattern: #"data-slot="usage-value">[^0-9]*(\d+(?:\.\d+)?)"#),
                  let usage = Double(usageRaw)
            else { continue }

            let resetKind = firstMatch(in: part, pattern: #"data-slot="(reset-time|reset-now)""#)
            let resetContent = firstMatch(
                in: part,
                pattern: #"data-slot="(?:reset-time|reset-now)">([\s\S]*?)</span>"#
            )?
                .replacingOccurrences(of: "<!--$-->", with: "")
                .replacingOccurrences(of: "<!--/-->", with: "")
                .replacingOccurrences(of: #"Resets?\s*in\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let resetInSec: TimeInterval?
            if resetKind == "reset-now" {
                resetInSec = 0
            } else if let resetContent {
                resetInSec = parseHumanReadableTime(resetContent)
            } else {
                resetInSec = nil
            }
            guard let resetInSec, resetInSec.isFinite else { continue }

            let labelLower = label.lowercased()
            let key: String?
            if labelLower.contains("rolling") { key = "rolling" }
            else if labelLower.contains("weekly") { key = "weekly" }
            else if labelLower.contains("monthly") { key = "monthly" }
            else { key = nil }
            if let key {
                result[key] = WindowSample(usedPercent: usage, resetInSec: resetInSec)
            }
        }
        return result
    }

    // MARK: - Helpers

    /// Positive login-page evidence only, and only on a page carrying no usage
    /// markers at all.
    ///
    /// A SolidJS bundle routinely inlines a route manifest naming `/sign-in`,
    /// so those substrings alone do not prove the request was rejected — they
    /// appear on a perfectly good dashboard. Claiming `authRequired` there
    /// would assert an unobserved cause *and* discard real numbers. When usage
    /// markers are present the parser decides, and an unrecognized page falls
    /// through to schema drift rather than a manufactured auth verdict.
    ///
    /// The load-bearing auth signals live in the client (HTTP 401/403 and a
    /// final URL on the sign-in route); this is the HTML backstop.
    private static func looksLikeLoginPage(_ html: String) -> Bool {
        let lower = html.lowercased()
        let hasUsageMarker = lower.contains("rollingusage")
            || lower.contains("weeklyusage")
            || lower.contains("monthlyusage")
            || lower.contains("data-slot=\"usage-item\"")
        guard !hasUsageMarker else { return false }
        if lower.contains("sign in to opencode") { return true }
        if lower.contains("<title>sign in") { return true }
        if lower.contains("type=\"password\"") { return true }
        return false
    }

    private static func percentagesAgree(_ a: ParsedSample, _ b: ParsedSample) -> Bool {
        a.rolling.usedPercent == b.rolling.usedPercent
            && a.weekly.usedPercent == b.weekly.usedPercent
            && a.monthly.usedPercent == b.monthly.usedPercent
    }

    private static func samplesAgree(_ a: ParsedSample, _ b: ParsedSample) -> Bool {
        a.rolling == b.rolling && a.weekly == b.weekly && a.monthly == b.monthly
    }

    private static func missingWindows(
        solid: Result<ParsedSample, ParseFailure>,
        slot: Result<ParsedSample, ParseFailure>
    ) -> [String] {
        var missing = Set<String>()
        for name in ["rolling", "weekly", "monthly"] {
            if case .failure(.schemaDrift(_, let fields)) = solid, fields.contains(name) {
                missing.insert(name)
            }
            if case .failure(.schemaDrift(_, let fields)) = slot, fields.contains(name) {
                missing.insert(name)
            }
        }
        if missing.isEmpty { return ["rolling", "weekly", "monthly"] }
        return Array(missing).sorted()
    }

    private static func isValidPercent(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 100
    }

    private static func isValidReset(_ seconds: TimeInterval, max: TimeInterval) -> Bool {
        seconds.isFinite && seconds >= 0 && seconds <= max
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }

    private static func parseHumanReadableTime(_ timeStr: String) -> TimeInterval? {
        let normalized = timeStr.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if ["reset-now", "reset now", "now", "resets now"].contains(normalized) {
            return 0
        }
        var total: TimeInterval = 0
        let patterns: [(String, TimeInterval)] = [
            (#"(\d+(?:\.\d+)?)\s*days?"#, 86400),
            (#"(\d+(?:\.\d+)?)\s*hours?"#, 3600),
            (#"(\d+(?:\.\d+)?)\s*minutes?"#, 60),
            (#"(\d+(?:\.\d+)?)\s*seconds?"#, 1),
        ]
        var matched = false
        for (pattern, unit) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let capture = Range(match.range(at: 1), in: normalized),
                  let value = Double(normalized[capture])
            else { continue }
            matched = true
            total += value * unit
        }
        return matched ? total : nil
    }
}
