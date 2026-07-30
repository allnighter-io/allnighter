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

    /// Tier-3 seats with no on-disk capacity surface.
    public static let tier3DisklessSources: [String] = [
        "claude_code",
        "cursor_agent",
        "kimi",
        "agy",
    ]

    /// Tier-3 seats the PTY probe drives on `--refresh` (includes Claude Code).
    public static let tier3ProbeableSources: [String] = CapacityProbe.probeableSources

    /// Acquire capacity windows for the fixed bench under `homeRoot`.
    ///
    /// - Parameters:
    ///   - homeRoot: Home directory root (default: real home). Tests inject a temp tree.
    ///   - now: Wall clock for unknown stamps. Callers pass it — no wall-clock reads
    ///     for observation stamps inside tier-1 paths.
    ///   - refresh: When `true`, run tier-3 PTY probes (explicit refresh only).
    ///     When `false` (default), tier-3 seats are `neverSampled` and **no** probe
    ///     executor is invoked — bare `alln capacity` spawns nothing.
    ///   - probeExecutor: Injectable probe seam. `nil` + `refresh` uses the live PTY
    ///     executor. Tests inject a counter / fixture runner.
    ///   - probeTimeout: Per-probe wall-clock budget (default 20s).
    /// - Returns: Windows for every bench source. Never empty for a known source;
    ///   never throws. Tier-1 seats are always acquired; a failed probe never
    ///   degrades them.
    public static func windows(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date,
        refresh: Bool = false,
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout
    ) -> [CapacityWindow] {
        var result: [CapacityWindow] = []
        // Tier-1 first — always. Probe failures must not prevent these numbers.
        result.append(contentsOf: acquireCodex(homeRoot: homeRoot, now: now))
        result.append(contentsOf: acquireGrok(homeRoot: homeRoot, now: now))
        result.append(contentsOf: acquireTier3(
            now: now,
            refresh: refresh,
            probeExecutor: probeExecutor,
            probeTimeout: probeTimeout
        ))
        return result
    }

    // MARK: - Tier 3

    private static func acquireTier3(
        now: Date,
        refresh: Bool,
        probeExecutor: (any CapacityProbeExecuting)?,
        probeTimeout: TimeInterval
    ) -> [CapacityWindow] {
        if !refresh {
            // Bare path: never sample, never spawn. NOT `.vendorExposesNothing` —
            // that claims the vendor has no usage surface, which is false for every
            // seat in this list. agy, Kimi, Cursor, and Claude all print `/usage`,
            // and we ship tested parsers for each. Without an explicit `--refresh`
            // we simply have not looked.
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
        let probeable = Set(tier3ProbeableSources)

        // Run probeable seats concurrently — each has its own timeout, so one
        // slow CLI cannot block a sibling beyond its own budget.
        let lock = NSLock()
        var bySource: [String: [CapacityWindow]] = [:]
        let group = DispatchGroup()

        for source in tier3DisklessSources where probeable.contains(source) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let windows = executor.execute(
                    CapacityProbeRequest(source: source, now: now, timeout: probeTimeout)
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

        // Wait for every probe: each is internally bounded by probeTimeout, plus
        // a small reaping margin so terminate can finish.
        let margin = max(2.0, probeTimeout * 0.1)
        let groupTimeout = probeTimeout + margin
        _ = group.wait(timeout: .now() + groupTimeout)

        var result: [CapacityWindow] = []
        for source in tier3DisklessSources {
            if probeable.contains(source) {
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
                // Future deferred seats only — every current tier-3 seat is probeable.
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
        return result
    }

    // MARK: - Codex

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
