import Foundation

/// `alln uninstall` — disable serve first, then remove install-created artifacts.
/// Lifecycle disable is injected from AllnighterCLI (ServeLifecycle lives in Engine).
public enum UninstallCLI {
    public static let launchAgentLabel = "com.allnighter.resident-coordinator"

    public enum ArtifactDisposition: String, Codable, Sendable, Equatable {
        case removed
        case absent
        case kept
    }

    public struct ArtifactReport: Codable, Sendable, Equatable {
        public var name: String
        public var path: String
        public var disposition: ArtifactDisposition
        public var reason: String?

        public init(name: String, path: String, disposition: ArtifactDisposition, reason: String? = nil) {
            self.name = name
            self.path = path
            self.disposition = disposition
            self.reason = reason
        }
    }

    public struct JSON: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var success: Bool
        public var artifacts: [ArtifactReport]
        public var userDataRetainedPath: String
        public var serveDisableDetail: String?

        public init(
            schemaVersion: Int = 1,
            success: Bool,
            artifacts: [ArtifactReport],
            userDataRetainedPath: String,
            serveDisableDetail: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.success = success
            self.artifacts = artifacts
            self.userDataRetainedPath = userDataRetainedPath
            self.serveDisableDetail = serveDisableDetail
        }
    }

    public struct DisableServeReport: Sendable, Equatable {
        public var succeeded: Bool
        public var detail: String
        public var errorCode: String?

        public init(succeeded: Bool, detail: String, errorCode: String? = nil) {
            self.succeeded = succeeded
            self.detail = detail
            self.errorCode = errorCode
        }
    }

    public struct Request {
        public var json: Bool
        public var yes: Bool
        public var homeDirectory: URL
        public var effectiveHomeDirectory: URL
        public var realHomeDirectory: URL
        public var fileManager: FileManager
        public var disableServe: @Sendable () async -> DisableServeReport
        public var readConfirmation: @Sendable () -> Bool

        public init(
            json: Bool = false,
            yes: Bool = false,
            homeDirectory: URL,
            effectiveHomeDirectory: URL? = nil,
            realHomeDirectory: URL? = nil,
            fileManager: FileManager = .default,
            disableServe: @escaping @Sendable () async -> DisableServeReport,
            readConfirmation: @escaping @Sendable () -> Bool = { false }
        ) {
            self.json = json
            self.yes = yes
            self.homeDirectory = homeDirectory
            self.effectiveHomeDirectory = effectiveHomeDirectory ?? homeDirectory
            self.realHomeDirectory = realHomeDirectory ?? fileManager.homeDirectoryForCurrentUser
            self.fileManager = fileManager
            self.disableServe = disableServe
            self.readConfirmation = readConfirmation
        }
    }

    public enum Outcome: Sendable, Equatable {
        case refused(code: String, message: String)
        case failed(code: String, message: String)
        case completed(JSON)
    }

    // MARK: - Install-derived paths

    public static func launchAgentPlistURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    public static func desiredStateURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Allnighter", isDirectory: true)
            .appendingPathComponent("serve-desired-state.json")
    }

    public static func runtimeReceiptURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Allnighter/Coordinator", isDirectory: true)
            .appendingPathComponent("runtime.json")
    }

    public static func serveLogDirectory(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent("Library/Logs/Allnighter", isDirectory: true)
    }

    public static func userDataRetainedDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Allnighter", isDirectory: true)
    }

    public static func serveLogBasenames() -> [String] {
        ["alln-serve-stdout.log", "alln-serve-stderr.log", "serve.log"]
    }

    // MARK: - Run

    public static func run(_ request: Request) async -> Outcome {
        let effective = canonicalHomePath(request.effectiveHomeDirectory)
        let real = canonicalHomePath(request.realHomeDirectory)
        if effective != real {
            return .refused(
                code: "SERVE_FOREIGN_HOME",
                message: "SERVE_FOREIGN_HOME: refusing uninstall for effective HOME \(effective); the per-user launchd label belongs to real home \(real). Use the real HOME and retry."
            )
        }

        if request.json && !request.yes {
            return .refused(
                code: "CLI_USAGE_ERROR",
                message: "`alln uninstall --json` requires `--yes` — refusing a scripted uninstall without explicit confirmation."
            )
        }

        if !request.yes && !request.readConfirmation() {
            return .refused(
                code: "CLI_USAGE_ERROR",
                message: "uninstall cancelled — pass `--yes` to confirm removal of install-created artifacts."
            )
        }

        let plistURL = launchAgentPlistURL(homeDirectory: request.homeDirectory)
        let plistExisted = request.fileManager.fileExists(atPath: plistURL.path)

        let disableReport = await request.disableServe()
        if !disableReport.succeeded {
            let code = disableReport.errorCode ?? "SERVE_INSTALL_FAILED"
            return .failed(code: code, message: disableReport.detail)
        }

        if request.fileManager.fileExists(atPath: plistURL.path) {
            return .failed(
                code: "SERVE_INSTALL_FAILED",
                message: "\(Self.launchAgentLabel) uninstall refused: LaunchAgent plist still present at \(plistURL.path) after serve disable — bootout did not settle safely; no install artifacts were removed."
            )
        }

        var artifacts: [ArtifactReport] = []
        artifacts.append(plistArtifactReport(
            path: plistURL.path,
            existedBeforeDisable: plistExisted,
            fileManager: request.fileManager
        ))

        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: request.homeDirectory)

        artifacts.append(removePathSymlinkArtifact(
            homeDirectory: request.homeDirectory,
            canonicalURL: canonicalURL,
            fileManager: request.fileManager
        ))

        artifacts.append(removeFileArtifact(
            name: "canonical-binary",
            url: canonicalURL,
            fileManager: request.fileManager
        ))

        artifacts.append(contentsOf: removeResourceBundleArtifacts(
            homeDirectory: request.homeDirectory,
            canonicalURL: canonicalURL,
            fileManager: request.fileManager
        ))

        let rollbackURL = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: request.homeDirectory)
        artifacts.append(removeFileArtifact(
            name: "canonical-rollback",
            url: rollbackURL,
            fileManager: request.fileManager
        ))

        artifacts.append(removeFileArtifact(
            name: "desired-state",
            url: desiredStateURL(homeDirectory: request.homeDirectory),
            fileManager: request.fileManager
        ))

        artifacts.append(removeFileArtifact(
            name: "runtime-receipt",
            url: runtimeReceiptURL(homeDirectory: request.homeDirectory),
            fileManager: request.fileManager
        ))

        artifacts.append(contentsOf: removeServeLogArtifacts(
            homeDirectory: request.homeDirectory,
            fileManager: request.fileManager
        ))

        let retainedPath = userDataRetainedDirectory(homeDirectory: request.homeDirectory).path
        let hadRemovalFailure = artifacts.contains { artifact in
            artifact.disposition == .kept && artifact.reason?.hasPrefix("remove failed:") == true
        }

        let json = JSON(
            success: !hadRemovalFailure,
            artifacts: artifacts,
            userDataRetainedPath: retainedPath,
            serveDisableDetail: disableReport.detail
        )

        if hadRemovalFailure {
            let details = artifacts
                .filter { $0.disposition == .kept && $0.reason?.hasPrefix("remove failed:") == true }
                .map { "\($0.name): \($0.reason ?? "")" }
                .joined(separator: "; ")
            return .failed(code: "SERVE_INSTALL_FAILED", message: "uninstall artifact removal failed: \(details)")
        }

        return .completed(json)
    }

    public static func humanReport(_ json: JSON) -> String {
        var lines: [String] = ["alln uninstall complete."]
        if let detail = json.serveDisableDetail {
            lines.append("serve: \(detail)")
        }
        for artifact in json.artifacts {
            switch artifact.disposition {
            case .removed:
                lines.append("\(artifact.name): removed (\(artifact.path))")
            case .absent:
                lines.append("\(artifact.name): absent (\(artifact.path))")
            case .kept:
                let why = artifact.reason.map { " — \($0)" } ?? ""
                lines.append("\(artifact.name): kept (\(artifact.path))\(why)")
            }
        }
        lines.append("user data retained at \(json.userDataRetainedPath)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func canonicalHomePath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func plistArtifactReport(
        path: String,
        existedBeforeDisable: Bool,
        fileManager: FileManager
    ) -> ArtifactReport {
        ArtifactReport(
            name: "launchagent-plist",
            path: path,
            disposition: existedBeforeDisable ? .removed : .absent
        )
    }

    private static func removeFileArtifact(
        name: String,
        url: URL,
        fileManager: FileManager
    ) -> ArtifactReport {
        let path = url.path
        guard fileManager.fileExists(atPath: path) else {
            return ArtifactReport(name: name, path: path, disposition: .absent)
        }
        do {
            try fileManager.removeItem(at: url)
            return ArtifactReport(name: name, path: path, disposition: .removed)
        } catch {
            return ArtifactReport(
                name: name,
                path: path,
                disposition: .kept,
                reason: "remove failed: \(error.localizedDescription)"
            )
        }
    }

    private static func removePathSymlinkArtifact(
        homeDirectory: URL,
        canonicalURL: URL,
        fileManager: FileManager
    ) -> ArtifactReport {
        let symlinkURL = CanonicalCLIInstall.pathSymlinkURL(homeDirectory: homeDirectory)
        let path = symlinkURL.path
        guard fileManager.fileExists(atPath: path) else {
            return ArtifactReport(name: "path-symlink", path: path, disposition: .absent)
        }

        let canonicalResolved = canonicalURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard let symlinkResolved = resolvedSymlinkTarget(
            at: path,
            installDir: symlinkURL.deletingLastPathComponent().path,
            fileManager: fileManager
        ) else {
            return ArtifactReport(
                name: "path-symlink",
                path: path,
                disposition: .kept,
                reason: "not a symlink Allnighter installed — could not read destination"
            )
        }

        guard InstallCLI.sameExecutable(symlinkResolved, canonicalResolved) else {
            return ArtifactReport(
                name: "path-symlink",
                path: path,
                disposition: .kept,
                reason: "symlink resolves elsewhere (\(symlinkResolved)), not the canonical binary"
            )
        }

        do {
            try fileManager.removeItem(at: symlinkURL)
            return ArtifactReport(name: "path-symlink", path: path, disposition: .removed)
        } catch {
            return ArtifactReport(
                name: "path-symlink",
                path: path,
                disposition: .kept,
                reason: "remove failed: \(error.localizedDescription)"
            )
        }
    }

    private static func removeResourceBundleArtifacts(
        homeDirectory: URL,
        canonicalURL: URL,
        fileManager: FileManager
    ) -> [ArtifactReport] {
        let canonicalDir = canonicalURL.deletingLastPathComponent()
        let pathDir = CanonicalCLIInstall.pathSymlinkURL(homeDirectory: homeDirectory).deletingLastPathComponent()
        var reports: [ArtifactReport] = []
        for name in CLIResourceBundles.requiredNames {
            let pathURL = pathDir.appendingPathComponent(name)
            reports.append(removePathBundleArtifact(
                url: pathURL,
                canonicalDir: canonicalDir,
                fileManager: fileManager
            ))
            reports.append(removeFileArtifact(
                name: "canonical-bundle:\(name)",
                url: canonicalDir.appendingPathComponent(name),
                fileManager: fileManager
            ))
        }
        return reports
    }

    /// Remove a PATH-dir bundle only when it is a symlink into our canonical dir
    /// (never a stranger's similarly named folder).
    private static func removePathBundleArtifact(
        url: URL,
        canonicalDir: URL,
        fileManager: FileManager
    ) -> ArtifactReport {
        let path = url.path
        let name = "path-bundle:\(url.lastPathComponent)"
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return ArtifactReport(name: name, path: path, disposition: .absent)
        }
        if let dest = try? fileManager.destinationOfSymbolicLink(atPath: path) {
            let expanded = (dest as NSString).expandingTildeInPath
            let destURL: URL
            if expanded.hasPrefix("/") {
                destURL = URL(fileURLWithPath: expanded)
            } else {
                destURL = url.deletingLastPathComponent().appendingPathComponent(expanded)
            }
            let destPath = destURL.standardizedFileURL.path
            let canonicalRoot = canonicalDir.standardizedFileURL.path
            if destPath == canonicalRoot || destPath.hasPrefix(canonicalRoot + "/") {
                return removeFileArtifact(name: name, url: url, fileManager: fileManager)
            }
            return ArtifactReport(
                name: name,
                path: path,
                disposition: .kept,
                reason: "symlink resolves elsewhere (\(destPath)), not a canonical CLI bundle"
            )
        }
        return ArtifactReport(
            name: name,
            path: path,
            disposition: .kept,
            reason: "not a symlink Allnighter installed"
        )
    }

    private static func removeServeLogArtifacts(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [ArtifactReport] {
        let logDir = serveLogDirectory(homeDirectory: homeDirectory)
        let basenames = Set(serveLogBasenames())
        guard fileManager.fileExists(atPath: logDir.path) else {
            return [ArtifactReport(
                name: "serve-logs",
                path: logDir.path,
                disposition: .absent
            )]
        }

        guard let entries = try? fileManager.contentsOfDirectory(atPath: logDir.path) else {
            return [ArtifactReport(
                name: "serve-logs",
                path: logDir.path,
                disposition: .kept,
                reason: "could not list serve log directory"
            )]
        }

        let serveFiles = entries.filter { name in
            basenames.contains(where: { name == $0 || name.hasPrefix($0 + ".") })
        }

        if serveFiles.isEmpty {
            return [ArtifactReport(
                name: "serve-logs",
                path: logDir.path,
                disposition: .absent,
                reason: "no serve log files present"
            )]
        }

        return serveFiles.sorted().map { name in
            let fileURL = logDir.appendingPathComponent(name)
            return removeFileArtifact(name: "serve-log:\(name)", url: fileURL, fileManager: fileManager)
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
}
