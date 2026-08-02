import Foundation
import PackagePlugin

/// Embeds build identity (`gitSha` / `buildTime`) into AllnighterCore.
///
/// Xcode's package bridge records a `.buildCommand`'s outputs in the Swift file
/// list but never schedules the custom task ("Build input file cannot be
/// found"). A lone `.prebuildCommand` is scheduled under Xcode but does not
/// re-run on SwiftPM incremental builds when HEAD moves.
///
/// Fix: **eagerly materialize** `BuildInfo.generated.swift` while the plugin
/// is applied (createBuildCommands runs under both toolchains during plan /
/// "Apply build tool plug-in"), *and* return a `.buildCommand` whose inputs
/// include git HEAD/ref so SwiftPM incremental builds re-run generation when
/// the tree moves. No `.prebuildCommand` — dual producers of the same object
/// file break SwiftPM ("multiple producers").
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

        // Eager write so Xcode has the file before compile (custom task may never run).
        try materializeBuildInfo(script: script, packageDir: packageDir, outputDir: outputDir)

        let repoRoot = packageDir.deletingLastPathComponent().deletingLastPathComponent()
        var buildInputs: [URL] = [script]
        buildInputs.append(contentsOf: gitDependencyPaths(repoRoot: repoRoot))

        return [
            .buildCommand(
                displayName: "Refreshing alln build identity",
                executable: script,
                arguments: [
                    packageDir.path,
                    outputDir.path,
                ],
                inputFiles: buildInputs,
                outputFiles: [outputFile]
            ),
        ]
    }

    /// Run the generator immediately during plugin application.
    private func materializeBuildInfo(script: URL, packageDir: URL, outputDir: URL) throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = script
        process.arguments = [packageDir.path, outputDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            // Fall through: still declare the buildCommand; SPM will run it.
            // Xcode without a file still fails the same way — surface that loudly.
            Diagnostics.warning("BuildInfoPlugin: generate-build-info.sh exited \(process.terminationStatus) during plan; relying on buildCommand")
        }
    }

    // MARK: - Inputs that must invalidate build identity

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
