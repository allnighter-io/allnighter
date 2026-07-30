import Foundation

/// One rate-limit window extracted from a Codex rollout `token_count` event
/// (`~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*.jsonl`).
/// Pure surface — converts to `CapacityWindow` via `asCapacityWindow()`.
/// Not wired to `CapacityObservation` / `SourceCapacityLedger` yet.
public struct CodexCapacityWindow: Sendable, Equatable {
    /// `used_percent` from primary or secondary (0…100+).
    public let usedPercent: Double
    /// Scope derived only from `window_minutes` (10080 → weekly, 300 → fiveHour).
    public let scope: CapacityWindowScope
    /// `resets_at` unix epoch. Re-bases each cycle — not a stable window key.
    public let resetAt: Date
    /// Wall clock of the log record (`timestamp`).
    public let observedAt: Date
    /// `plan_type` when present (e.g. "plus", "pro").
    public let planType: String?
    /// `credits.balance` when present and numeric. Never defaulted to 0.
    public let creditsBalance: Double?

    public init(
        usedPercent: Double,
        scope: CapacityWindowScope,
        resetAt: Date,
        observedAt: Date,
        planType: String?,
        creditsBalance: Double?
    ) {
        self.usedPercent = usedPercent
        self.scope = scope
        self.resetAt = resetAt
        self.observedAt = observedAt
        self.planType = planType
        self.creditsBalance = creditsBalance
    }

    /// Normalize into the shared `CapacityWindow` surface.
    ///
    /// Codex is used-polarity, exact unix reset, on-disk tier. Credits balance
    /// is prepaid vendor units (`unit == nil`), never dollars. Scope is only
    /// weekly or fiveHour — unknown `window_minutes` never reach here.
    public func asCapacityWindow() -> CapacityWindow {
        CapacityWindow(
            used: usedPercent,
            source: "codex",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .onDisk,
            planTier: planType,
            prepaidBalance: creditsBalance
        )
    }
}

/// Read-only extractor for Codex session rollout `token_count` rate-limit snapshots.
/// Takes log **content**, never a path — call sites own IO. Fail closed: garbage,
/// missing fields, unknown window sizes, and non-numeric credits are absent,
/// never defaulted. `model_context_window` is session context size, not quota —
/// it is never emitted as a capacity window.
public enum CodexCapacityLog {

    private static let weeklyMinutes = 10_080
    private static let fiveHourMinutes = 300

    /// Most recent token_count record's rate-limit windows in `content` (JSON lines).
    /// "Most recent" is the record `timestamp`, never `resets_at` (weekly re-bases).
    /// Unrelated lines are ignored. Malformed input never throws. Empty when none.
    public static func latestWindows(fromLogContent content: String) -> [CodexCapacityWindow] {
        var bestObservedAt: Date?
        var bestWindows: [CodexCapacityWindow] = []

        content.enumerateLines { line, _ in
            guard let candidate = parseLine(line) else { return }
            if let current = bestObservedAt {
                if candidate.observedAt > current {
                    bestObservedAt = candidate.observedAt
                    bestWindows = candidate.windows
                }
            } else {
                bestObservedAt = candidate.observedAt
                bestWindows = candidate.windows
            }
        }
        return bestWindows
    }

    /// Parse then normalize the latest record's windows into shared `CapacityWindow`s.
    public static func capacityWindows(fromLogContent content: String) -> [CapacityWindow] {
        latestWindows(fromLogContent: content).map { $0.asCapacityWindow() }
    }

    // MARK: - Line parse (fail closed)

    private struct ParsedRecord {
        let observedAt: Date
        let windows: [CodexCapacityWindow]
    }

    private static func parseLine(_ line: String) -> ParsedRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }

        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            root = obj
        } catch {
            return nil
        }

        guard let observedAt = parseDate(root["timestamp"] as? String) else { return nil }
        guard let payload = root["payload"] as? [String: Any] else { return nil }
        guard let payloadType = payload["type"] as? String, payloadType == "token_count" else {
            return nil
        }
        // rate_limits is a sibling of info under payload — not inside info.
        // info.model_context_window is deliberately ignored (session context, not quota).
        guard let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }

        // credits.balance is a STRING when present. Non-numeric → fail whole record
        // (wrong 0 is the dangerous direction for a later auto-spend gate).
        // Absent / null credits → prepaid absent (nil), not zero.
        let creditsBalance: Double?
        switch parseCreditsBalance(rateLimits["credits"]) {
        case .absent:
            creditsBalance = nil
        case .value(let v):
            creditsBalance = v
        case .invalid:
            return nil
        }

        let planType = rateLimits["plan_type"] as? String

        var windows: [CodexCapacityWindow] = []
        if let primary = rateLimits["primary"] as? [String: Any],
           let window = parseSlot(primary, observedAt: observedAt, planType: planType, creditsBalance: creditsBalance)
        {
            windows.append(window)
        }
        // secondary is often null — legitimate absence of the short-window slot.
        if let secondary = rateLimits["secondary"] as? [String: Any],
           let window = parseSlot(secondary, observedAt: observedAt, planType: planType, creditsBalance: creditsBalance)
        {
            windows.append(window)
        }

        // A token_count with no known-scope slots still counts as an observation
        // only when we have at least one window. Empty known windows → skip line
        // so an older good record can still win (unknown scopes are not samples).
        guard !windows.isEmpty else { return nil }
        return ParsedRecord(observedAt: observedAt, windows: windows)
    }

    private static func parseSlot(
        _ slot: [String: Any],
        observedAt: Date,
        planType: String?,
        creditsBalance: Double?
    ) -> CodexCapacityWindow? {
        // Never default a missing percentage to 0.
        guard let usedPercent = doubleValue(slot["used_percent"]) else { return nil }
        guard let minutes = intValue(slot["window_minutes"]) else { return nil }
        guard let scope = scope(forWindowMinutes: minutes) else { return nil }
        guard let resetsAt = unixDate(slot["resets_at"]) else { return nil }

        return CodexCapacityWindow(
            usedPercent: usedPercent,
            scope: scope,
            resetAt: resetsAt,
            observedAt: observedAt,
            planType: planType,
            creditsBalance: creditsBalance
        )
    }

    /// Only 10080 (weekly) and 300 (fiveHour). Anything else (e.g. free 43200) is skipped.
    private static func scope(forWindowMinutes minutes: Int) -> CapacityWindowScope? {
        switch minutes {
        case weeklyMinutes: return .weekly
        case fiveHourMinutes: return .fiveHour
        default: return nil
        }
    }

    private enum CreditsParse {
        case absent
        case value(Double)
        case invalid
    }

    /// `credits` may be null, missing, or `{"balance":"0",...}`. Balance is a string.
    private static func parseCreditsBalance(_ any: Any?) -> CreditsParse {
        guard let any, !(any is NSNull) else { return .absent }
        guard let dict = any as? [String: Any] else { return .invalid }
        guard let raw = dict["balance"], !(raw is NSNull) else { return .absent }
        // Must be a string — never silently accept a JSON number as if it were the field.
        guard let s = raw as? String else { return .invalid }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }
        // Reject non-numeric strings; never default to 0.
        guard let value = Double(trimmed) else { return .invalid }
        return .value(value)
    }

    private static func unixDate(_ any: Any?) -> Date? {
        if let i = any as? Int {
            return Date(timeIntervalSince1970: TimeInterval(i))
        }
        if let d = any as? Double {
            return Date(timeIntervalSince1970: d)
        }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue
        }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.intValue
        }
        return nil
    }

    /// Fractional seconds (e.g. `…329Z`) and plain ISO8601 both parse.
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
