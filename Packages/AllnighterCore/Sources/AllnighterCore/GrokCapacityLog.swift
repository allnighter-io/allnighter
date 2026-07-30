import Foundation

/// One weekly billing window extracted from the grok CLI's unified log
/// (`~/.grok/logs/unified.jsonl`, msg == "billing: fetched credits config").
/// Pure surface for a later capacity slice — not wired to `CapacityWindow` /
/// `CapacityObservation` / `SourceCapacityLedger` yet.
public struct GrokWeeklyCapacity: Sendable, Equatable {
    /// `creditUsagePercent` — fraction of the weekly allowance already used (0…100+).
    public let usedPercent: Double
    /// Start of the current weekly period (`currentPeriod.start`).
    public let periodStart: Date
    /// End of the current weekly period (`currentPeriod.end`) — the reset.
    public let periodEnd: Date
    /// Wall clock of the log record (`ts`).
    public let observedAt: Date
    /// e.g. "X Premium+".
    public let subscriptionTier: String
    /// On-demand spend cap (`onDemandCap.val`). Surface, never invent 0.
    public let onDemandCap: Int
    /// On-demand spend so far (`onDemandUsed.val`).
    public let onDemandUsed: Int
    /// Prepaid balance (`prepaidBalance.val`). Later slices must not auto-spend this.
    public let prepaidBalance: Int

    public init(
        usedPercent: Double,
        periodStart: Date,
        periodEnd: Date,
        observedAt: Date,
        subscriptionTier: String,
        onDemandCap: Int,
        onDemandUsed: Int,
        prepaidBalance: Int
    ) {
        self.usedPercent = usedPercent
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.observedAt = observedAt
        self.subscriptionTier = subscriptionTier
        self.onDemandCap = onDemandCap
        self.onDemandUsed = onDemandUsed
        self.prepaidBalance = prepaidBalance
    }
}

/// Read-only extractor for grok CLI billing snapshots written to unified.jsonl.
/// Takes log **content**, never a path — call sites own IO. Fail closed: garbage,
/// missing fields, and unknown period types are absent, never defaulted.
public enum GrokCapacityLog {

    private static let billingMsg = "billing: fetched credits config"
    private static let weeklyPeriodType = "USAGE_PERIOD_TYPE_WEEKLY"

    /// Most recent weekly capacity window in `content` (JSON lines), or nil.
    /// Unrelated lines are ignored. Malformed input never throws.
    public static func latestWeeklyWindow(fromLogContent content: String) -> GrokWeeklyCapacity? {
        var best: GrokWeeklyCapacity?
        content.enumerateLines { line, _ in
            guard let candidate = parseLine(line) else { return }
            if let current = best {
                if candidate.observedAt > current.observedAt {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best
    }

    // MARK: - Line parse (fail closed)

    private static func parseLine(_ line: String) -> GrokWeeklyCapacity? {
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

        guard let msg = root["msg"] as? String, msg == billingMsg else { return nil }
        guard let observedAt = parseDate(root["ts"] as? String) else { return nil }
        guard let ctx = root["ctx"] as? [String: Any] else { return nil }
        guard let config = ctx["config"] as? [String: Any] else { return nil }

        // Never default a missing percentage to 0.
        guard let usedPercent = doubleValue(config["creditUsagePercent"]) else { return nil }

        guard let period = config["currentPeriod"] as? [String: Any],
              let periodType = period["type"] as? String,
              periodType == weeklyPeriodType,
              let periodStart = parseDate(period["start"] as? String),
              let periodEnd = parseDate(period["end"] as? String)
        else { return nil }

        guard let subscriptionTier = ctx["subscriptionTier"] as? String else { return nil }

        // Required so a later slice can refuse auto-spend against paid balances.
        guard let onDemandCap = moneyVal(config["onDemandCap"]),
              let onDemandUsed = moneyVal(config["onDemandUsed"]),
              let prepaidBalance = moneyVal(config["prepaidBalance"])
        else { return nil }

        return GrokWeeklyCapacity(
            usedPercent: usedPercent,
            periodStart: periodStart,
            periodEnd: periodEnd,
            observedAt: observedAt,
            subscriptionTier: subscriptionTier,
            onDemandCap: onDemandCap,
            onDemandUsed: onDemandUsed,
            prepaidBalance: prepaidBalance
        )
    }

    /// `{"val": N}` — absent or non-object is nil (not 0).
    private static func moneyVal(_ any: Any?) -> Int? {
        guard let dict = any as? [String: Any] else { return nil }
        return intValue(dict["val"])
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber {
            // Reject bool masquerading as number (JSON true/false → NSNumber).
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

    /// Fractional seconds and non-Z offsets (e.g. `…374130+00:00`) must both parse.
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
