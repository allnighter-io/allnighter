import Foundation

/// Capacity acquisition boundary: tier-1 on-disk reads + optional tier-3 PTY probes.
///
/// **Bare call** (`refresh: false`, the default) reads what is already on disk —
/// no probes, no PTY, no process spawns. Instant.
///
/// **Refresh** (`refresh: true` / `alln capacity --refresh`) additionally runs a
/// per-driver PTY probe for seats we can drive (agy, kimi, cursor, Claude Code).
/// Probes are never idle-backgrounded; only explicit refresh starts them.
///
/// **Targeted refresh** (`refresh: true` + `refreshSource:`) probes only that
/// seat when it is tier-3 probeable. Tier-1 ids are allowed and cheap (disk
/// only — no spawn). Every other seat still appears: tier-1 from disk, unprobed
/// tier-3 as `neverSampled`. The strip is never truncated to one row.
///
/// Injectable `homeRoot` / `probeExecutor` keep tests off the real home and off
/// real vendor CLIs.
///
/// Fail closed: missing directory, unreadable file, spawn failure, timeout,
/// empty capture, and parse failure all return `unknown` with a reason — never
/// throw, never invent 0%.
public enum CapacityAcquisition {

    /// Fixed product display order (source ids). Not-ready/parked seats are
    /// reordered by the strip renderer, not here.
    public static let benchSourceOrder: [String] = [
        "codex",
        "claude_code",
        "cursor_agent",
        "grok",
        "kimi",
        "agy",
    ]

    /// Tier-3 seats with a PTY probe path.
    /// Codex and Grok have disk-read fallbacks when the probe fails;
    /// the others have no disk surface and show `neverSampled` on failure.
    public static let tier3DisklessSources: [String] = [
        "claude_code",
        "cursor_agent",
        "kimi",
        "agy",
        "codex",
        "grok",
    ]

    /// Tier-3 seats the PTY probe drives on `--refresh` (includes Claude Code).
    public static let tier3ProbeableSources: [String] = CapacityProbe.probeableSources

    /// Valid bench source ids for `alln capacity --refresh --source <id>`.
    /// Same set as `benchSourceOrder` — the product bench, not only probeable seats.
    public static var validRefreshSourceIds: [String] { benchSourceOrder }

    /// CLI_USAGE_ERROR message when `--source` is unknown / misspelled.
    public static func unknownRefreshSourceMessage(_ id: String) -> String {
        let valid = validRefreshSourceIds.joined(separator: ", ")
        return "unknown source: \(id) (valid: \(valid))"
    }

    /// `nil` when `id` is a known bench source; otherwise the usage error message.
    public static func validateRefreshSourceId(_ id: String) -> String? {
        guard validRefreshSourceIds.contains(id) else {
            return unknownRefreshSourceMessage(id)
        }
        return nil
    }

    /// Acquire capacity windows for the fixed bench under `homeRoot`.
    ///
    /// - Parameters:
    ///   - homeRoot: Home directory root (default: real home). Tests inject a temp tree.
    ///   - now: Wall clock for unknown stamps. Callers pass it — no wall-clock reads
    ///     for observation stamps inside tier-1 paths.
    ///   - refresh: When `true`, run tier-3 PTY probes (explicit refresh only).
    ///     When `false` (default), tier-3 seats are `neverSampled` and **no** probe
    ///     executor is invoked — bare `alln capacity` spawns nothing.
    ///   - refreshSource: When non-nil with `refresh`, probe only this bench source
    ///     if it is tier-3 probeable. Tier-1 ids are accepted and do not spawn.
    ///     Ignored when `refresh` is false (caller must reject that combination).
    ///   - probeExecutor: Injectable probe seam. `nil` + `refresh` uses the live PTY
    ///     executor. Tests inject a counter / fixture runner.
    ///   - probeTimeout: Per-probe wall-clock budget (default 20s).
    /// - Returns: Windows for every bench source. Never empty for a known source;
    ///   never throws. Tier-1 seats are always acquired; a failed probe never
    ///   degrades them. The strip always covers the full bench — never one row only.
    public static func windows(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date,
        refresh: Bool = false,
        refreshSource: String? = nil,
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout
    ) -> [CapacityWindow] {
        var result: [CapacityWindow] = []
        // Tier-3 covers all bench sources now, including codex and grok.
        // Codex and Grok fall back to disk reads when their probe fails.
        result.append(contentsOf: acquireTier3(
            homeRoot: homeRoot,
            now: now,
            refresh: refresh,
            refreshSource: refreshSource,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout
        ))
        return result
    }

    // MARK: - Tier 3

    private static func acquireTier3(
        homeRoot: URL,
        now: Date,
        refresh: Bool,
        refreshSource: String?,
        probeExecutor: (any CapacityProbeExecuting)?,
        probeTimeout: TimeInterval
    ) -> [CapacityWindow] {
        if !refresh {
            // Bare/cached path: return disk reads for codex and grok, neverSampled for others.
            return tier3DisklessSources.map { source -> [CapacityWindow] in
                switch source {
                case "codex": return acquireCodexDisk(homeRoot: homeRoot, now: now)
                case "grok":  return acquireGrokDisk(homeRoot: homeRoot, now: now)
                default:
                    return [CapacityWindow.unknown(
                        reason: .neverSampled,
                        source: source,
                        scope: .weekly,
                        observedAt: now,
                        sourceTier: .tuiProbe
                    )]
                }
            }.flatMap { $0 }
        }

        let probeable = Set(tier3ProbeableSources)
        // Targeted refresh: only the named seat if probeable. Full refresh: all.
        // Tier-1 / non-probeable --source → empty probe set (disk path already ran).
        let sourcesToProbe: Set<String>
        if let refreshSource {
            if probeable.contains(refreshSource) {
                sourcesToProbe = [refreshSource]
            } else {
                sourcesToProbe = []
            }
        } else {
            sourcesToProbe = probeable
        }

        // No seats to probe (targeted tier-1, or empty filter) — neverSampled for
        // every tier-3 row. Still return a complete strip.
        if sourcesToProbe.isEmpty {
            return tier3DisklessSources.map { source in
                CapacityWindow.unknown(
                    reason: .neverSampled,
                    source: source,
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                )
            }
        }

        let executor = probeExecutor ?? LiveCapacityProbeExecutor()

        // Run selected seats concurrently — each has its own timeout, so one
        // slow CLI cannot block a sibling beyond its own budget.
        let lock = NSLock()
        var bySource: [String: [CapacityWindow]] = [:]
        let group = DispatchGroup()

        // Group wait must cover the slowest seat (Claude 35s) when using defaults.
        let effectiveTimeouts = sourcesToProbe.map { source -> TimeInterval in
            if probeTimeout == CapacityProbe.defaultTimeout {
                return CapacityProbe.timeout(for: source)
            }
            return probeTimeout
        }
        let maxProbeTimeout = effectiveTimeouts.max() ?? probeTimeout

        for source in tier3DisklessSources where sourcesToProbe.contains(source) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let seatTimeout = probeTimeout == CapacityProbe.defaultTimeout
                    ? CapacityProbe.timeout(for: source)
                    : probeTimeout
                let windows = executor.execute(
                    CapacityProbeRequest(source: source, now: now, timeout: seatTimeout)
                )
                let safe: [CapacityWindow]
                if windows.isEmpty {
                    // Executor contract is "at least one"; belt-and-suspenders.
                    safe = [
                        CapacityProbe.unknown(
                            source: source,
                            reason: .parserFailed(observedAt: now),
                            now: now
                        ),
                    ]
                } else {
                    // Never allow vendorExposesNothing for a seat we ship a parser for.
                    safe = windows.map { window in
                        if window.unknownReason == .vendorExposesNothing {
                            return CapacityProbe.unknown(
                                source: source,
                                reason: .parserFailed(observedAt: now),
                                now: now
                            )
                        }
                        return window
                    }
                }
                lock.lock()
                bySource[source] = safe
                lock.unlock()
            }
        }

        // Wait for every probe: each is internally bounded by its seat timeout,
        // plus a small reaping margin so terminate can finish.
        let margin = max(2.0, maxProbeTimeout * 0.1)
        let groupTimeout = maxProbeTimeout + margin
        _ = group.wait(timeout: .now() + groupTimeout)

        var result: [CapacityWindow] = []
        for source in tier3DisklessSources {
            if sourcesToProbe.contains(source) {
                if let windows = bySource[source] {
                    result.append(contentsOf: windows)
                } else {
                    // Group timed out before this seat reported — fail closed.
                    result.append(
                        CapacityProbe.unknown(
                            source: source,
                            reason: .parserFailed(observedAt: now),
                            now: now
                        )
                    )
                }
            } else {
                // Not selected for this refresh (targeted other seat, or deferred).
                // Codex and grok fall back to their disk reads; others: neverSampled.
                switch source {
                case "codex": result.append(contentsOf: acquireCodexDisk(homeRoot: homeRoot, now: now))
                case "grok":  result.append(contentsOf: acquireGrokDisk(homeRoot: homeRoot, now: now))
                default:
                    result.append(
                        CapacityWindow.unknown(
                            reason: .neverSampled,
                            source: source,
                            scope: .weekly,
                            observedAt: now,
                            sourceTier: .tuiProbe
                        )
                    )
                }
            }
        }
        return result
    }

    // MARK: - Codex

    /// Disk fallback: newest `rollout-*.jsonl` under `~/.codex/sessions/`.
    /// Called when the PTY probe is skipped (cached path) or fails.
    private static func acquireCodexDisk(homeRoot: URL, now: Date) -> [CapacityWindow] {
        acquireCodex(homeRoot: homeRoot, now: now)
    }

    /// `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*.jsonl` — newest file first;
    /// stop at the first file that yields a usable rate-limit record.
    private static func acquireCodex(homeRoot: URL, now: Date) -> [CapacityWindow] {
        let sessionsRoot = homeRoot
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return [unknownCodex(reason: .neverSampled, now: now)]
        }

        let files = rolloutFilesNewestFirst(under: sessionsRoot)
        guard !files.isEmpty else {
            return [unknownCodex(reason: .neverSampled, now: now)]
        }

        for fileURL in files {
            guard let content = readUTF8File(fileURL) else { continue }
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            let windows = CodexCapacityLog.capacityWindows(fromLogContent: content)
            if !windows.isEmpty {
                return windows
            }
        }

        // Files existed but none produced a usable token_count rate_limits record.
        return [unknownCodex(reason: .parserFailed(observedAt: now), now: now)]
    }

    private static func unknownCodex(reason: CapacityUnknownReason, now: Date) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: reason,
            source: "codex",
            scope: .weekly,
            observedAt: now,
            sourceTier: .onDisk
        )
    }

    /// Newest-first by mtime, then path (rollout filenames embed wall clock).
    private static func rolloutFilesNewestFirst(under sessionsRoot: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var scored: [(url: URL, mtime: Date, path: String)] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let mtime = values?.contentModificationDate ?? .distantPast
            scored.append((fileURL, mtime, fileURL.path))
        }

        scored.sort { a, b in
            if a.mtime != b.mtime { return a.mtime > b.mtime }
            return a.path > b.path
        }
        return scored.map(\.url)
    }

    // MARK: - Grok

    /// Disk fallback: `~/.grok/logs/unified.jsonl` reverse-scan.
    /// Called when the PTY probe is skipped (cached path) or fails.
    private static func acquireGrokDisk(homeRoot: URL, now: Date) -> [CapacityWindow] {
        acquireGrok(homeRoot: homeRoot, now: now)
    }

    /// `~/.grok/logs/unified.jsonl` — one large file. Read backwards from EOF
    /// and stop at the first billing weekly match (newest record).
    private static func acquireGrok(homeRoot: URL, now: Date) -> [CapacityWindow] {
        let logURL = homeRoot
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("unified.jsonl", isDirectory: false)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: logURL.path, isDirectory: &isDir),
              !isDir.boolValue
        else {
            return [unknownGrok(reason: .neverSampled, now: now)]
        }

        guard let match = latestGrokWindowReadingBackwards(from: logURL) else {
            // File present but empty / no billing line / unreadable.
            return [unknownGrok(reason: .parserFailed(observedAt: now), now: now)]
        }
        return [match.asCapacityWindow()]
    }

    private static func unknownGrok(reason: CapacityUnknownReason, now: Date) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: reason,
            source: "grok",
            scope: .weekly,
            observedAt: now,
            sourceTier: .onDisk
        )
    }

    /// Reverse-scan `unified.jsonl` for the newest billing weekly record.
    ///
    /// Reads fixed-size chunks from EOF, reconstructs complete lines newest-first,
    /// and stops on the first line `GrokCapacityLog` accepts. Avoids a full-file
    /// scan (~5 MB / ~271 ms) when the newest billing line sits near the end.
    static func latestGrokWindowReadingBackwards(
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

            // Prepend this chunk; keep a carry of a partial first line.
            var block = data
            block.append(carry)

            // Split into lines. The first segment may be incomplete when start > 0.
            let parts = splitLinesKeepingEmpties(block)
            let complete: ArraySlice<Data>
            if start > 0 {
                // First part is a line prefix continued from earlier-in-file bytes.
                carry = parts.first ?? Data()
                complete = parts.dropFirst()
            } else {
                carry = Data()
                complete = parts[...]
            }

            // Newest lines are at the end of this chunk's complete lines.
            for lineData in complete.reversed() {
                guard !lineData.isEmpty,
                      let line = String(data: lineData, encoding: .utf8)
                else { continue }
                if let window = GrokCapacityLog.latestWeeklyWindow(fromLogContent: line) {
                    return window
                }
            }
        }

        // Final carry is the file's first (oldest) line fragment/full line.
        if !carry.isEmpty, let line = String(data: carry, encoding: .utf8) {
            return GrokCapacityLog.latestWeeklyWindow(fromLogContent: line)
        }
        return nil
    }

    /// Split on `\n`; drop a trailing empty segment produced by a final newline.
    private static func splitLinesKeepingEmpties(_ data: Data) -> [Data] {
        var parts: [Data] = []
        var start = data.startIndex
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == 0x0A { // \n
                parts.append(data[start..<i])
                i = data.index(after: i)
                start = i
            } else {
                i = data.index(after: i)
            }
        }
        parts.append(data[start..<data.endIndex])
        // A file ending in \n yields a trailing empty part — drop it so it is not
        // treated as a real line, while preserving intentional blank mid-file lines.
        if parts.last?.isEmpty == true {
            parts.removeLast()
        }
        return parts
    }

    // MARK: - IO helpers

    private static func readUTF8File(_ url: URL) -> String? {
        // Unreadable → nil (caller maps to unknown). Never throw.
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
