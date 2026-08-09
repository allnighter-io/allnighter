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
/// it — only `utilization.limits[]` and the one shared fetch timestamp are
/// needed.
///
/// Source of truth is `utilization.limits[]`, not the sibling `five_hour` /
/// `seven_day` keys — a prior version of this reader used those two names
/// and silently dropped the model-scoped weekly pool (`weekly_scoped`,
/// `scope.model.display_name`) that `limits[]` also carries, a real,
/// observed regression versus the old TUI scrape. `limits[]` entries seen
/// live: `session` (the ~5h rolling window), `weekly_all` (the primary/
/// dashboard weekly window), and `weekly_scoped` (a secondary weekly window
/// tied to one model, e.g. `display_name: "Fable"`). Every entry's `percent`
/// is the vendor's own USED percent, never remaining, never inverted twice.
///
/// Attribution: this parser answers only for `sourceId == "claude_code"` — it
/// is never applied to another vendor's payload and never influences one.
///
/// Fail closed, always. Never throws. Missing/unreadable file, malformed
/// JSON, an absent `cachedUsageUtilization`, an unjudgeable or stale fetch
/// time, or a `limits[]` entry with a non-numeric `percent` / unparseable
/// `resets_at` drops just that entry (matching `AgyNativeCapacityProbe` /
/// `CodexNativeCapacityProbe`'s per-bucket fail-closed shape); zero
/// surviving entries is no observation at all. An entry whose `kind` is not
/// one of the three known values is ignored silently, never guessed at and
/// never allowed to block the known ones — `limits[]` is documented to grow
/// more kinds without warning. `scope` is read only for `weekly_scoped`, and
/// only `scope.model.display_name` — a missing/null scope yields `poolLabel
/// == nil`, never a fabricated label. `is_active` is not surfaced: nothing in
/// `CapacityWindow` claims that meaning today, and inventing one the vendor
/// never documented is worse than omitting it.
///
/// Known accepted loss: the old TUI scrape also reported `planTier: "Max"`,
/// read from Claude Code's boot banner text. That string does not exist
/// anywhere in `~/.claude.json` — reading it would require a credential or
/// the TUI itself, and guessing a tier from utilization numbers would be a
/// locally computed value presented as vendor-stated fact. `planTier` stays
/// absent on this channel; this is accepted, not a bug to chase here.
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
        guard let limits = utilization["limits"] as? [Any] else { return nil }

        // Every entry is attempted independently — one malformed/unknown
        // entry never blocks the others.
        let windows = limits.compactMap { parseLimit($0, observedAt: now) }
        return windows.isEmpty ? nil : windows
    }

    /// `kind` → scope, for the only three values ever observed live. Any
    /// other `kind` (including one this array grows tomorrow) is not in this
    /// map and is dropped by the caller — never guessed into the nearest
    /// scope.
    private static let knownKindScopes: [String: CapacityWindowScope] = [
        "session": .session,
        "weekly_all": .weekly,
        "weekly_scoped": .weekly,
    ]

    /// One `limits[]` entry → one window, or `nil` if the `kind` is unknown
    /// or anything about the entry is not trustworthy. Never throws, never
    /// defaults a missing percentage to 0.
    private static func parseLimit(_ any: Any, observedAt: Date) -> CapacityWindow? {
        guard let item = any as? [String: Any] else { return nil }

        // Unknown kind → silently ignored, not guessed at. Matches the
        // vendor's own future-growth warning on this array.
        guard let kind = item["kind"] as? String,
              let scope = knownKindScopes[kind]
        else { return nil }

        // `percent` is the vendor's own USED percent (verified live against
        // what alln already publishes: weekly_all 77 ↔ 23% remaining shown
        // today) — never remaining, never inverted twice. Non-numeric,
        // including JSON `true`/`false`, is refused rather than coerced.
        guard let usedPercent = doubleValue(item["percent"]) else { return nil }

        // `resets_at` carries its own explicit UTC offset on this channel
        // (`…+00:00`) — parsed as written, never assumed to be UTC or local.
        guard let resetsAtRaw = item["resets_at"] as? String,
              let resetAt = parseISO8601(resetsAtRaw)
        else { return nil }

        // Only `weekly_scoped` ever carries a pool label, and only when the
        // vendor actually names a model — a null/missing `scope` yields
        // `nil`, never a fabricated label. The vendor's `display_name` is
        // used verbatim, never reformatted.
        var poolLabel: String?
        if kind == "weekly_scoped" {
            let scopeObject = item["scope"] as? [String: Any]
            let modelObject = scopeObject?["model"] as? [String: Any]
            poolLabel = modelObject?["display_name"] as? String
        }

        return CapacityWindow(
            used: usedPercent,
            source: "claude_code",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .onDisk,
            poolLabel: poolLabel
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
