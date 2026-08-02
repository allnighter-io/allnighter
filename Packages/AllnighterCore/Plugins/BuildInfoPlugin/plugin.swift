import Foundation
import PackagePlugin

/// Embeds build identity (`gitSha` / `buildTime`) into AllnighterCore.
///
/// Uses a **buildCommand** (not prebuildCommand) whose inputs include the git
/// HEAD/ref files and every Core Swift source. SwiftPM's prebuild phase does
/// **not** re-run on incremental builds in practice — so a stale
/// `BuildInfo.generated.swift` was being linked while other sources recompiled,
/// and `alln version` reported an old gitSha even though contract/binary
/// constants matched HEAD. Declared inputs force regeneration whenever the
/// tree the binary is built from moves.
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

        var inputs: [URL] = [script]
        inputs.append(contentsOf: gitDependencyPaths(repoRoot: repoRoot))
        inputs.append(contentsOf: coreSwiftSources(packageDir: packageDir))

        return [
            .buildCommand(
                displayName: "Generating alln build identity",
                executable: script,
                arguments: [
                    packageDir.path,
                    outputDir.path,
                ],
                inputFiles: inputs,
                outputFiles: [outputFile]
            )
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

    /// Any Core source edit must refresh identity (and buildTime) so an
    /// incremental rebuild cannot keep a stale generated file.
    private func coreSwiftSources(packageDir: URL) -> [URL] {
        let root = packageDir
            .appendingPathComponent("Sources")
            .appendingPathComponent("AllnighterCore")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var paths: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            paths.append(url)
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
