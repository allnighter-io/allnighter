import Foundation

/// One weekly billing window extracted from the grok CLI's unified log
/// (`~/.grok/logs/unified.jsonl`, msg == "billing: fetched credits config").
/// Pure surface — converts to `CapacityWindow` via `asCapacityWindow()`.
/// Not wired to `CapacityObservation` / `SourceCapacityLedger` yet.
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

    /// Normalize into the shared `CapacityWindow` surface.
    ///
    /// Grok is used-polarity, weekly scope, exact ISO8601 reset, on-disk tier.
    /// On-demand and prepaid are dimensionless vendor units (`unit == nil`), never dollars.
    public func asCapacityWindow() -> CapacityWindow {
        let cap = Double(onDemandCap)
        let used = Double(onDemandUsed)
        return CapacityWindow(
            used: usedPercent,
            source: "grok",
            scope: .weekly,
            resetAt: periodEnd,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .onDisk,
            planTier: subscriptionTier,
            onDemand: CapacityPaidAmount(
                used: used,
                cap: cap,
                remaining: max(0.0, cap - used),
                unit: nil
            ),
            prepaidBalance: Double(prepaidBalance)
        )
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

    /// Parse then normalize the latest weekly window into a shared `CapacityWindow`.
    public static func capacityWindow(fromLogContent content: String) -> CapacityWindow? {
        latestWeeklyWindow(fromLogContent: content)?.asCapacityWindow()
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

    // The `NSNumber`/`CFBoolean` branch is checked FIRST in both helpers
    // below, before falling back to `any as? Double`/`any as? Int` — those
    // direct casts also succeed for a CFBoolean-backed NSNumber (JSON
    // `true`/`false` bridges to one), coercing it into `1.0`/`1` before the
    // CFBoolean guard ever runs. Do NOT "fix" this with a blanket `any is
    // Bool` pre-check instead: Swift's NSNumber/Bool bridging has its own
    // trap the other way — `(0 as NSNumber) is Bool` and `(1 as NSNumber) is
    // Bool` are BOTH `true` on Darwin, so that shortcut would silently
    // refuse a legitimate 0%/1% value too. `CFGetTypeID` against
    // `CFBooleanGetTypeID()` is the only discriminator that gets both
    // directions right.
    private static func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue
        }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.intValue
        }
        if let i = any as? Int { return i }
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

    // MARK: - Disk log scan (parser utility — not capacity display)

    /// Reverse-scan `unified.jsonl` for the newest billing weekly record.
    ///
    /// Used by log-parser tests and diagnostics — **not** the capacity display path.
    public static func latestWeeklyWindowReadingBackwards(
        from url: URL,
        chunkSize: Int = 64 * 1024
    ) -> GrokWeeklyCapacity? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return nil
        }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            return nil
        }
        if fileSize == 0 { return nil }

        let chunk = max(1, chunkSize)
        var offset = fileSize
        var carry = Data()

        while offset > 0 {
            let readSize = UInt64(chunk)
            let start = offset > readSize ? offset - readSize : 0
            let length = offset - start
            do {
                try handle.seek(toOffset: start)
            } catch {
                return nil
            }
            let data: Data
            do {
                guard let slice = try handle.read(upToCount: Int(length)) else { return nil }
                data = slice
            } catch {
                return nil
            }
            offset = start

            var block = data
            block.append(carry)

            let parts = splitLinesKeepingEmpties(block)
            let complete: ArraySlice<Data>
            if start > 0 {
                carry = parts.first ?? Data()
                complete = parts.dropFirst()
            } else {
                carry = Data()
                complete = parts[...]
            }

            for lineData in complete.reversed() {
                guard !lineData.isEmpty,
                      let line = String(data: lineData, encoding: .utf8)
                else { continue }
                if let window = latestWeeklyWindow(fromLogContent: line) {
                    return window
                }
            }
        }

        if !carry.isEmpty, let line = String(data: carry, encoding: .utf8) {
            return latestWeeklyWindow(fromLogContent: line)
        }
        return nil
    }

    private static func splitLinesKeepingEmpties(_ data: Data) -> [Data] {
        var parts: [Data] = []
        var start = data.startIndex
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == 0x0A {
                parts.append(data[start..<i])
                i = data.index(after: i)
                start = i
            } else {
                i = data.index(after: i)
            }
        }
        parts.append(data[start..<data.endIndex])
        if parts.last?.isEmpty == true {
            parts.removeLast()
        }
        return parts
    }
}
