import Foundation

/// Escapes the foreground process cwd when it sits under a TCC-protected home
/// folder (`~/Documents`, `~/Desktop`, `~/Downloads`). Install-cli and
/// serve-mutate paths spawn `launchctl` children that inherit cwd; a Documents
/// checkout therefore trips a Documents prompt attributed to `alln`.
///
/// Call at the top of `runInstallCLI` and `serve enable|repair|disable` handlers
/// — not in `AllnighterCLI.main` (repo-scoped `alln run` / `ps` keep cwd).
public enum ProtectedCWDEscape {

    public struct Seams: Sendable {
        public var currentDirectory: @Sendable () -> String
        public var homeDirectory: @Sendable () -> URL
        public var ensureProbeScratch: @Sendable () -> String?
        public var changeCurrentDirectory: @Sendable (String) -> Bool

        public init(
            currentDirectory: @escaping @Sendable () -> String,
            homeDirectory: @escaping @Sendable () -> URL,
            ensureProbeScratch: @escaping @Sendable () -> String?,
            changeCurrentDirectory: @escaping @Sendable (String) -> Bool
        ) {
            self.currentDirectory = currentDirectory
            self.homeDirectory = homeDirectory
            self.ensureProbeScratch = ensureProbeScratch
            self.changeCurrentDirectory = changeCurrentDirectory
        }

        public static var live: Seams {
            Seams(
                currentDirectory: { FileManager.default.currentDirectoryPath },
                homeDirectory: { FileManager.default.homeDirectoryForCurrentUser },
                ensureProbeScratch: { AllnighterPaths.ensuredProbeScratchPath() },
                changeCurrentDirectory: { FileManager.default.changeCurrentDirectoryPath($0) }
            )
        }
    }

    private static let protectedHomeFolders = ["Downloads", "Desktop", "Documents"]

    /// Returns whether `currentDirectory` resolves under one of the user's
    /// protected home folders (home-relative prefix match).
    public static func isProtected(currentDirectory: String, homeDirectory: URL) -> Bool {
        let resolvedHome = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = URL(fileURLWithPath: currentDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        for folder in protectedHomeFolders {
            let folderPath = resolvedHome.appendingPathComponent(folder).path
            if resolved == folderPath || resolved.hasPrefix(folderPath + "/") {
                return true
            }
        }
        return false
    }

    /// Moves cwd to ProbeScratch when protected; falls back to home if scratch
    /// cannot be created. Returns whether cwd was changed.
    @discardableResult
    public static func escapeIfNeeded(seams: Seams = .live) -> Bool {
        let cwd = seams.currentDirectory()
        let home = seams.homeDirectory()
        guard isProtected(currentDirectory: cwd, homeDirectory: home) else {
            return false
        }
        let target = seams.ensureProbeScratch() ?? home.path
        return seams.changeCurrentDirectory(target)
    }
}
