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
            if case .failure(let slotErr) = slot, case .failure(let solidErr) = solid {
                switch slotErr {
                case .duplicateWindow, .invalidValue:
                    return slot
                case .schemaDrift(_, let slotMissing):
                    if case .schemaDrift(_, let solidMissing) = solidErr,
                       solidMissing.count == 3, slotMissing.count < 3 {
                        return slot
                    }
                default:
                    break
                }
            }
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

    // MARK: - Solid SSR (tokenizer)

    private static let solidWindowPattern =
        #"(rollingUsage|weeklyUsage|monthlyUsage):\$R\[\d+\]=\{"#

    private static func parseSolidBundle(html: String) -> Result<ParsedSample, ParseFailure> {
        var seenKeys: [String: [WindowSample]] = [:]

        guard let windowRegex = try? NSRegularExpression(pattern: solidWindowPattern) else {
            return .failure(.schemaDrift(strategy: ParseStrategy.solidSSR.rawValue,
                                         missing: ["rolling", "weekly", "monthly"]))
        }
        let nsRange = NSRange(html.startIndex..., in: html)
        for match in windowRegex.matches(in: html, range: nsRange) {
            guard let labelRange = Range(match.range(at: 1), in: html) else { continue }
            let label = String(html[labelRange])
            let shortName = String(label.dropLast(5))

            let matchEnd = match.range.location + match.range.length
            guard matchEnd < html.utf16.count else { continue }

            let bodyStart = String.Index(utf16Offset: matchEnd, in: html)
            guard let bodyEnd = findClosingBrace(in: html, from: bodyStart) else { continue }
            let body = String(html[bodyStart..<bodyEnd])

            guard let fields = tokenizeObjectBody(body),
                  let used = fields["usagePercent"],
                  let reset = fields["resetInSec"]
            else { continue }

            seenKeys[shortName, default: []].append(
                WindowSample(usedPercent: used, resetInSec: reset)
            )
        }

        let windowNames = ["rolling", "weekly", "monthly"]
        var windows: [String: WindowSample] = [:]
        for name in windowNames {
            guard let samples = seenKeys[name], !samples.isEmpty else {
                return .failure(.schemaDrift(strategy: ParseStrategy.solidSSR.rawValue,
                                             missing: windowNames))
            }
            let distinct = Set(samples.map { "\($0.usedPercent)|\($0.resetInSec)" })
            guard distinct.count == 1, let sample = samples.first else {
                return .failure(.duplicateWindow(name))
            }
            windows[name] = sample
        }

        guard let rolling = windows["rolling"],
              let weekly = windows["weekly"],
              let monthly = windows["monthly"]
        else {
            return .failure(.schemaDrift(strategy: ParseStrategy.solidSSR.rawValue,
                                         missing: windowNames))
        }
        return .success(ParsedSample(strategy: .solidSSR,
                                     rolling: rolling, weekly: weekly, monthly: monthly))
    }

    private static func findClosingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var inString = false
        var escapeNext = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if escapeNext {
                escapeNext = false
                text.formIndex(after: &i)
                continue
            }
            if inString {
                if ch == "\\" { escapeNext = true }
                else if ch == "\"" { inString = false }
                text.formIndex(after: &i)
                continue
            }
            if ch == "\"" { inString = true }
            else if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            text.formIndex(after: &i)
        }
        return nil
    }

    private static func tokenizeObjectBody(_ body: String) -> [String: Double]? {
        var result: [String: Double] = [:]
        var inString = false
        var escapeNext = false
        var braceDepth = 0
        var bracketDepth = 0
        var i = body.startIndex

        while i < body.endIndex {
            let ch = body[i]

            if escapeNext {
                escapeNext = false
                body.formIndex(after: &i)
                continue
            }
            if inString {
                if ch == "\\" { escapeNext = true }
                else if ch == "\"" { inString = false }
                body.formIndex(after: &i)
                continue
            }
            if ch == "\"" { inString = true; body.formIndex(after: &i); continue }
            if ch == "{" { braceDepth += 1; body.formIndex(after: &i); continue }
            if ch == "}" { if braceDepth > 0 { braceDepth -= 1 }; body.formIndex(after: &i); continue }
            if ch == "[" { bracketDepth += 1; body.formIndex(after: &i); continue }
            if ch == "]" { if bracketDepth > 0 { bracketDepth -= 1 }; body.formIndex(after: &i); continue }

            if braceDepth == 0 && bracketDepth == 0 && (ch.isLetter || ch == "_") {
                let fieldStart = i
                body.formIndex(after: &i)
                while i < body.endIndex && (body[i].isLetter || body[i].isNumber || body[i] == "_") {
                    body.formIndex(after: &i)
                }
                if i < body.endIndex && body[i] == ":" {
                    let fieldName = String(body[fieldStart..<i])
                    body.formIndex(after: &i)
                    if let value = readNumberValue(in: body, from: &i) {
                        if let existing = result[fieldName], existing != value {
                            return nil
                        }
                        result[fieldName] = value
                    }
                }
                continue
            }

            body.formIndex(after: &i)
        }
        return result
    }

    private static func readNumberValue(in body: String, from i: inout String.Index) -> Double? {
        while i < body.endIndex {
            let ch = body[i]
            if ch.isNumber || ch == "-" {
                let numStart = i
                body.formIndex(after: &i)
                while i < body.endIndex {
                    let nch = body[i]
                    if nch.isNumber || nch == "." { body.formIndex(after: &i) }
                    else { break }
                }
                return Double(String(body[numStart..<i]))
            }
            if ch == "\"" {
                body.formIndex(after: &i)
                var escaped = false
                while i < body.endIndex {
                    let qch = body[i]
                    if escaped { escaped = false }
                    else if qch == "\\" { escaped = true }
                    else if qch == "\"" { break }
                    body.formIndex(after: &i)
                }
                if i < body.endIndex { body.formIndex(after: &i) }
                continue
            }
            return nil
        }
        return nil
    }

    // MARK: - data-slot HTML

    private static func parseDataSlotBundle(html: String) -> Result<ParsedSample, ParseFailure> {
        let map: [String: WindowSample]
        switch parseDataSlotFormat(html: html) {
        case .success(let parsed): map = parsed
        case .failure(let err): return .failure(err)
        }
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

    private static func parseDataSlotFormat(html: String) -> Result<[String: WindowSample], ParseFailure> {
        var result: [String: WindowSample] = [:]
        let parts = html.components(separatedBy: "data-slot=\"usage-item\"")
        guard parts.count > 1 else { return .success(result) }
        for part in parts.dropFirst() {
            guard let label = firstMatch(in: part, pattern: #"data-slot="usage-label">([^<]+)<"#),
                  let usageRaw = firstMatch(in: part, pattern: #"data-slot="usage-value">[^<]*?(\d+(?:\.\d+)?)\s*%"#),
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
            var matchKeys: [String] = []
            if labelLower.contains("rolling") { matchKeys.append("rolling") }
            if labelLower.contains("weekly") { matchKeys.append("weekly") }
            if labelLower.contains("monthly") { matchKeys.append("monthly") }
            let key: String? = matchKeys.count == 1 ? matchKeys[0] : nil
            if let key {
                let sample = WindowSample(usedPercent: usage, resetInSec: resetInSec)
                if let existing = result[key], existing != sample {
                    return .failure(.duplicateWindow(key))
                }
                result[key] = sample
            }
        }
        return .success(result)
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
