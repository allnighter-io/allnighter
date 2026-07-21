import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum FileReferenceError: Error, Sendable, Equatable, CustomStringConvertible {
    case projectRootMissing
    case outsideProject(String)
    case notFound(String)
    case unreadable(String)
    case binaryUnsupported(String)
    case tooLarge(String, Int)
    case tooMany(Int)
    case sensitiveBlocked(String)
    case invalidLineRange(String)

    public var code: String {
        switch self {
        case .projectRootMissing: return "FILE_REFERENCE_PROJECT_ROOT_MISSING"
        case .outsideProject: return "FILE_REFERENCE_OUTSIDE_PROJECT"
        case .notFound: return "FILE_REFERENCE_NOT_FOUND"
        case .unreadable: return "FILE_REFERENCE_UNREADABLE"
        case .binaryUnsupported: return "FILE_REFERENCE_BINARY_UNSUPPORTED"
        case .tooLarge: return "FILE_REFERENCE_TOO_LARGE"
        case .tooMany: return "FILE_REFERENCE_TOO_MANY"
        case .sensitiveBlocked: return "FILE_REFERENCE_SENSITIVE_BLOCKED"
        case .invalidLineRange: return "FILE_REFERENCE_LINE_RANGE_INVALID"
        }
    }

    public var description: String {
        switch self {
        case .projectRootMissing:
            return "thread has no project working directory for file references"
        case .outsideProject(let path):
            return "file reference is outside the project root: \(path)"
        case .notFound(let path):
            return "file reference not found: \(path)"
        case .unreadable(let path):
            return "file reference unreadable: \(path)"
        case .binaryUnsupported(let path):
            return "file reference is not UTF-8 text: \(path)"
        case .tooLarge(let path, let limit):
            return "file reference exceeds \(limit) bytes: \(path)"
        case .tooMany(let limit):
            return "too many file references; maximum is \(limit)"
        case .sensitiveBlocked(let path):
            return "file reference looks sensitive and was blocked: \(path)"
        case .invalidLineRange(let path):
            return "file reference has an invalid line range: \(path)"
        }
    }
}

public struct ResolvedFileReference: Sendable, Equatable {
    public var turnRef: TurnFileReferenceRef
    public var attachedFile: ThreadContextBuilder.Options.AttachedFileInput

    public init(
        turnRef: TurnFileReferenceRef,
        attachedFile: ThreadContextBuilder.Options.AttachedFileInput
    ) {
        self.turnRef = turnRef
        self.attachedFile = attachedFile
    }
}

public struct ProjectFileReferenceResolver {
    public var policy: FileReferencePolicy

    public init(policy: FileReferencePolicy = .default) {
        self.policy = policy
    }

    public func resolve(
        inputs: [FileReferenceInput],
        rootPath: String?,
        projectId: String?,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString }
    ) throws -> [ResolvedFileReference] {
        guard inputs.count <= policy.maxCount else {
            throw FileReferenceError.tooMany(policy.maxCount)
        }
        guard let rootPath, !rootPath.isEmpty else {
            throw FileReferenceError.projectRootMissing
        }
        let rootURL = URL(fileURLWithPath: rootPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileReferenceError.projectRootMissing
        }

        return try inputs.enumerated().map { sequence, input in
            try resolveOne(
                input,
                rootURL: rootURL,
                projectId: projectId,
                sequence: sequence,
                referenceId: idFactory()
            )
        }
    }

    private func resolveOne(
        _ input: FileReferenceInput,
        rootURL: URL,
        projectId: String?,
        sequence: Int,
        referenceId: String
    ) throws -> ResolvedFileReference {
        let candidate = candidateURL(for: input.path, rootURL: rootURL)
        guard isContained(candidate, in: rootURL) else {
            throw FileReferenceError.outsideProject(input.path)
        }

        let rootRelativePath = relativePath(for: candidate, rootURL: rootURL)
        guard !isSensitive(rootRelativePath) else {
            throw FileReferenceError.sensitiveBlocked(rootRelativePath)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            throw FileReferenceError.notFound(rootRelativePath)
        }
        guard !isDirectory.boolValue else {
            throw FileReferenceError.unreadable(rootRelativePath)
        }

        let data: Data
        do {
            data = try Data(contentsOf: candidate)
        } catch {
            throw FileReferenceError.unreadable(rootRelativePath)
        }
        guard data.count <= policy.maxSourceBytes else {
            throw FileReferenceError.tooLarge(rootRelativePath, policy.maxSourceBytes)
        }
        guard !data.contains(0), let fullText = String(data: data, encoding: .utf8) else {
            throw FileReferenceError.binaryUnsupported(rootRelativePath)
        }

        let deliveredText: String
        if let range = input.lineRange {
            guard let sliced = Self.slice(fullText, lineRange: range) else {
                throw FileReferenceError.invalidLineRange(rootRelativePath)
            }
            deliveredText = sliced
        } else {
            deliveredText = fullText
        }

        let turnRef = TurnFileReferenceRef(referenceId: referenceId, sequence: sequence)
        let attached = ThreadContextBuilder.Options.AttachedFileInput(
            path: rootRelativePath,
            referenceId: referenceId,
            sequence: sequence,
            projectId: projectId,
            rootRelativePath: rootRelativePath,
            resolvedPath: candidate.path,
            lineRange: input.lineRange,
            preloadedText: deliveredText,
            storedSha256: sha256Hex(data),
            byteSize: data.count,
            languageHint: languageHint(for: rootRelativePath)
        )
        return ResolvedFileReference(turnRef: turnRef, attachedFile: attached)
    }

    private func candidateURL(for path: String, rootURL: URL) -> URL {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath()
        }
        return rootURL.appendingPathComponent(raw).standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isContained(_ candidate: URL, in rootURL: URL) -> Bool {
        let root = rootURL.path
        let path = candidate.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let root = rootURL.path
        let path = url.path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    private func isSensitive(_ path: String) -> Bool {
        let components = path.split(separator: "/").map { $0.lowercased() }
        guard let filename = components.last else { return false }
        if filename == ".env" || filename.hasPrefix(".env.") { return true }
        if filename.hasSuffix(".pem") || filename.hasSuffix(".key") { return true }
        if ["id_rsa", "id_dsa", "id_ed25519", "credentials", "token", "secret"].contains(filename) {
            return true
        }
        return components.contains { $0 == ".ssh" || $0 == ".aws" || $0 == ".gnupg" }
    }

    private static func slice(_ text: String, lineRange: FileLineRange) -> String? {
        guard lineRange.startLine >= 1, lineRange.endLine >= lineRange.startLine else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lineRange.endLine <= lines.count else { return nil }
        return lines[(lineRange.startLine - 1)...(lineRange.endLine - 1)].joined(separator: "\n")
    }

    private func languageHint(for path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum FileReferenceTokenParser {
    public static func parse(message: String) -> [FileReferenceInput] {
        var refs: [FileReferenceInput] = []
        var index = message.startIndex
        while index < message.endIndex {
            guard message[index] == "@" else {
                index = message.index(after: index)
                continue
            }
            let previous = index == message.startIndex ? nil : message[message.index(before: index)]
            guard previous == nil || previous?.isWhitespace == true || "([{\"'".contains(previous!) else {
                index = message.index(after: index)
                continue
            }
            var end = message.index(after: index)
            while end < message.endIndex, !message[end].isWhitespace {
                end = message.index(after: end)
            }
            let token = String(message[message.index(after: index)..<end])
            if let parsed = parseSpecifier(token), looksLikePath(parsed.path) {
                refs.append(parsed)
            }
            index = end
        }
        return refs.dedupedPreservingOrder()
    }

    public static func parseSpecifier(_ raw: String) -> FileReferenceInput? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("@") { token.removeFirst() }
        while let last = token.last, ".,;)]}\"'".contains(last) {
            token.removeLast()
        }
        guard !token.isEmpty else { return nil }

        if let colon = token.lastIndex(of: ":") {
            let suffix = String(token[token.index(after: colon)...])
            let path = String(token[..<colon])
            if let range = parseLineRange(suffix), !path.isEmpty {
                return FileReferenceInput(path: path, lineRange: range)
            }
        }
        return FileReferenceInput(path: token)
    }

    private static func parseLineRange(_ suffix: String) -> FileLineRange? {
        guard !suffix.isEmpty else { return nil }
        let parts = suffix.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 1, let line = Int(parts[0]) {
            return FileLineRange(startLine: line, endLine: line)
        }
        if parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) {
            return FileLineRange(startLine: start, endLine: end)
        }
        return nil
    }

    private static func looksLikePath(_ path: String) -> Bool {
        path.contains("/") || path.contains(".")
    }
}

public struct ProjectFileCatalog {
    public struct Candidate: Sendable, Equatable {
        public var path: String
        public var modifiedAt: Date?
        public var rankScore: Double

        public init(path: String, modifiedAt: Date?, rankScore: Double) {
            self.path = path
            self.modifiedAt = modifiedAt
            self.rankScore = rankScore
        }
    }

    public init() {}

    // MARK: Ranking (FR-S08)

    /// Match-quality tiers — these dominate the score so freshness can only reorder
    /// WITHIN a tier, never promote a weak match over a stronger one. No repo-specific
    /// vocabulary lives here: a path ranks only because the user typed it (match), it is
    /// fresh, or it is a readable doc.
    enum MatchTier: Int {
        case fuzzyPath = 1
        case fuzzyBasename = 2
        case pathContains = 3
        case basenameContains = 4
        case pathSegmentPrefix = 5
        case basenamePrefix = 6
        case exactBasename = 7
    }
    /// At/above this tier the query is "very exact" — noisy files are NOT sunk.
    private static let exactTierFloor = MatchTier.basenamePrefix.rawValue
    private static let tierWeight = 1_000_000.0

    /// A one-time corpus scan: the project's file paths + the set of dirty/staged/
    /// untracked paths. This is the ONLY expensive part (git subprocesses) — do it ONCE,
    /// off the main thread, then `rank()` the cached snapshot in-memory per keystroke.
    /// No per-file `stat` (the old code did one per file → a beachball on big repos).
    public struct Snapshot: Sendable, Equatable {
        public var paths: [String]
        public var dirty: Set<String>
        public init(paths: [String], dirty: Set<String>) {
            self.paths = paths
            self.dirty = dirty
        }
    }

    public func snapshot(rootPath: String) -> Snapshot {
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        let paths = gitTrackedAndUntrackedFiles(rootURL: rootURL) ?? walkFiles(rootURL: rootURL)
        return Snapshot(paths: paths, dirty: dirtyPaths(rootURL: rootURL))
    }

    /// Pure, in-memory ranking over a cached snapshot — no I/O, so it's instant per
    /// keystroke. Match-quality tier dominates; freshness (recent ≫ dirty > touched) and
    /// the readable-doc tiebreak only reorder within a tier. (Recently-modified/mtime is
    /// intentionally dropped here — statting every file is what froze the UI.)
    public func rank(
        _ snapshot: Snapshot,
        query: String = "",
        limit: Int = 40,
        recentlyReferenced: [String] = [],
        laneTouched: [String] = []
    ) -> [Candidate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let recentRanks = Dictionary(uniqueKeysWithValues: recentlyReferenced.enumerated().map { ($0.element, $0.offset) })
        let laneSet = Set(laneTouched)
        let dirtySet = snapshot.dirty

        return snapshot.paths.compactMap { path -> Candidate? in
            let lowerPath = path.lowercased()
            let basename = ((path as NSString).lastPathComponent).lowercased()

            var effectiveTier = 0
            if !q.isEmpty {
                guard let tier = Self.matchTier(query: q, basename: basename, path: lowerPath) else { return nil }
                effectiveTier = tier.rawValue
                if effectiveTier < Self.exactTierFloor, Self.isNoisy(lowerPath) {
                    effectiveTier = max(0, effectiveTier - 3)
                }
            } else if Self.isNoisy(lowerPath) {
                effectiveTier = -1
            }

            var fresh = 0.0
            if let rank = recentRanks[path] { fresh += 20_000 - Double(min(rank, 99)) * 100 }
            if dirtySet.contains(path) { fresh += 8_000 }
            if laneSet.contains(path) { fresh += 1_000 }
            if Self.isReadableDoc(basename) { fresh += 150 }

            let score = Double(effectiveTier) * Self.tierWeight + fresh
            return Candidate(path: path, modifiedAt: nil, rankScore: score)
        }
        .sorted {
            if $0.rankScore == $1.rankScore { return $0.path < $1.path }
            return $0.rankScore > $1.rankScore
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Convenience (CLI/tests): scan + rank in one call. The GUI must NOT use this on the
    /// main thread — it scans every time. Use `snapshot()` once + `rank()` per keystroke.
    public func candidates(
        rootPath: String,
        query: String = "",
        limit: Int = 40,
        recentlyReferenced: [String] = [],
        laneTouched: [String] = []
    ) -> [Candidate] {
        rank(snapshot(rootPath: rootPath), query: query, limit: limit,
             recentlyReferenced: recentlyReferenced, laneTouched: laneTouched)
    }

    /// Best match tier of `query` against the path. Order from strongest: exact basename,
    /// basename prefix, any path-segment prefix, basename contains, path contains, then
    /// fuzzy (abbreviation/subsequence) on the basename and finally the whole path.
    static func matchTier(query q: String, basename: String, path: String) -> MatchTier? {
        guard !q.isEmpty else { return nil }
        if basename == q { return .exactBasename }
        if basename.hasPrefix(q) { return .basenamePrefix }
        if path.split(separator: "/").contains(where: { $0.hasPrefix(q) }) { return .pathSegmentPrefix }
        if basename.contains(q) { return .basenameContains }
        if path.contains(q) { return .pathContains }
        if isSubsequence(q, of: basename) { return .fuzzyBasename }
        if isSubsequence(q, of: path) { return .fuzzyPath }
        return nil
    }

    /// Classic subsequence test — `needle`'s characters appear in order within `hay`
    /// (the abbreviation match, e.g. "ssotf" → "ssot_founder…").
    static func isSubsequence(_ needle: String, of hay: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var it = hay.makeIterator()
        for ch in needle {
            var matched = false
            while let h = it.next() {
                if h == ch { matched = true; break }
            }
            if !matched { return false }
        }
        return true
    }

    private static let readableDocExtensions: Set<String> = ["md", "mdx", "txt", "rst", "adoc"]
    static func isReadableDoc(_ basename: String) -> Bool {
        readableDocExtensions.contains((basename as NSString).pathExtension)
    }

    /// Generated / build / vendor / cache / archive noise — sunk unless the query is very
    /// exact. Generic patterns only; no repo-specific names.
    private static let noisyDirSegments: Set<String> = [
        "node_modules", ".build", "build", "dist", "out", "deriveddata", "pods", "vendor",
        ".git", "coverage", ".cache", "__pycache__", ".next", ".nuxt", ".gradle", "target",
        ".terraform", "bin", "obj"
    ]
    static func isNoisy(_ lowerPath: String) -> Bool {
        let segments = lowerPath.split(separator: "/").map(String.init)
        if segments.dropLast().contains(where: { noisyDirSegments.contains($0) }) { return true }
        guard let name = segments.last else { return false }
        if name.hasSuffix(".lock") || name.hasSuffix(".min.js") || name.hasSuffix(".min.css")
            || name.hasSuffix(".map") || name.hasSuffix(".pyc") || name.hasSuffix(".o")
            || name.hasSuffix(".class") { return true }
        if ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "podfile.lock", "cargo.lock"].contains(name) {
            return true
        }
        let ext = (name as NSString).pathExtension
        return ["zip", "tar", "gz", "tgz", "bz2", "xz", "jar", "war"].contains(ext)
    }

    /// Paths git reports as staged/unstaged/untracked — a strong freshness signal. One
    /// bounded subprocess; an empty set when not a git repo (no correctness dependency).
    private func dirtyPaths(rootURL: URL) -> Set<String> {
        let process = Process()
        process.currentDirectoryURL = rootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "status", "--porcelain", "-z"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        // Drain before waiting — same pipe-deadlock guard as the file listing.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        var dirty = Set<String>()
        for entry in raw.split(separator: "\0") where entry.count > 3 {
            // Each entry is "XY <path>"; renames spill the old path into the next entry,
            // which we harmlessly also add. Status codes are never valid paths here.
            let path = String(entry.dropFirst(3))
            if !path.isEmpty { dirty.insert(path) }
        }
        return dirty
    }

    private func gitTrackedAndUntrackedFiles(rootURL: URL) -> [String]? {
        let process = Process()
        process.currentDirectoryURL = rootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain the pipe BEFORE waitUntilExit. On a big repo git's output exceeds the
        // 64KB pipe buffer; if we waited first, git would block writing and we'd block
        // waiting → deadlock (the bug that hung the @ picker on real repos but never in
        // the tiny fixtures).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let files = raw.split(separator: "\0").map(String.init)
        return files.isEmpty ? nil : files
    }

    private func walkFiles(rootURL: URL) -> [String] {
        let skip = Set([".git", ".allnighter", "node_modules", ".build", "build", "dist", "DerivedData", "Pods"])
        guard let subpaths = try? FileManager.default.subpathsOfDirectory(atPath: rootURL.path) else {
            return []
        }
        return subpaths.filter { path in
            let parts = path.split(separator: "/").map(String.init)
            guard !parts.contains(where: { skip.contains($0) }) else { return false }
            var isDirectory: ObjCBool = false
            let absolute = rootURL.appendingPathComponent(path).path
            return FileManager.default.fileExists(atPath: absolute, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }
}

extension Array where Element == FileReferenceInput {
    public func dedupedPreservingOrder() -> [FileReferenceInput] {
        var seen = Set<String>()
        return filter { input in
            let range = input.lineRange.map { ":\($0.startLine)-\($0.endLine)" } ?? ""
            return seen.insert(input.path + range).inserted
        }
    }
}
