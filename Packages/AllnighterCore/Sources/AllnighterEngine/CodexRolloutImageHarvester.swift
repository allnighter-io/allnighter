import Foundation

/// Harvests image outputs Codex records in its rollout JSONL instead of emitting
/// as answer text or writing to a file. Codex image tool calls store data URLs
/// under `response_item.payload.output[]` entries shaped like:
/// `{ "type": "input_image", "image_url": "data:image/png;base64,..." }`.
public struct CodexRolloutImageHarvester: Sendable {
    public var searchRoots: [URL]
    public var maxImages: Int

    public init(searchRoots: [URL]? = nil, maxImages: Int = WorkerOutputImageHarvest.maxImagesPerTurn) {
        self.searchRoots = searchRoots ?? Self.defaultSearchRoots()
        self.maxImages = maxImages
    }

    public func images(
        sessionId: String,
        after startedAt: Date? = nil,
        before finishedAt: Date? = nil
    ) -> [WorkerOutputImageHarvest.DataCandidate] {
        images(sessionId: sessionId, cwd: nil, after: startedAt, before: finishedAt)
    }

    /// Locate the rollout by captured session id if present, else by the run's working
    /// directory + time window (session ids are not reliably captured for Codex, and a warm
    /// session reuses one rollout across turns — the per-image timestamp window then selects
    /// this turn's image inside that file).
    public func images(
        sessionId: String?,
        cwd: String?,
        after startedAt: Date? = nil,
        before finishedAt: Date? = nil
    ) -> [WorkerOutputImageHarvest.DataCandidate] {
        let url = sessionId.flatMap { id in
            id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : rolloutURL(sessionId: id, near: finishedAt ?? startedAt)
        } ?? cwd.flatMap { rolloutURL(cwd: $0, after: startedAt, before: finishedAt) }
        guard let url else { return [] }
        return Self.images(inRollout: url, after: startedAt, before: finishedAt, maxImages: maxImages)
    }

    /// The most recent rollout whose `session_meta.cwd` matches `cwd` and whose session began
    /// no later than `finishedAt` (+margin). mtime-prefiltered so we only read first lines of
    /// plausibly-relevant files.
    public func rolloutURL(cwd: String, after startedAt: Date? = nil, before finishedAt: Date? = nil) -> URL? {
        let target = Self.normalizePath(cwd)
        guard !target.isEmpty else { return nil }
        let mtimeFloor = startedAt?.addingTimeInterval(-300)
        // This turn's session began at ~startedAt (cold = this turn; warm = an earlier turn,
        // so an even earlier start). A session that begins AFTER the turn started is a
        // different (possibly concurrent) run and must not shadow the right file.
        let startCeiling = (startedAt ?? finishedAt)?.addingTimeInterval(30)
        var best: (url: URL, start: Date)?
        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                if let mtimeFloor,
                   let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   mtime < mtimeFloor { continue }
                guard let meta = Self.sessionMeta(url: url), Self.normalizePath(meta.cwd) == target else { continue }
                if let startCeiling, meta.start > startCeiling { continue }
                if best == nil || meta.start > best!.start { best = (url, meta.start) }
            }
        }
        return best?.url
    }

    public func rolloutURL(sessionId: String, near date: Date? = nil) -> URL? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Fast path: Codex partitions live sessions by LOCAL date (sessions/YYYY/MM/DD) and the
        // rollout filename embeds that date. When we know roughly when the run happened, probe
        // that day's directory (± a day for tz/midnight) shallowly — bounds the hot path to one
        // small dir instead of a recursive walk over a months-deep session history every turn.
        if let date {
            for root in searchRoots {
                for offset in [0, -1, 1] {
                    let day = date.addingTimeInterval(TimeInterval(offset) * 86_400)
                    let dir = root.appendingPathComponent(Self.datePath(day), isDirectory: true)
                    if let match = firstJSONL(in: dir, nameContaining: trimmed) { return match }
                }
            }
        }
        // Fallback: full recursive walk (rare — odd partition, archived flat dir, far-past date).
        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl",
                      url.lastPathComponent.contains(trimmed) else { continue }
                return url
            }
        }
        return nil
    }

    private static func datePath(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func firstJSONL(in dir: URL, nameContaining needle: String) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return entries.first { $0.pathExtension.lowercased() == "jsonl" && $0.lastPathComponent.contains(needle) }
    }

    public static func images(
        inRollout url: URL,
        after startedAt: Date? = nil,
        before finishedAt: Date? = nil,
        maxImages: Int = WorkerOutputImageHarvest.maxImagesPerTurn
    ) -> [WorkerOutputImageHarvest.DataCandidate] {
        guard maxImages > 0,
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var images: [WorkerOutputImageHarvest.DataCandidate] = []
        var seenDataURLs = Set<String>()
        for line in contents.split(whereSeparator: \.isNewline) {
            guard images.count < maxImages,
                  let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "response_item",
                  timestamp(in: obj, isBetween: startedAt, and: finishedAt),
                  let payload = obj["payload"] as? [String: Any] else { continue }

            switch payload["type"] as? String {
            case "image_generation_call":
                // The built-in `image_gen` tool: the produced PNG is RAW base64 in `result`
                // (no `data:` prefix), the actual generation output. Dedupe by call id so a
                // generating→completed pair of snapshots yields one image.
                guard let result = payload["result"] as? String, !result.isEmpty else { continue }
                // Dedup by call id; if absent, by the FULL base64 (not a 64-char prefix — two
                // distinct same-dimension PNGs share the signature+IHDR header, so a prefix can
                // collide and silently drop the second image).
                let key = (payload["id"] as? String) ?? (payload["call_id"] as? String) ?? result
                guard seenDataURLs.insert(key).inserted,
                      let candidate = dataCandidate(fromBase64: result, index: images.count) else { continue }
                images.append(candidate)
            case "function_call_output":
                // `view_image` / attached-image results carry `data:image/...;base64,` URLs.
                if let output = payload["output"] {
                    collectImages(from: output, into: &images, seenDataURLs: &seenDataURLs, maxImages: maxImages)
                }
            default:
                continue
            }
        }
        return images
    }

    /// `session_meta` (first line) cwd + session start time — used to match a rollout to a run
    /// without a captured session id. Reads only the file head (the first line can be large
    /// because it embeds base instructions).
    private static func sessionMeta(url: URL) -> (cwd: String, start: Date)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 524_288),
              let text = String(data: head, encoding: .utf8),
              let firstLine = text.split(whereSeparator: \.isNewline).first,
              let data = String(firstLine).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              let cwd = payload["cwd"] as? String else { return nil }
        let raw = (payload["timestamp"] as? String) ?? (obj["timestamp"] as? String) ?? ""
        return (cwd, parseISODate(raw) ?? .distantPast)
    }

    private static func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var std = (trimmed as NSString).standardizingPath
        while std.count > 1, std.hasSuffix("/") { std.removeLast() }
        return std
    }

    private static func defaultSearchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
        ]
    }

    private static func timestamp(in obj: [String: Any], isBetween startedAt: Date?, and finishedAt: Date?) -> Bool {
        guard startedAt != nil || finishedAt != nil else { return true }
        guard let raw = obj["timestamp"] as? String, let date = parseISODate(raw) else { return false }
        if let startedAt, date < startedAt.addingTimeInterval(-2) { return false }
        if let finishedAt, date > finishedAt.addingTimeInterval(10) { return false }
        return true
    }

    private static func parseISODate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func collectImages(
        from value: Any,
        into images: inout [WorkerOutputImageHarvest.DataCandidate],
        seenDataURLs: inout Set<String>,
        maxImages: Int
    ) {
        guard images.count < maxImages else { return }
        if let dict = value as? [String: Any] {
            if (dict["type"] as? String) == "input_image",
               let rawURL = dict["image_url"] as? String,
               seenDataURLs.insert(rawURL).inserted,
               let candidate = dataCandidate(fromDataURL: rawURL, index: images.count) {
                images.append(candidate)
                return
            }
            for child in dict.values {
                collectImages(from: child, into: &images, seenDataURLs: &seenDataURLs, maxImages: maxImages)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectImages(from: child, into: &images, seenDataURLs: &seenDataURLs, maxImages: maxImages)
                if images.count >= maxImages { break }
            }
        } else if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") || trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) else { return }
            collectImages(from: parsed, into: &images, seenDataURLs: &seenDataURLs, maxImages: maxImages)
        }
    }

    private static func dataCandidate(fromDataURL rawURL: String, index: Int) -> WorkerOutputImageHarvest.DataCandidate? {
        guard rawURL.lowercased().hasPrefix("data:image/"),
              let comma = rawURL.firstIndex(of: ",") else { return nil }
        let metadata = String(rawURL[rawURL.index(rawURL.startIndex, offsetBy: "data:".count)..<comma])
        guard metadata.lowercased().contains(";base64") else { return nil }
        let mimeType = metadata.split(separator: ";").first.map(String.init) ?? "image/png"
        let payload = String(rawURL[rawURL.index(after: comma)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters), !data.isEmpty else {
            return nil
        }
        return WorkerOutputImageHarvest.DataCandidate(
            data: data,
            mimeType: mimeType,
            originalName: "codex-rollout-image-\(index + 1).\(fileExtension(for: mimeType))"
        )
    }

    /// Decode RAW base64 (no `data:` prefix) — the `image_generation_call.result` shape (always
    /// PNG from Codex). The declared MIME is advisory only: `ThreadAttachmentStore`'s ingestor
    /// re-sniffs the bytes and re-encodes, so we don't re-implement magic-byte detection here.
    private static func dataCandidate(fromBase64 raw: String, index: Int) -> WorkerOutputImageHarvest.DataCandidate? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters), !data.isEmpty
        else { return nil }
        return WorkerOutputImageHarvest.DataCandidate(
            data: data,
            mimeType: "image/png",
            originalName: "codex-rollout-image-\(index + 1).png"
        )
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "png"
        }
    }
}
