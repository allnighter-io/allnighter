import Foundation

/// Parser for agy's **native** print-mode JSON channel — the primary
/// acquisition path for `agy` (`Capacity_Native_Channels.md` §2), replacing
/// the PTY `/usage` screen scrape (`AgyCapacityLog`) as the seat's fallback.
///
/// Channel: `agy --print "/usage" --output-format json --print-timeout 25s`.
/// Measured on the dogfood host: ~1-8s wall, zero model tokens, structured
/// `command.data.groups[].buckets[]` with `remaining_fraction` (0…1) and
/// `reset_time` (ISO8601) for both the weekly and 5-hour window in each pool.
///
/// The sibling `response` field is rendered text for a human — **never**
/// parsed here. Only `command.data.groups[]` is read; that is the vendor's
/// structured truth, not text formatted for a terminal.
///
/// Attribution: this parser answers only for `sourceId == "agy"` — it is
/// never applied to another vendor's payload and never influences one.
///
/// Fail closed, always. Never throws. A `status != "SUCCESS"` payload,
/// malformed/empty JSON, an unrecognized shape, or a single bucket with an
/// unrecognized `window` value or out-of-range `remaining_fraction` produces
/// **no window** for that bucket — never an inferred or defaulted number.
public enum AgyNativeCapacityProbe {

    /// argv for the native channel. The prompt argument lands immediately
    /// after `--print` for agy (see `CapacityPaneReader.readerArgv`).
    public static func argv(prompt: String = "/usage") -> [String] {
        ["--print", prompt, "--output-format", "json", "--print-timeout", "25s"]
    }

    /// Our own external wall-clock budget for the child process. Kept well
    /// under agy's own `--print-timeout` (25s) and under the acquisition
    /// ladder's per-source budget (`CapacityProbe.timeout(for: "agy")` = 20s)
    /// so a slow native attempt still leaves time for the PTY fallback within
    /// the same probe call. Measured wall time on the dogfood host is 1-8s —
    /// this is headroom, not the expected case.
    public static let processTimeout: TimeInterval = 12

    /// Parse one raw stdout capture from the native command into normalized
    /// windows. Never throws. Returns `[]` (no observation, caller falls back
    /// to the PTY scrape) on any recognized-failure shape: malformed JSON,
    /// missing `status`, `status != "SUCCESS"`, or no readable buckets.
    public static func capacityWindows(fromOutput output: String, observedAt: Date) -> [CapacityWindow] {
        guard let data = output.data(using: .utf8) else { return [] }
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            root = obj
        } catch {
            return []
        }

        // The vendor's own declared outcome. Never inferred from shape alone —
        // a payload could be well-formed and still say the call failed.
        guard let status = root["status"] as? String, status == "SUCCESS" else { return [] }

        guard let command = root["command"] as? [String: Any],
              let commandData = command["data"] as? [String: Any],
              let groups = commandData["groups"] as? [[String: Any]]
        else { return [] }

        var windows: [CapacityWindow] = []
        for group in groups {
            guard let poolLabel = group["name"] as? String,
                  let buckets = group["buckets"] as? [[String: Any]]
            else { continue }
            for bucket in buckets {
                guard let window = parseBucket(bucket, poolLabel: poolLabel, observedAt: observedAt)
                else { continue }
                windows.append(window)
            }
        }
        return windows
    }

    // MARK: - Bucket parse (fail closed per bucket)

    private static func parseBucket(
        _ bucket: [String: Any],
        poolLabel: String,
        observedAt: Date
    ) -> CapacityWindow? {
        guard let windowKind = bucket["window"] as? String,
              let scope = scope(forWindowKind: windowKind)
        else { return nil }

        // remaining_fraction is the vendor's own 0…1 fraction — never a percent,
        // never derived from anything else. Out of range is refused, not clamped.
        guard let fraction = doubleValue(bucket["remaining_fraction"]),
              fraction >= 0, fraction <= 1
        else { return nil }

        guard let resetString = bucket["reset_time"] as? String,
              let resetAt = parseISO8601(resetString)
        else { return nil }

        return CapacityWindow(
            remaining: fraction * 100.0,
            source: "agy",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .headlessJSON,
            poolLabel: poolLabel
        )
    }

    /// Only the two window kinds this channel has ever been observed to emit.
    /// An unrecognized kind is dropped, not guessed at — a future vendor value
    /// must not silently land in the wrong scope.
    private static func scope(forWindowKind raw: String) -> CapacityWindowScope? {
        switch raw {
        case "weekly": return .weekly
        case "5h": return .fiveHour
        default: return nil
        }
    }

    // The `NSNumber`/`CFBoolean` branch is checked FIRST, before falling
    // back to `any as? Double`/`any as? Int` — those direct casts also
    // succeed for a CFBoolean-backed NSNumber (JSON `true`/`false` bridges
    // to one), coercing it into `1.0` before the CFBoolean guard ever runs.
    // Do NOT "fix" this with a blanket `any is Bool` pre-check instead:
    // Swift's NSNumber/Bool bridging has its own trap the other way —
    // `(0 as NSNumber) is Bool` and `(1 as NSNumber) is Bool` are BOTH
    // `true` on Darwin, so that shortcut would silently refuse a legitimate
    // 0%/1% `remaining_fraction` too. `CFGetTypeID` against
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

    private static func parseISO8601(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
