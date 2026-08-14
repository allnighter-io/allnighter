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
        public var canonicalPath: String?
        public var rollbackPath: String?
        public var codeIdentity: String?
        public var version: String?
        public var noServeSource: String?
        public init(schemaVersion: Int = 2, action: Action, path: String? = nil, target: String? = nil, onPath: Bool? = nil, canonicalPath: String? = nil, rollbackPath: String? = nil, codeIdentity: String? = nil, version: String? = nil, noServeSource: String? = nil) {
            self.schemaVersion = schemaVersion
            self.action = action
            self.path = path
            self.target = target
            self.onPath = onPath
            self.canonicalPath = canonicalPath
            self.rollbackPath = rollbackPath
            self.codeIdentity = codeIdentity
            self.version = version
            self.noServeSource = noServeSource
        }
    }

    public struct Request {
        public var argv0: String?
        public var pathOverride: String?
        public var printOnly: Bool
        public var pathEnvironment: String?
        public var homeDirectory: URL
        public var fileManager: FileManager
        public var canonicalInstall: (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure>
        public var version: String?
        public var noServeSource: String?

        public init(
            argv0: String? = nil,
            pathOverride: String? = nil,
            printOnly: Bool = false,
            pathEnvironment: String? = nil,
            homeDirectory: URL? = nil,
            fileManager: FileManager = .default,
            canonicalInstall: @escaping (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> = { candidate, home, version, fm in
                CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: home, version: version, fileManager: fm)
            },
            version: String? = nil,
            noServeSource: String? = nil
        ) {
            self.argv0 = argv0
            self.pathOverride = pathOverride
            self.printOnly = printOnly
            self.pathEnvironment = pathEnvironment
            self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
            self.fileManager = fileManager
            self.canonicalInstall = canonicalInstall
            self.version = version
            self.noServeSource = noServeSource
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

    public static func resolvedHomeDirectory(
        environment: [String: String],
        fileManager: FileManager = .default
    ) -> URL {
        if let home = environment["HOME"],
           !home.isEmpty,
           home.hasPrefix("/") {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: home, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: home)
            }
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    /// Default install dir: `~/.local/bin` unconditionally.
    /// `/usr/local/bin` is reachable only through an explicit `--path`.
    public static func defaultInstallDirectory(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> String {
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

    private struct CanonicalIdentityRecord: Codable {
        let identity: CanonicalCLIInstall.CodeIdentity
    }

    public static func run(_ request: Request) -> Outcome {
        guard let runningBinary = resolvedRunningBinary(
            argv0: request.argv0,
            pathEnvironment: request.pathEnvironment,
            fileManager: request.fileManager
        ) else {
            return .failed(code: "CLI_USAGE_ERROR", message: "could not resolve the running binary path")
        }

        if request.printOnly {
            let onPathNow = onPath(runningBinary: runningBinary, pathEnvironment: request.pathEnvironment, fileManager: request.fileManager)
            return .printed(JSON(action: .printed, path: nil, target: runningBinary, onPath: onPathNow, noServeSource: request.noServeSource))
        }

        let candidateURL = URL(fileURLWithPath: runningBinary)

        switch request.canonicalInstall(candidateURL, request.homeDirectory, request.version, request.fileManager) {
        case .failure(let failure):
            var message = failure.message
            if failure.code == "SERVE_ROLLBACK_FAILED" {
                let canonicalPath = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: request.homeDirectory).path
                let rollbackPath = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: request.homeDirectory).path
                message.append("\n\nTo recover:\n  cp \"\(rollbackPath)\" \"\(canonicalPath)\"")
                message.append("\nIf that fails, reinstall via the one-paste cold-start faucet.")
            }
            return .failed(code: failure.code, message: message)
        case .success(let report):
            let canonicalURL = report.canonicalURL
            let canonicalTarget = canonicalURL.path

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
                if let existingResolved, sameExecutable(existingResolved, canonicalTarget) {
                    action = .alreadyInstalled
                } else {
                    do {
                        try request.fileManager.removeItem(atPath: symlinkPath)
                        try request.fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: canonicalTarget)
                        action = .repaired
                    } catch {
                        return .failed(code: "INSTALL_CLI_TARGET_UNWRITABLE", message: "could not repair symlink at \(symlinkPath): \(error.localizedDescription)")
                    }
                }
            } else {
                do {
                    try request.fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: canonicalTarget)
                    action = .installed
                } catch {
                    return .failed(code: "INSTALL_CLI_TARGET_UNWRITABLE", message: "could not create symlink at \(symlinkPath): \(error.localizedDescription)")
                }
            }

            do {
                try CLIResourceBundles.linkSiblings(
                    from: canonicalURL.deletingLastPathComponent(),
                    into: URL(fileURLWithPath: installDir),
                    fileManager: request.fileManager
                )
            } catch {
                return .failed(
                    code: "INSTALL_CLI_TARGET_UNWRITABLE",
                    message: "could not link CLI resource bundles into \(installDir): \(error.localizedDescription)"
                )
            }

            let cdhash: String?
            if let data = try? Data(contentsOf: CanonicalCLIInstall.identityRecordURL(homeDirectory: request.homeDirectory)),
               let record = try? CoreJSON.decode(CanonicalIdentityRecord.self, from: data) {
                cdhash = record.identity.cdhash
            } else {
                cdhash = nil
            }

            let onPathNow = onPath(runningBinary: runningBinary, pathEnvironment: request.pathEnvironment, fileManager: request.fileManager)

            let rollbackPath: String?
            if let rb = report.rollbackURL {
                rollbackPath = rb.path
            } else {
                rollbackPath = nil
            }

            return .installed(JSON(
                action: action,
                path: symlinkPath,
                target: canonicalTarget,
                onPath: onPathNow,
                canonicalPath: canonicalTarget,
                rollbackPath: rollbackPath,
                codeIdentity: cdhash,
                version: request.version,
                noServeSource: request.noServeSource
            ))
        }
    }

    public static func printInstructions(target: String, installDir: String) -> String {
        """
        To call `alln` from any shell/agent, symlink it onto your PATH:
          ln -sf "\(target)" \(installDir)/\(symlinkName)
        (Distribution is deferred; this is the dev-build path.)
        """
    }

    public static func isNoServeEnvTruthy(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let lower = value.lowercased()
        return lower == "1" || lower == "true" || lower == "yes"
    }

    /// Human install receipt. TTY (`color: true`) paints amber phosphor;
    /// piped / `--json` callers stay on the JSON envelope. Disclosure
    /// obligation (scheduler why / how to change it) is preserved as rows.
    /// `tty` chooses the human next step (`alln`) vs the agent front door.
    public static func humanLine(_ json: JSON, color: Bool = false, tty: Bool = false) -> String {
        if json.action == .printed {
            return "Print-only install-cli instructions (use without --print to perform the install)."
        }

        let version = json.version ?? AllnighterVersionIdentity.binaryVersion
        let statusPhrase: String
        switch json.action {
        case .installed:
            statusPhrase = "ready"
        case .alreadyInstalled:
            statusPhrase = "already installed"
        case .repaired:
            statusPhrase = "repaired"
        case .printed:
            statusPhrase = "ready"
        }

        var lines: [String] = CLIPaint.banner(version: version, status: statusPhrase, color: color)

        let binary = json.canonicalPath ?? json.target ?? ""
        if !binary.isEmpty {
            lines.append(CLIPaint.row(label: "binary", value: CLIPaint.primary(binary, color: color), color: color))
        }
        if let path = json.path, !path.isEmpty, path != binary {
            lines.append(CLIPaint.row(label: "path", value: CLIPaint.primary(path, color: color), color: color))
        }

        lines.append(contentsOf: serveDisclosureRows(noServeSource: json.noServeSource, color: color))
        lines.append("")
        let next = tty ? "alln" : "alln menu --json"
        lines.append(CLIPaint.row(
            label: "next",
            value: CLIPaint.accent(next, bold: false, color: color),
            color: color
        ))
        lines.append(CLIPaint.row(
            label: "help",
            value: CLIPaint.muted(SupportHatch.email, color: color),
            color: color
        ))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Human disclosure for the serve scheduler, tied to the install transaction.
    /// §2.2 requires the install to say what was (or was not) installed, why it
    /// exists, and how to change it later. Keep this to a few lines.
    public static func serveDisclosure(noServeSource: String?) -> String {
        serveDisclosureRows(noServeSource: noServeSource, color: false)
            .joined(separator: "\n")
    }

    private static let schedulerSummary =
        "pending wake · PM turn wake · boost seed · vendor backoff · notifications · capacity refresh · probe record refresh"

    private static func serveDisclosureRows(noServeSource: String?, color: Bool) -> [String] {
        if let source = noServeSource {
            let optOutLabel = source == "flag" ? "--no-serve" : "ALLN_NO_SERVE"
            return [
                CLIPaint.row(
                    label: "scheduler",
                    value: CLIPaint.primary("skipped (\(optOutLabel)). The per-user background scheduler was not installed.", color: color),
                    color: color
                ),
                CLIPaint.row(
                    label: "",
                    value: CLIPaint.muted("It would handle deferred obligations: \(schedulerSummary).", color: color),
                    color: color,
                    continuation: true
                ),
                CLIPaint.row(
                    label: "",
                    value: CLIPaint.muted("`alln run` still works; only deferred scheduling is affected. Enable later with `alln serve enable`.", color: color),
                    color: color,
                    continuation: true
                ),
            ]
        }
        return [
            CLIPaint.row(
                label: "scheduler",
                value: CLIPaint.done("on", color: color)
                    + CLIPaint.muted(" · installed a per-user background scheduler for deferred obligations", color: color),
                color: color
            ),
            CLIPaint.row(
                label: "",
                value: CLIPaint.faint(schedulerSummary, color: color),
                color: color,
                continuation: true
            ),
            CLIPaint.row(
                label: "",
                value: CLIPaint.muted("`alln run` still works without it. Disable with `alln serve disable`.", color: color),
                color: color,
                continuation: true
            ),
        ]
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
