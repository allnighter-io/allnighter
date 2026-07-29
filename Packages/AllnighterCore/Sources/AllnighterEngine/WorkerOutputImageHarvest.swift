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

    /// Cap on how many referenced markdown artifacts one turn follows for embedded images
    /// (AGY/antigravity wraps a produced image in a `.md` artifact and links only the `.md`).
    static let maxArtifactsToFollow = 4
    /// Don't slurp a huge file when following an artifact for embedded image links.
    static let maxArtifactBytes = 512 * 1024

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

    /// An image already present as bytes instead of a filesystem path (Codex rollout
    /// image tool output is the motivating case).
    public struct DataCandidate: Sendable, Equatable {
        public var data: Data
        public var mimeType: String
        public var originalName: String

        public init(data: Data, mimeType: String, originalName: String) {
            self.data = data
            self.mimeType = mimeType
            self.originalName = originalName
        }
    }

    /// Images produced by Codex and stored only in the session rollout log for this
    /// run's answer window. Bounded by each answer's timestamps so resumed sessions do
    /// not re-harvest images from earlier turns.
    public static func codexRolloutDataCandidates(
        run: TeamRun,
        models: [Model],
        repoRoot: String? = nil,
        harvester: CodexRolloutImageHarvester = CodexRolloutImageHarvester()
    ) -> [DataCandidate] {
        let modelById = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cwd = (repoRoot?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        var results: [DataCandidate] = []
        for answer in run.answers {
            guard results.count < maxImagesPerTurn,
                  let model = modelById[answer.modelId],
                  model.driverId == "codex" else { continue }
            let sessionId = answer.result.capturedSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Locate the rollout by captured session id when present, else by the run's
            // working directory + time window (session ids aren't reliably captured for Codex).
            guard (sessionId?.isEmpty == false) || cwd != nil else { continue }
            let remaining = maxImagesPerTurn - results.count
            let images = harvester.images(
                sessionId: sessionId,
                cwd: cwd,
                after: answer.result.timing.startedAt,
                before: answer.result.timing.finishedAt
            )
            results.append(contentsOf: images.prefix(remaining))
        }
        return results
    }

    /// Path tokens in `texts` that resolve to real, validated images. Run-relative paths
    /// resolve under `runDirectory` (when given); absolute and `~/` paths resolve directly.
    /// Deduped by resolved path, first-seen order, capped at `maxImagesPerTurn`.
    public static func candidates(in texts: [String], runDirectory: URL?) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []

        func consider(token: String, url: URL, captionToken: String) {
            guard result.count < maxImagesPerTurn else { return }
            if seen.insert(url.path).inserted { result.append(Candidate(token: captionToken, url: url)) }
        }

        for text in texts {
            // 1. Images named directly in the prose (Grok: "The path is given: …/1.jpg").
            for token in imagePathTokens(in: text) {
                guard result.count < maxImagesPerTurn else { return result }
                if let url = validatedImageURL(forPath: token, runDirectory: runDirectory) {
                    consider(token: token, url: url, captionToken: token)
                }
            }
            // 2. Images embedded inside a referenced markdown artifact (AGY: the answer links
            //    a `.md`, and the real image is `![alt](…jpg)` inside it). Follow the artifact,
            //    resolve its inner image links relative to the artifact's own directory.
            var followed = 0
            for token in artifactPathTokens(in: text) {
                guard result.count < maxImagesPerTurn, followed < maxArtifactsToFollow else { break }
                guard let artifactURL = validatedArtifactURL(forPath: token, runDirectory: runDirectory),
                      let contents = readArtifact(artifactURL) else { continue }
                followed += 1
                let artifactDir = artifactURL.deletingLastPathComponent()
                for inner in imagePathTokens(in: contents) {
                    guard result.count < maxImagesPerTurn else { break }
                    if let url = validatedImageURL(forPath: inner, runDirectory: artifactDir) {
                        // Leave the caption untouched: the artifact link (e.g. the `.md`) is a
                        // real, openable artifact worth keeping; the image just appears below it.
                        // The inner path never appeared in the prose, so nothing is stripped.
                        consider(token: inner, url: url, captionToken: inner)
                    }
                }
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

    /// Ingest already-decoded image candidates as `.workerGenerated` attachments.
    /// Each image is validated/normalized through the same ingestor as file-based
    /// images; one bad payload does not abort the rest.
    public static func commit(
        dataCandidates: [DataCandidate],
        threadId: String,
        store: ThreadAttachmentStore,
        startSequence: Int,
        idFactory: () -> String,
        now: Date
    ) -> [TurnAttachmentRef] {
        guard !dataCandidates.isEmpty else { return [] }
        let flock = try? ThreadFlockLock.acquire(lockURL: store.lockURL)
        defer { _ = flock }

        var refs: [TurnAttachmentRef] = []
        var sequence = startSequence
        for candidate in dataCandidates.prefix(maxImagesPerTurn) {
            do {
                let ingested = try store.ingestor.ingest(
                    data: candidate.data,
                    declaredMIME: candidate.mimeType,
                    sourceKind: .workerGenerated,
                    originalName: candidate.originalName
                )
                let (_, ref) = try store.commitIngested(
                    ingested: ingested,
                    attachmentId: idFactory(),
                    threadId: threadId,
                    sourceKind: .workerGenerated,
                    sequence: sequence,
                    originalName: candidate.originalName,
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

    /// Path-like tokens ending in a markdown extension — a user-facing artifact some agents
    /// (AGY/antigravity) produce instead of naming the image directly. The caller reads each
    /// and scans its contents for embedded image links.
    static func artifactPathTokens(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let pattern = "[^\\s\"'`<>()\\[\\]{}|,]+\\.(?:md|markdown)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func validatedImageURL(forPath rawPath: String, runDirectory: URL?) -> URL? {
        guard let url = resolvedFileURL(forPath: rawPath, runDirectory: runDirectory),
              RunImagePathResolver.isImagePath(url.path) else { return nil }
        return WorkerImageCapture.isValidImage(at: url) ? url : nil
    }

    private static func validatedArtifactURL(forPath rawPath: String, runDirectory: URL?) -> URL? {
        guard let url = resolvedFileURL(forPath: rawPath, runDirectory: runDirectory) else { return nil }
        let ext = url.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return url
    }

    /// Resolve a raw token (which may be a `file://` URL, a `~/`/absolute path, or a path
    /// relative to `runDirectory`) to a filesystem URL — without checking the file type.
    /// Absolute/`file://`/`~` paths resolve directly; relative paths use the resolver's escape
    /// checks (no `..`, must stay under the run root). Returns nil for paths that don't exist.
    private static func resolvedFileURL(forPath rawPath: String, runDirectory: URL?) -> URL? {
        let token = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let path = filesystemPath(from: token)

        if path.hasPrefix("/") || path.hasPrefix("~") {
            let expanded = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        guard let runDirectory,
              let abs = RunImagePathResolver.absolutePath(runDirectory: runDirectory, relativePath: path)
        else { return nil }
        return URL(fileURLWithPath: abs)
    }

    /// Turn a `file://` URL into a filesystem path (percent-decoded, scheme dropped). A plain
    /// path is returned unchanged — so a literal `%2F` in a non-URL vendor path (Grok session
    /// dirs) is preserved, never accidentally decoded.
    private static func filesystemPath(from token: String) -> String {
        guard token.lowercased().hasPrefix("file://") else { return token }
        if let url = URL(string: token), url.isFileURL { return url.path }
        let dropped = String(token.dropFirst("file://".count))
        return dropped.removingPercentEncoding ?? dropped
    }

    private static func readArtifact(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= maxArtifactBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
