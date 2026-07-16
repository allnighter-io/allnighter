import Foundation
import AllnighterCore

/// Read-only observation of a local git root for a Project (PRJ-S01).
///
/// Observed, never invented: any field git cannot answer is `nil`, and a path
/// that is not the top level of a git repo reports `.folder`. No mutation, no
/// network — pure local reads (`rev-parse`, `remote get-url`, `status --porcelain`).
public struct GitObserver: Sendable {
    public struct Observation: Equatable, Sendable {
        public var kind: ProjectKind
        public var branch: String?
        public var head: String?
        public var remote: String?
        public var dirtySummary: String?
        public init(kind: ProjectKind, branch: String? = nil, head: String? = nil,
                    remote: String? = nil, dirtySummary: String? = nil) {
            self.kind = kind; self.branch = branch; self.head = head
            self.remote = remote; self.dirtySummary = dirtySummary
        }
    }

    public init() {}

    public func observe(rootPath: String) -> Observation {
        // A Project is a git repo only when `rootPath` IS the repo top level
        // (nested subdirs are separate Projects; see RootNormalization).
        guard let top = runGit(["rev-parse", "--show-toplevel"], cwd: rootPath),
              RootNormalization.sameRoot(top, rootPath) else {
            return Observation(kind: .folder)
        }
        // `--abbrev-ref HEAD` returns "HEAD" when detached; treat that as no branch.
        let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: rootPath).flatMap { $0 == "HEAD" ? nil : $0 }
        let head = runGit(["rev-parse", "HEAD"], cwd: rootPath)          // nil on an empty repo
        let remote = runGit(["remote", "get-url", "origin"], cwd: rootPath)
        let porcelain = runGit(["status", "--porcelain"], cwd: rootPath, treatEmptyAsValue: true)
        let dirtySummary: String? = {
            guard let porcelain, !porcelain.isEmpty else { return nil }   // empty == clean
            let n = porcelain.split(separator: "\n").count
            return "\(n) changed file\(n == 1 ? "" : "s")"
        }()
        return Observation(kind: .gitRepo, branch: branch, head: head, remote: remote, dirtySummary: dirtySummary)
    }

    /// The git repo top level containing `path` (from any subdir), as a normalized
    /// key — or `nil` if `path` is not inside a git work tree. Used by ProjectBinding.
    public func repoTopLevel(forPath path: String) -> String? {
        guard let top = runGit(["rev-parse", "--show-toplevel"], cwd: path) else { return nil }
        return RootNormalization.normalize(top).key
    }

    /// Dirty files as normalized, **root-relative** paths (observed via
    /// `status --porcelain`). Renames report the destination path. Empty when the
    /// tree is clean or `rootPath` is not a git repo top level. Used by the PRJ-S06
    /// dirty-overlap mutation gate — never mutates the tree.
    public func dirtyFiles(rootPath: String) -> [String] {
        // `-uall` lists every untracked file individually instead of collapsing a
        // new directory to one entry — overlap matching needs per-file paths.
        // Preserve leading whitespace: porcelain's first status column is a space
        // for unstaged-only changes (` M file`), and a blob trim would eat it.
        guard let porcelain = runGitRaw(["status", "--porcelain", "-uall"], cwd: rootPath),
              !porcelain.isEmpty else { return [] }
        return porcelain.split(separator: "\n").compactMap { line in
            // Porcelain v1: `XY <path>` or `XY <orig> -> <dest>` (rename/copy). XY is
            // exactly 2 status columns followed by one space.
            let entry = String(line)
            guard entry.count > 3 else { return nil }
            var path = String(entry.dropFirst(3))   // drop the 2 status chars + the space
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            // Porcelain quotes paths with unusual chars; strip the surrounding quotes.
            if path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2 {
                path = String(path.dropFirst().dropLast())
            }
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Recent commits as `<short-sha> <subject>` lines (newest first), observed.
    /// Empty when not a git repo or the repo has no commits.
    public func recentCommits(rootPath: String, limit: Int = 5) -> [String] {
        guard let out = runGit(["log", "-\(max(1, limit))", "--pretty=%h %s"], cwd: rootPath) else { return [] }
        return out.split(separator: "\n").map(String.init)
    }

    /// Commits reachable from `head` but not `baseline` (`baseline..head`), newest first.
    public func commitsInRange(rootPath: String, baseline: String, head: String) -> [RepoDelta.CommitInfo] {
        guard baseline != head,
              let out = runGit(["log", "\(baseline)..\(head)", "--pretty=format:%H %s"], cwd: rootPath),
              !out.isEmpty else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let entry = String(line)
            guard let space = entry.firstIndex(of: " ") else { return nil }
            let sha = String(entry[..<space])
            let subject = String(entry[entry.index(after: space)...])
            return RepoDelta.CommitInfo(sha: sha, subject: subject)
        }
    }

    /// Root-relative paths changed between `baseline` and `head` (`baseline..head`), observed.
    public func changedFilesInRange(rootPath: String, baseline: String, head: String) -> [String] {
        guard baseline != head,
              let out = runGit(["diff", "--name-only", "\(baseline)..\(head)"], cwd: rootPath),
              !out.isEmpty else { return [] }
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Observed repo delta for a mutating run window. When `baseline` and `head` are equal
    /// or either is missing, `changed` is `false` and commit/file lists are empty.
    public func repoDelta(
        rootPath: String, baseline: String?, head: String?, fileCap: Int = 50
    ) -> RepoDelta {
        let cap = max(1, fileCap)
        guard let baseline, let head else {
            return RepoDelta(changed: false, baseline: baseline, head: head)
        }
        guard baseline != head else {
            return RepoDelta(changed: false, baseline: baseline, head: head)
        }
        let commits = commitsInRange(rootPath: rootPath, baseline: baseline, head: head)
        let allFiles = changedFilesInRange(rootPath: rootPath, baseline: baseline, head: head)
        let truncated = allFiles.count > cap
        return RepoDelta(
            changed: true,
            baseline: baseline,
            head: head,
            commits: commits,
            filesChanged: allFiles.count,
            files: Array(allFiles.prefix(cap)),
            truncated: truncated
        )
    }

    /// Run a read-only git command, returning raw stdout with only the trailing
    /// newline removed (leading whitespace preserved — porcelain status columns
    /// depend on it). `nil` on launch failure / non-zero exit.
    private func runGitRaw(_ args: [String], cwd: String) -> String? {
        guard let git = SubprocessCommandRunner.resolveExecutable("git", env: ProcessInfo.processInfo.environment) else {
            return nil
        }
        let process = Process()
        process.executableURL = git
        process.arguments = ["-C", cwd] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
        return text
    }

    /// Run a read-only git command synchronously. Returns trimmed stdout, or `nil`
    /// on launch failure / non-zero exit. With `treatEmptyAsValue`, an empty
    /// stdout + exit 0 returns "" (so callers can tell "clean" from "failed").
    private func runGit(_ args: [String], cwd: String, treatEmptyAsValue: Bool = false) -> String? {
        guard let git = SubprocessCommandRunner.resolveExecutable("git", env: ProcessInfo.processInfo.environment) else {
            return nil
        }
        let process = Process()
        process.executableURL = git
        process.arguments = ["-C", cwd] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return treatEmptyAsValue ? "" : nil }
        return text
    }
}
