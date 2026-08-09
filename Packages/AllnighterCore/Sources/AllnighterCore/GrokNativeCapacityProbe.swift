import Foundation

/// Reader for grok's **native** on-disk log channel — the primary
/// acquisition path for `grok` (`Capacity_Native_Channels.md` §2), replacing
/// the `/usage` TUI screen scrape (`GrokCapacityProbe`) as the seat's
/// fallback.
///
/// Channel: the newest `billing: fetched credits config` line in
/// `~/.grok/logs/unified.jsonl` — a log grok's CLI already writes on every
/// interactive launch. Parsing is `GrokCapacityLog` (pure, content-only,
/// already written and correct); this file owns the IO that
/// `GrokCapacityLog` deliberately does not — on this host the log is
/// 4.5 MB / 17,635 lines / 550 billing records and only grows, so a
/// capacity refresh must never load it whole.
///
/// Never spawns grok, never reads a credential, and never triggers grok's
/// own billing refresh (`GET cli-chat-proxy.grok.com/v1/billing`, which
/// needs grok's stored token — forbidden) — this reads only what the CLI
/// already wrote to disk (Capacity_Native_Channels.md §4).
///
/// Attribution: this channel answers only for `sourceId == "grok"`.
public enum GrokNativeCapacityProbe {

    /// Bytes read from the tail of `unified.jsonl` before giving up.
    ///
    /// Measured live on the dogfood host across the newest 20
    /// `billing: fetched credits config` records: byte gaps between
    /// consecutive billing lines ranged 591–9,201 (roughly one line per
    /// interactive launch). Across the *whole* file the p95 gap was
    /// ~10.8 KB and the p99 gap ~70 KB — a single long-running chat session
    /// can push the newest billing line much further back than the typical
    /// case. 64 KiB sits just under that measured p99, so it catches the
    /// newest record in the overwhelming majority of real sessions while
    /// staying under 1.5% of the file's current 4.5 MB size. When the
    /// newest record falls outside even that generous a window, the honest
    /// answer is that this channel has been quiet for unusually long —
    /// `fetch` falls through to the TUI probe rather than escalating to a
    /// full-file read to chase it.
    public static let tailByteBudget = 64 * 1024

    /// How old the log record's own `ts` may be before this channel is
    /// refused as stale.
    ///
    /// Unlike claude_code's cache — rewritten on a background timer, so
    /// `fetchedAtMs` is only ever a few minutes old under active use — grok
    /// appends this line *only* when a full interactive session launches
    /// (`Capacity_Native_Channels.md`, "grok — investigated 2026-08-08":
    /// `grok --version` / `models` / `inspect` / `agent` were all measured
    /// live NOT to refresh it). On an idle machine the newest line can be
    /// legitimately hours old through no fault of this channel, so
    /// claude_code's 15-minute bound would refuse perfectly good readings
    /// between ordinary grok sessions. 30 minutes is chosen to comfortably
    /// survive a normal gap between invocations within one working session
    /// while still refusing a reading left over from a session that ended a
    /// while ago. A stale reading presented as current is the expensive
    /// failure this channel exists to avoid; falling through to the TUI
    /// probe is the cheap one.
    public static let maxAge: TimeInterval = 30 * 60

    /// `~/.grok/logs/unified.jsonl` under the given home directory.
    public static func fileURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("unified.jsonl", isDirectory: false)
    }

    // MARK: - Public entry

    /// Read a bounded tail of the log, parse the newest billing line via
    /// `GrokCapacityLog`, and gate on staleness — end to end. Returns `nil`
    /// on any failure (file missing/unreadable, no billing line in the
    /// tail, malformed JSON, stale record) so the caller falls through to
    /// the TUI probe unchanged. Never throws.
    public static func fetch(homeDirectory: URL, now: Date) -> [CapacityWindow]? {
        guard let tail = readTail(url: fileURL(homeDirectory: homeDirectory), byteBudget: tailByteBudget)
        else { return nil }
        return capacityWindows(fromTailContent: tail, now: now)
    }

    /// Parse an already-read tail string into a fresh-enough window, or
    /// `nil`. Split out from `fetch` so a captured tail — including one
    /// whose leading line is deliberately truncated — can be exercised in
    /// tests without touching disk.
    public static func capacityWindows(fromTailContent tail: String, now: Date) -> [CapacityWindow]? {
        guard let window = GrokCapacityLog.latestWeeklyWindow(fromLogContent: tail) else { return nil }
        guard now.timeIntervalSince(window.observedAt) <= maxAge else { return nil }
        return [window.asCapacityWindow()]
    }

    // MARK: - Bounded tail IO

    /// Read at most the last `byteBudget` bytes of `url`, split at line
    /// boundaries (byte-level, so a multi-byte UTF-8 character can never be
    /// split mid-character across the read boundary), and drop a leading
    /// fragment that started mid-line. One bounded read only — file
    /// missing, unreadable, empty, or any seek/read failure returns `nil`
    /// rather than escalating to a full-file scan. Never throws.
    static func readTail(url: URL, byteBudget: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            return nil
        }
        guard fileSize > 0 else { return nil }

        let budget = UInt64(max(0, byteBudget))
        let start = fileSize > budget ? fileSize - budget : 0
        do {
            try handle.seek(toOffset: start)
        } catch {
            return nil
        }

        let data: Data
        do {
            guard let read = try handle.read(upToCount: Int(fileSize - start)) else { return nil }
            data = read
        } catch {
            return nil
        }

        var lines = splitLines(data)
        // start > 0 means byte 0 of this read is not byte 0 of the file —
        // the first "line" is a fragment of whatever preceded it, never a
        // real record. Drop it unconditionally, even if that leaves nothing.
        if start > 0, !lines.isEmpty {
            lines.removeFirst()
        }

        let decoded = lines.compactMap { String(data: $0, encoding: .utf8) }
        guard !decoded.isEmpty else { return "" }
        return decoded.joined(separator: "\n")
    }

    /// Split raw bytes on `\n` (0x0A). Safe against multi-byte UTF-8: 0x0A
    /// never occurs as a lead or continuation byte of a multi-byte
    /// character, so this can never cut one in half.
    private static func splitLines(_ data: Data) -> [Data] {
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
        if start < data.endIndex {
            parts.append(data[start..<data.endIndex])
        }
        return parts
    }
}
