import Foundation

/// Capacity acquisition boundary — **one canonical adapter per bench source**.
///
/// | Source | Sole mechanism |
/// | --- | --- |
/// | `codex`, `grok` | Structured disk/log (never PTY) |
/// | `claude_code`, `cursor_agent`, `kimi`, `agy` | One PTY probe adapter (refresh only) |
///
/// **Bare call** (`refresh: false`, the default) — disk adapters + neverSampled
/// for PTY seats. No probes, no process spawns. Instant.
///
/// **Refresh** (`refresh: true` / `alln capacity --refresh`) — re-read disk
/// sources and run the single PTY adapter per selected PTY seat. Never idle-
/// backgrounded; only explicit refresh starts probes.
///
/// **Targeted refresh** (`refreshSource:`) — re-reads disk for every disk seat,
/// probes only the named PTY seat (disk seats with `--source` are disk-only,
/// no spawn). Unprobed PTY siblings are `neverSampled`. Full six-row strip
/// always.
///
/// There is no parallel fallback that can silently disagree with the canonical
/// adapter (no disk+PTY dual path for the same source).
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

    /// Sources whose sole acquisition path is structured disk/log truth.
    public static let diskOnlySources: [String] = [
        "codex",
        "grok",
    ]

    /// Sources whose sole acquisition path is one isolated PTY probe adapter.
    public static let ptyOnlySources: [String] = [
        "claude_code",
        "cursor_agent",
        "kimi",
        "agy",
    ]

    /// Full bench roster (disk + PTY). Prefer `benchSourceOrder` for display order.
    public static let tier3DisklessSources: [String] = benchSourceOrder

    /// PTY seats driven on `--refresh`. Disk-only seats are never in this set.
    public static let tier3ProbeableSources: [String] = ptyOnlySources

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

    /// PTY sources that will be attempted on this refresh (empty when `refresh` is false).
    public static func sourcesProbed(
        refresh: Bool,
        refreshSource: String? = nil
    ) -> [String] {
        guard refresh else { return [] }
        let probeable = Set(ptyOnlySources)
        if let refreshSource {
            return probeable.contains(refreshSource) ? [refreshSource] : []
        }
        return ptyOnlySources
    }

    /// Acquire capacity windows for the fixed bench under `homeRoot`.
    ///
    /// - Parameters:
    ///   - homeRoot: Home directory root (default: real home). Tests inject a temp tree.
    ///   - now: Wall clock for unknown stamps. Callers pass it — no wall-clock reads
    ///     for observation stamps inside tier-1 paths.
    ///   - refresh: When `true`, run PTY adapters (explicit refresh only).
    ///     When `false` (default), PTY seats are `neverSampled` and **no** probe
    ///     executor is invoked — bare `alln capacity` spawns nothing.
    ///   - refreshSource: When non-nil with `refresh`, probe only this PTY seat
    ///     when applicable. Disk-only ids re-read disk and do not spawn.
    ///     Ignored when `refresh` is false (caller must reject that combination).
    ///   - probeExecutor: Injectable probe seam. `nil` + `refresh` uses the live PTY
    ///     executor. Tests inject a counter / fixture runner.
    ///   - probeTimeout: Per-probe wall-clock budget (default 20s).
    /// - Returns: Windows for every bench source. Never empty for a known source;
    ///   never throws. Disk seats are always acquired; a failed PTY probe never
    ///   degrades them. The strip always covers the full bench — never one row only.
    public static func windows(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date,
        refresh: Bool = false,
        refreshSource: String? = nil,
        probeExecutor: (any CapacityProbeExecuting)? = nil,
        probeTimeout: TimeInterval = CapacityProbe.defaultTimeout
    ) -> [CapacityWindow] {
        // Always run disk adapters first — sole path for codex/grok, refresh or bare.
        var bySource: [String: [CapacityWindow]] = [
            "codex": acquireCodex(homeRoot: homeRoot, now: now),
            "grok": acquireGrok(homeRoot: homeRoot, now: now),
        ]

        let sourcesToProbe = Set(sourcesProbed(refresh: refresh, refreshSource: refreshSource))

        if sourcesToProbe.isEmpty {
            for source in ptyOnlySources {
                bySource[source] = [
                    CapacityWindow.unknown(
                        reason: .neverSampled,
                        source: source,
                        scope: .weekly,
                        observedAt: now,
                        sourceTier: .tuiProbe
                    ),
                ]
            }
            return orderedBenchWindows(bySource, now: now)
        }

        let executor = probeExecutor ?? LiveCapacityProbeExecutor()
        let group = DispatchGroup()
        // Box concurrent probe results so we do not mutate a captured Dictionary.
        final class ProbeResults: @unchecked Sendable {
            private let lock = NSLock()
            private var map: [String: [CapacityWindow]] = [:]
            func set(_ source: String, _ windows: [CapacityWindow]) {
                lock.lock(); map[source] = windows; lock.unlock()
            }
            func snapshot() -> [String: [CapacityWindow]] {
                lock.lock(); defer { lock.unlock() }
                return map
            }
        }
        let probeResults = ProbeResults()

        let effectiveTimeouts = sourcesToProbe.map { source -> TimeInterval in
            if probeTimeout == CapacityProbe.defaultTimeout {
                return CapacityProbe.timeout(for: source)
            }
            return probeTimeout
        }
        let maxProbeTimeout = effectiveTimeouts.max() ?? probeTimeout

        for source in ptyOnlySources where sourcesToProbe.contains(source) {
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
                probeResults.set(source, safe)
            }
        }

        // Each probe is internally bounded; wait with reaping margin, then force-kill
        // any still-tracked vendor children so a hung seat cannot outlive the strip.
        let margin = max(2.0, maxProbeTimeout * 0.1)
        let groupTimeout = maxProbeTimeout + margin
        let waitResult = group.wait(timeout: .now() + groupTimeout)
        if waitResult == .timedOut {
            CapacityProbe.terminateAllActiveProbes()
            // Brief reaping window after killpg.
            _ = group.wait(timeout: .now() + 1.0)
        }

        let probed = probeResults.snapshot()
        for source in ptyOnlySources {
            if sourcesToProbe.contains(source) {
                if let windows = probed[source] {
                    bySource[source] = windows
                } else {
                    bySource[source] = [
                        CapacityProbe.unknown(
                            source: source,
                            reason: .probeTimeout(observedAt: now),
                            now: now
                        ),
                    ]
                }
            } else {
                bySource[source] = [
                    CapacityWindow.unknown(
                        reason: .neverSampled,
                        source: source,
                        scope: .weekly,
                        observedAt: now,
                        sourceTier: .tuiProbe
                    ),
                ]
            }
        }
        return orderedBenchWindows(bySource, now: now)
    }

    private static func orderedBenchWindows(
        _ bySource: [String: [CapacityWindow]],
        now: Date
    ) -> [CapacityWindow] {
        var result: [CapacityWindow] = []
        for source in benchSourceOrder {
            if let windows = bySource[source], !windows.isEmpty {
                result.append(contentsOf: windows)
            } else {
                let tier: CapacityAcquisitionTier =
                    diskOnlySources.contains(source) ? .onDisk : .tuiProbe
                result.append(
                    CapacityWindow.unknown(
                        reason: .neverSampled,
                        source: source,
                        scope: .weekly,
                        observedAt: now,
                        sourceTier: tier
                    )
                )
            }
        }
        return result
    }

    // MARK: - Codex

    /// Canonical codex adapter: newest `rollout-*.jsonl` under `~/.codex/sessions/`.
    /// Sole acquisition path — never PTY.

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

    /// Canonical grok adapter: `~/.grok/logs/unified.jsonl` reverse-scan.
    /// Sole acquisition path — never PTY.
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
