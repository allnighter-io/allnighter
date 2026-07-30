import Foundation

/// Tier-1 on-disk capacity acquisition.
///
/// Reads what is already on disk — no probes, no PTY, no process spawns.
/// Injectable `homeRoot` keeps tests off the real home directory.
///
/// Fail closed: missing directory, unreadable file, and empty file all return
/// `unknown` with a reason — never throw, never invent 0%.
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

    /// Tier-3 seats with no on-disk capacity surface for this ladder step.
    public static let tier3DisklessSources: [String] = [
        "claude_code",
        "cursor_agent",
        "kimi",
        "agy",
    ]

    /// Acquire capacity windows for the fixed bench under `homeRoot`.
    ///
    /// - Parameters:
    ///   - homeRoot: Home directory root (default: real home). Tests inject a temp tree.
    ///   - now: Wall clock for unknown stamps. Callers pass it — no `Date()` inside.
    /// - Returns: Windows for every bench source. Never empty for a known source;
    ///   never throws.
    public static func windows(
        homeRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        now: Date
    ) -> [CapacityWindow] {
        var result: [CapacityWindow] = []
        result.append(contentsOf: acquireCodex(homeRoot: homeRoot, now: now))
        result.append(contentsOf: acquireGrok(homeRoot: homeRoot, now: now))
        for source in tier3DisklessSources {
            result.append(
                CapacityWindow.unknown(
                    reason: .vendorExposesNothing,
                    source: source,
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                )
            )
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
