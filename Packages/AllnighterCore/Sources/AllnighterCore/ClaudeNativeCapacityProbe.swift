import Foundation

/// Reader for claude_code's **native** on-disk cache channel — the primary
/// acquisition path for `claude_code` (`Capacity_Native_Channels.md` §2),
/// replacing the `/usage` TUI screen scrape (`ClaudeCapacityLog`) as the
/// seat's fallback.
///
/// Channel: `cachedUsageUtilization` inside `~/.claude.json` — a cache the
/// CLI writes and refreshes on its own schedule (measured live: `fetchedAtMs`
/// ~5 minutes old under active use). A pure file read: no spawn, no PTY, no
/// rendered screen, zero credentials. The sibling `accountUuid` field sits
/// next to it in the same object; this reader never reads, stores, or logs
/// it — only the two usage windows and their two timestamps are needed.
///
/// Attribution: this parser answers only for `sourceId == "claude_code"` — it
/// is never applied to another vendor's payload and never influences one.
///
/// Fail closed, always. Never throws. Missing/unreadable file, malformed
/// JSON, an absent `cachedUsageUtilization`, an unjudgeable or stale fetch
/// time, or a known bucket with a non-numeric `utilization` / unparseable
/// `resets_at` drops just that bucket (matching `AgyNativeCapacityProbe` /
/// `CodexNativeCapacityProbe`'s per-bucket fail-closed shape); zero
/// surviving buckets is no observation at all. Unknown/null sibling keys in
/// `utilization` (`nimbus_quill`, `tangelo`, `iguana_necktie`, `limits`,
/// `spend`, …) are ignored by construction — only `five_hour` and
/// `seven_day` are ever read by name, and the object is known to grow more
/// such keys without warning.
public enum ClaudeNativeCapacityProbe {

    /// How old `fetchedAtMs` may be before the cache is refused as stale.
    ///
    /// This file is rewritten on Claude Code's own schedule, not ours, and
    /// goes arbitrarily stale once Claude Code stops running — there is no
    /// signal here for "still current" beyond this one timestamp. Measured
    /// live, `fetchedAtMs` was ~5 minutes old under active use; 15 minutes is
    /// roughly three times that, generous enough to survive a normal gap
    /// between turns without treating every idle minute as stale, tight
    /// enough that a reading left over from a closed session cannot be
    /// published as current. A stale reading presented as current is the
    /// expensive failure this whole channel exists to avoid; falling through
    /// to the TUI probe is the cheap one.
    public static let maxAge: TimeInterval = 15 * 60

    /// `~/.claude.json` under the given home directory.
    public static func fileURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
    }

    // MARK: - Public entry

    /// Read + parse the cache end to end. Returns `nil` on any failure — file
    /// missing, unreadable, or the payload fails closed — so the caller falls
    /// through to the TUI probe unchanged. Never throws.
    public static func fetch(homeDirectory: URL, now: Date) -> [CapacityWindow]? {
        let url = fileURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8)
        else { return nil }
        return capacityWindows(fromFileContent: content, now: now)
    }

    // MARK: - Parse (fail closed)

    /// Parse raw `~/.claude.json` content into normalized windows, or `nil`
    /// when there is nothing safe to report. Never throws.
    ///
    /// `now` is the wall clock of this read and becomes each window's
    /// `observedAt` — `fetchedAtMs` is used only to gate staleness and is
    /// never surfaced as if it were our own observation time.
    public static func capacityWindows(fromFileContent content: String, now: Date) -> [CapacityWindow]? {
        guard let data = content.data(using: .utf8) else { return nil }
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            root = obj
        } catch {
            return nil
        }

        guard let cache = root["cachedUsageUtilization"] as? [String: Any] else { return nil }

        // fetchedAtMs governs staleness for the whole cache object — both
        // buckets share one fetch. Missing/non-numeric is refused outright:
        // freshness cannot be judged without it, and an unjudgeable reading
        // is never presented as current.
        guard let fetchedAtMs = doubleValue(cache["fetchedAtMs"]) else { return nil }
        let fetchedAt = Date(timeIntervalSince1970: fetchedAtMs / 1000.0)
        guard now.timeIntervalSince(fetchedAt) <= maxAge else { return nil }

        guard let utilization = cache["utilization"] as? [String: Any] else { return nil }

        var windows: [CapacityWindow] = []
        // Only these two names are read by construction. Every other key in
        // `utilization` — `nimbus_quill`, `tangelo`, `iguana_necktie`,
        // `limits`, `spend`, whatever appears next — is never iterated and
        // never guessed at.
        //
        // Scope choice matches `ClaudeCapacityLog` (the existing TUI
        // fallback for this same source): the ~5h rolling window is
        // `.session`, weekly is `.weekly`, so a source can move between the
        // native and TUI tiers without its scope identity shifting under it.
        if let window = parseBucket(utilization["five_hour"], scope: .session, observedAt: now) {
            windows.append(window)
        }
        if let window = parseBucket(utilization["seven_day"], scope: .weekly, observedAt: now) {
            windows.append(window)
        }
        return windows.isEmpty ? nil : windows
    }

    /// One known bucket → one window, or `nil` if anything about it is not
    /// trustworthy. Never throws, never defaults a missing percentage to 0.
    private static func parseBucket(
        _ any: Any?,
        scope: CapacityWindowScope,
        observedAt: Date
    ) -> CapacityWindow? {
        guard let bucket = any as? [String: Any] else { return nil }

        // `utilization` is the vendor's own USED percent (verified live
        // against what alln already publishes: seven_day 76 ↔ 24% remaining
        // shown today) — never remaining, never inverted twice. Non-numeric,
        // including JSON `true`/`false`, is refused rather than coerced.
        guard let usedPercent = doubleValue(bucket["utilization"]) else { return nil }

        // `resets_at` carries its own explicit UTC offset on this channel
        // (`…+00:00`) — parsed as written, never assumed to be UTC or local.
        guard let resetsAtRaw = bucket["resets_at"] as? String,
              let resetAt = parseISO8601(resetsAtRaw)
        else { return nil }

        return CapacityWindow(
            used: usedPercent,
            source: "claude_code",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .onDisk,
            poolLabel: nil
        )
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        // Must be checked BEFORE `any as? Double` / `any as? Int` — Swift's
        // dynamic cast happily coerces a JSON `true`/`false` (bridged as
        // NSNumber/CFBoolean) into `1.0`/`0.0` through those casts, so the
        // later CFBoolean guard on the NSNumber branch below is never
        // reached and a bool silently becomes a number. Caught by
        // `testBooleanUtilizationIsRefusedNotCoerced` — the same
        // `as? Double` ordering in the agy/codex precedent parsers has this
        // same latent gap, just never exercised by a bool fixture there.
        if any is Bool { return nil }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue
        }
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
