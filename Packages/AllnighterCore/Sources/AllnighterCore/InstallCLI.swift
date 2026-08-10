import Foundation

/// `alln install-cli` — symlink the running binary onto PATH (docs/phases/Agent_Front_Door.md F1).
/// Injectable filesystem/PATH seams keep unit tests off the real machine layout.
public enum InstallCLI {
    public static let commandName = "alln"
    public static let symlinkName = "alln"

    public enum Action: String, Codable, Sendable, Equatable {
        case installed, repaired, alreadyInstalled, printed
    }

    public struct JSON: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var action: Action
        public var path: String?
        public var target: String?
        public var onPath: Bool?
        public init(schemaVersion: Int = 1, action: Action, path: String? = nil, target: String? = nil, onPath: Bool? = nil) {
            self.schemaVersion = schemaVersion
            self.action = action
            self.path = path
            self.target = target
            self.onPath = onPath
        }
    }

    public struct Request {
        public var argv0: String?
        public var pathOverride: String?
        public var printOnly: Bool
        public var pathEnvironment: String?
        public var homeDirectory: URL
        public var fileManager: FileManager

        public init(
            argv0: String? = nil,
            pathOverride: String? = nil,
            printOnly: Bool = false,
            pathEnvironment: String? = nil,
            homeDirectory: URL? = nil,
            fileManager: FileManager = .default
        ) {
            self.argv0 = argv0
            self.pathOverride = pathOverride
            self.printOnly = printOnly
            self.pathEnvironment = pathEnvironment
            self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
            self.fileManager = fileManager
        }
    }

    public enum Outcome: Sendable, Equatable {
        case printed(JSON)
        case installed(JSON)
        case failed(code: String, message: String)
    }

    /// Resolved absolute path of the running binary from `argv[0]`.
    ///
    /// Handles three shapes: absolute path; relative path with `/` (resolved against
    /// `currentDirectory`); bare command name (searches `pathEnvironment`, never
    /// fabricates `<cwd>/name`).
    public static func resolvedRunningBinary(
        argv0: String?,
        pathEnvironment: String? = nil,
        currentDirectory: String? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        guard let raw = argv0, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath

        if expanded.hasPrefix("/") {
            return resolveExistingExecutable(expanded, fileManager: fileManager)
        }
        if expanded.contains("/") {
            let cwd = currentDirectory ?? fileManager.currentDirectoryPath
            let absolute = URL(fileURLWithPath: cwd).appendingPathComponent(expanded).standardizedFileURL.path
            return resolveExistingExecutable(absolute, fileManager: fileManager)
        }
        guard let pathEnvironment else { return nil }
        return resolveOnPath(command: expanded, pathEnvironment: pathEnvironment, fileManager: fileManager)
    }

    private static func resolveExistingExecutable(_ path: String, fileManager: FileManager) -> String? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Default install dir: `/usr/local/bin` when writable, else `~/.local/bin`.
    public static func defaultInstallDirectory(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> String {
        let usrLocal = "/usr/local/bin"
        if fileManager.isWritableFile(atPath: usrLocal) { return usrLocal }
        return homeDirectory.appendingPathComponent(".local/bin").path
    }

    /// Resolve `command` on PATH to an absolute, symlink-resolved executable path.
    /// `nil` pathEnvironment → resolution unavailable (`notChecked` semantics upstream).
    public static func resolveOnPath(
        command: String = symlinkName,
        pathEnvironment: String?,
        fileManager: FileManager = .default
    ) -> String? {
        guard let pathEnvironment else { return nil }
        for component in pathEnvironment.split(separator: ":", omittingEmptySubsequences: false).map(String.init) {
            guard !component.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: component).appendingPathComponent(command).path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            guard fileManager.isExecutableFile(atPath: candidate) else { continue }
            return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().standardizedFileURL.path
        }
        return nil
    }

    public static func onPath(
        runningBinary: String,
        pathEnvironment: String?,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let resolved = resolveOnPath(pathEnvironment: pathEnvironment, fileManager: fileManager) else { return false }
        return sameExecutable(resolved, runningBinary)
    }

    public static func sameExecutable(_ a: String, _ b: String) -> Bool {
        RootNormalization.normalize(a).key == RootNormalization.normalize(b).key
    }

    public static func run(_ request: Request) -> Outcome {
        guard let target = resolvedRunningBinary(
            argv0: request.argv0,
            pathEnvironment: request.pathEnvironment,
            fileManager: request.fileManager
        ) else {
            return .failed(code: "CLI_USAGE_ERROR", message: "could not resolve the running binary path")
        }

        if request.printOnly {
            let onPathNow = onPath(runningBinary: target, pathEnvironment: request.pathEnvironment, fileManager: request.fileManager)
            return .printed(JSON(action: .printed, path: nil, target: target, onPath: onPathNow))
        }

        let installDir: String
        if let override = request.pathOverride {
            installDir = (override as NSString).expandingTildeInPath
        } else {
            installDir = defaultInstallDirectory(homeDirectory: request.homeDirectory, fileManager: request.fileManager)
        }

        let symlinkPath = URL(fileURLWithPath: installDir).appendingPathComponent(symlinkName).path

        switch ensureInstallDirectory(installDir, homeDirectory: request.homeDirectory, fileManager: request.fileManager) {
        case .failure(let message):
            return .failed(code: "INSTALL_CLI_TARGET_UNWRITABLE", message: message)
        case .success:
            break
        }

        guard request.fileManager.isWritableFile(atPath: installDir) else {
            return .failed(
                code: "INSTALL_CLI_TARGET_UNWRITABLE",
                message: unwritableMessage(installDir: installDir, homeDirectory: request.homeDirectory)
            )
        }

        let action: Action
        if request.fileManager.fileExists(atPath: symlinkPath) {
            let existingResolved = resolvedSymlinkTarget(
                at: symlinkPath,
                installDir: installDir,
                fileManager: request.fileManager
            )
            if let existingResolved, sameExecutable(existingResolved, target) {
                action = .alreadyInstalled
            } else {
                do {
                    try request.fileManager.removeItem(atPath: symlinkPath)
                    try request.fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: target)
                    action = .repaired
                } catch {
                    return .failed(code: "INSTALL_CLI_TARGET_UNWRITABLE", message: "could not repair symlink at \(symlinkPath): \(error.localizedDescription)")
                }
            }
        } else {
            do {
                try request.fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: target)
                action = .installed
            } catch {
                return .failed(code: "INSTALL_CLI_TARGET_UNWRITABLE", message: "could not create symlink at \(symlinkPath): \(error.localizedDescription)")
            }
        }

        let onPathNow = onPath(runningBinary: target, pathEnvironment: request.pathEnvironment, fileManager: request.fileManager)
        return .installed(JSON(action: action, path: symlinkPath, target: target, onPath: onPathNow))
    }

    public static func printInstructions(target: String, installDir: String) -> String {
        """
        To call `alln` from any shell/agent, symlink it onto your PATH:
          ln -sf "\(target)" \(installDir)/\(symlinkName)
        (Distribution is deferred; this is the dev-build path.)
        """
    }

    public static func humanLine(_ json: JSON) -> String {
        let pathLine: String
        switch json.action {
        case .printed:
            pathLine = "Print-only install-cli instructions (use without --print to perform the install)."
        case .alreadyInstalled:
            pathLine = "already installed: \(json.path ?? "") → \(json.target ?? "")"
        case .installed:
            pathLine = "installed: \(json.path ?? "") → \(json.target ?? "")"
        case .repaired:
            pathLine = "repaired stale symlink: \(json.path ?? "") → \(json.target ?? "")"
        }
        // FCS-L7: after any install-cli outcome that leaves `alln` on PATH, teach
        // find-CLIs before spend (agents read this line; humans do too).
        switch json.action {
        case .installed, .repaired, .alreadyInstalled:
            return pathLine
                + "\nNext: run `alln menu --json`; if benchTally.nextAction is set, run that command once."
        case .printed:
            return pathLine
        }
    }

    // MARK: - Private

    private enum DirPrep {
        case success, failure(String)
    }

    private static func ensureInstallDirectory(
        _ installDir: String,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> DirPrep {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: installDir, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                return .failure("install path exists but is not a directory: \(installDir)")
            }
            return .success
        }
        do {
            try fileManager.createDirectory(atPath: installDir, withIntermediateDirectories: true)
            return .success
        } catch {
            return .failure(unwritableMessage(installDir: installDir, homeDirectory: homeDirectory))
        }
    }

    private static func resolvedSymlinkTarget(
        at symlinkPath: String,
        installDir: String,
        fileManager: FileManager
    ) -> String? {
        guard let dest = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath) else { return nil }
        let expanded = (dest as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: installDir))
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func unwritableMessage(installDir: String, homeDirectory: URL) -> String {
        let fallback = homeDirectory.appendingPathComponent(".local/bin").path
        if installDir == "/usr/local/bin" {
            return "cannot write to /usr/local/bin. Run `alln install-cli --path \(fallback)` "
                + "(creates ~/.local/bin) or retry with sudo after ensuring the directory is writable."
        }
        return "cannot write to \(installDir). Choose a writable directory with --path <dir> "
            + "(e.g. `alln install-cli --path \(fallback)`)."
    }
}
