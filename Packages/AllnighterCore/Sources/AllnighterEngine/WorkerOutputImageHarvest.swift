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

    /// Resolved, validated local image files referenced anywhere in `texts`. Run-relative
    /// paths resolve under `runDirectory` (when given); absolute and `~/` paths resolve
    /// directly. Results are deduped by resolved path, in first-seen order, and capped.
    public static func candidateImageURLs(in texts: [String], runDirectory: URL?) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        func consider(_ path: String) {
            guard result.count < maxImagesPerTurn else { return }
            guard let url = validatedImageURL(forPath: path, runDirectory: runDirectory) else { return }
            if seen.insert(url.path).inserted { result.append(url) }
        }

        for text in texts {
            for token in imagePathTokens(in: text) { consider(token) }
            if result.count >= maxImagesPerTurn { break }
        }
        return result
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
