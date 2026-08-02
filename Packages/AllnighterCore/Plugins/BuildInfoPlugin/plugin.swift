import Foundation
import PackagePlugin

/// Embeds build identity (`gitSha` / `buildTime`) into AllnighterCore.
///
/// Why two commands:
/// - **prebuildCommand** — required for Xcode. The Mac target builds AllnighterCore
///   through Xcode's package bridge; a lone `.buildCommand` is applied (outputs
///   land in the Swift file list) but the custom task is never scheduled, which
///   yields "Build input file cannot be found: …/BuildInfo.generated.swift".
/// - **buildCommand** — required for SwiftPM incremental freshness. Declared
///   inputs include git HEAD/ref files so a commit/checkout re-runs generation
///   even when no package source mtimes moved. Xcode may ignore this task; the
///   prebuild already materialised the file, so compile still succeeds.
///
/// Belt-and-braces: `scripts/rebuild_cli.sh` deletes the cached generated file,
/// and `VersionIdentityTests.testBuildInfoGitShaMatchesWorkspaceHEAD` fails the
/// suite if a stale SHA is still linked.
@main
struct BuildInfoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target.name == "AllnighterCore" else { return [] }

        let packageDir = context.package.directoryURL
        let outputDir = context.pluginWorkDirectoryURL
        let outputFile = outputDir.appendingPathComponent("BuildInfo.generated.swift")
        let script = packageDir
            .appendingPathComponent("Plugins")
            .appendingPathComponent("BuildInfoPlugin")
            .appendingPathComponent("generate-build-info.sh")

        // Packages/AllnighterCore → repo root
        let repoRoot = packageDir.deletingLastPathComponent().deletingLastPathComponent()
        var buildInputs: [URL] = [script]
        buildInputs.append(contentsOf: gitDependencyPaths(repoRoot: repoRoot))

        let args = [packageDir.path, outputDir.path]

        return [
            .prebuildCommand(
                displayName: "Generating alln build identity (prebuild)",
                executable: script,
                arguments: args,
                outputFilesDirectory: outputDir
            ),
            .buildCommand(
                displayName: "Refreshing alln build identity",
                executable: script,
                arguments: args,
                inputFiles: buildInputs,
                outputFiles: [outputFile]
            ),
        ]
    }

    // MARK: - Inputs that must invalidate build identity

    /// HEAD + current branch ref + packed-refs so a commit (or checkout) re-runs
    /// generation even when no package source mtimes moved.
    private func gitDependencyPaths(repoRoot: URL) -> [URL] {
        let fm = FileManager.default
        guard let gitDir = resolvedGitDir(repoRoot: repoRoot) else { return [] }

        var paths: [URL] = []
        let head = gitDir.appendingPathComponent("HEAD")
        guard fm.fileExists(atPath: head.path) else { return [] }
        paths.append(head)

        if let headText = try? String(contentsOf: head, encoding: .utf8) {
            let trimmed = headText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ref:") {
                let ref = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
                // Walk components so "refs/heads/…" is not percent-encoded as one segment.
                var refPath = gitDir
                for part in ref.split(separator: "/") where !part.isEmpty {
                    refPath = refPath.appendingPathComponent(String(part))
                }
                if fm.fileExists(atPath: refPath.path) {
                    paths.append(refPath)
                }
            }
        }

        let packed = gitDir.appendingPathComponent("packed-refs")
        if fm.fileExists(atPath: packed.path) {
            paths.append(packed)
        }
        return paths
    }

    /// Resolves `.git` for normal repos and linked worktrees (`gitdir:` file).
    private func resolvedGitDir(repoRoot: URL) -> URL? {
        let fm = FileManager.default
        let dotGit = repoRoot.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) else {
            return nil
        }
        if isDir.boolValue {
            return dotGit
        }
        // Worktree: `.git` is a file containing `gitdir: <path>`.
        guard let text = try? String(contentsOf: dotGit, encoding: .utf8) else {
            return nil
        }
        for line in text.split(separator: "\n") {
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.lowercased().hasPrefix("gitdir:") else { continue }
            let value = raw.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            if value.isEmpty { return nil }
            if (value as NSString).isAbsolutePath {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return repoRoot.appendingPathComponent(value)
        }
        return nil
    }
}
