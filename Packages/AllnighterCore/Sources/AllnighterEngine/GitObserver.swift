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
