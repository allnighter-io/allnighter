import Foundation

/// Neutral CWD for CLI paths that must not touch TCC-protected home folders
/// (`~/Documents`, `~/Desktop`, `~/Downloads`).
///
/// Two different operations:
/// - `adoptNeutral` — `chdir` to ProbeScratch (home fallback) **without**
///   reading cwd. `getcwd` / `currentDirectoryPath` on a Documents checkout
///   **is** the TCC touch; `escapeIfNeeded` cannot prevent that first read.
///   Call from `AllnighterCLI.main` for every command that does not need the
///   caller's repo cwd (bare `alln`, help, version, menu, serve, …).
/// - `escapeIfNeeded` — read cwd, and only then move if it is protected.
///   Keep for install-cli / serve-mutate children that inherit cwd. Never use
///   this as the bare-`alln` belt.
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
    ///
    /// Reads cwd first — that read is itself a Documents TCC prompt when the
    /// process already sits in a protected folder. Prefer `adoptNeutral` when
    /// the command does not need the caller's cwd.
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

    /// `chdir` to ProbeScratch (home fallback) without reading the current
    /// directory. POSIX `chdir("/absolute")` does not `getcwd`.
    @discardableResult
    public static func adoptNeutral(seams: Seams = .live) -> Bool {
        let target = seams.ensureProbeScratch() ?? seams.homeDirectory().path
        return seams.changeCurrentDirectory(target)
    }

    /// Commands whose product meaning is "this checkout" — `alln run`, project
    /// scope, git-from-cwd. Everything else must `adoptNeutral` before
    /// `ToolRuntime` / catalog load / any `Process` spawn.
    public static func preservesCallerWorkingDirectory(
        command: String,
        args: [String] = []
    ) -> Bool {
        switch command {
        case "run", "loop", "sweep", "project", "ps", "kill", "gc",
             "pending", "stalled", "artifact", "export", "spec", "thread",
             "continuity", "dev":
            return true
        case "doctor" where args.first == "handoff":
            return true
        default:
            return false
        }
    }
}
