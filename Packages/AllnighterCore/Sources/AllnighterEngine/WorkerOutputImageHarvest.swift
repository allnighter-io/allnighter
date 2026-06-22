import Foundation
import AllnighterCore

/// Captures images a worker produced — referenced by path in its settled output — into a
/// thread's canonical attachment store, so the timeline can show a real preview from
/// canonical bytes. The chip's open action then hands the canonical file to the OS
/// (Preview) for full size.
///
/// This is run-time capture (at settlement), NOT render-time scraping: the bytes are
/// copied once into the thread's attachment store and the UI renders that canonical copy
/// — never the vendor path, never a fabricated thumbnail. Only existing, validated
/// PNG/JPEG files are taken; a path with no real image behind it is ignored.
public enum WorkerOutputImageHarvest {
    /// Cap on how many produced images one turn captures — guards against pathological
    /// output that lists many paths.
    public static let maxImagesPerTurn = 8

    /// A path token in the worker's prose that resolved to a real, validated image.
    /// `token` is the raw substring as it appeared (used to strip it from the caption);
    /// `url` is the validated file on disk.
    public struct Candidate: Sendable, Equatable {
        public var token: String
        public var url: URL
        public init(token: String, url: URL) {
            self.token = token
            self.url = url
        }
    }

    /// Path tokens in `texts` that resolve to real, validated images. Run-relative paths
    /// resolve under `runDirectory` (when given); absolute and `~/` paths resolve directly.
    /// Deduped by resolved path, first-seen order, capped at `maxImagesPerTurn`.
    public static func candidates(in texts: [String], runDirectory: URL?) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for text in texts {
            for token in imagePathTokens(in: text) {
                guard result.count < maxImagesPerTurn else { return result }
                guard let url = validatedImageURL(forPath: token, runDirectory: runDirectory) else { continue }
                if seen.insert(url.path).inserted { result.append(Candidate(token: token, url: url)) }
            }
        }
        return result
    }

    /// Resolved, validated local image files referenced anywhere in `texts`.
    public static func candidateImageURLs(in texts: [String], runDirectory: URL?) -> [URL] {
        candidates(in: texts, runDirectory: runDirectory).map(\.url)
    }

    /// The caption with captured image-path tokens removed: a path we've already turned into
    /// a preview chip is redundant noise (and vendor paths are ugly). Drops the token, then
    /// drops a line that is now just a dangling label ("Updated image saved:") and collapses
    /// the blank lines that leaves. Returns the original text unchanged when `tokens` is empty.
    public static func cleanedCaption(from text: String, removing tokens: [String]) -> String {
        guard !tokens.isEmpty else { return text }
        var stripped = text
        for token in tokens { stripped = stripped.replacingOccurrences(of: token, with: "") }

        let lines = stripped.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // A line that, after the path is gone, is only a short trailing-colon label is the
        // "Updated image saved:" / "The file is saved here:" lead-in — drop it.
        let kept = lines.filter { line in
            !(line.hasSuffix(":") && line.count <= 48)
        }
        var collapsed: [String] = []
        for line in kept {
            if line.isEmpty, collapsed.last?.isEmpty ?? true { continue }
            collapsed.append(line)
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ingest each image as a `.workerGenerated` attachment and return the refs (sequenced
    /// from `startSequence`). Each commit is independent — one failure does not abort the rest.
    public static func commit(
        imageURLs: [URL],
        threadId: String,
        store: ThreadAttachmentStore,
        startSequence: Int,
        idFactory: () -> String,
        now: Date
    ) -> [TurnAttachmentRef] {
        guard !imageURLs.isEmpty else { return [] }
        let flock = try? ThreadFlockLock.acquire(lockURL: store.lockURL)
        defer { _ = flock }

        var refs: [TurnAttachmentRef] = []
        var sequence = startSequence
        for url in imageURLs {
            do {
                let ingested = try store.ingestor.ingest(
                    fileURL: url, sourceKind: .workerGenerated, originalName: url.lastPathComponent
                )
                let (_, ref) = try store.commitIngested(
                    ingested: ingested,
                    attachmentId: idFactory(),
                    threadId: threadId,
                    sourceKind: .workerGenerated,
                    sequence: sequence,
                    originalName: url.lastPathComponent,
                    now: now
                )
                refs.append(ref)
                sequence += 1
            } catch {
                continue
            }
        }
        return refs
    }

    // MARK: - Path extraction

    /// Path-like tokens ending in an image extension. Matches absolute / `~/` paths and
    /// run-relative paths/filenames; the caller validates each against the filesystem.
    static func imagePathTokens(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        // A path token is a run of non-whitespace, non-quote, non-bracket characters that
        // ends in a known image extension. Trailing sentence punctuation is trimmed by the
        // validator step (the URL either exists or it doesn't).
        let pattern = "[^\\s\"'`<>()\\[\\]{}|,]+\\.(?:png|jpe?g|webp)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func validatedImageURL(forPath rawPath: String, runDirectory: URL?) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, RunImagePathResolver.isImagePath(trimmed) else { return nil }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            return WorkerImageCapture.isValidImage(at: url) ? url : nil
        }
        // Run-relative — only honoured under a known run directory, with the resolver's
        // escape checks (no `..`, no absolute, must stay under the run root).
        guard let runDirectory,
              let abs = RunImagePathResolver.absolutePath(runDirectory: runDirectory, relativePath: trimmed)
        else { return nil }
        let url = URL(fileURLWithPath: abs)
        return WorkerImageCapture.isValidImage(at: url) ? url : nil
    }
}
