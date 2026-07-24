import Foundation
import AllnighterCore
#if canImport(Darwin)
import Darwin
#endif

/// Explicit user-level launchd registration for the resident execution owner.
/// Clients never call this implicitly: invoking `alln serve install` is the
/// user's consent to keep their already-installed Allnighter binary available
/// outside short-lived host-agent sandboxes.
public enum ResidentCoordinatorInstall {
    public static let label = "com.allnighter.resident-coordinator"

    public struct Result: Codable, Equatable, Sendable {
        public var schemaVersion: Int = 1
        public var action: String
        public var label: String
        public var plistPath: String
        public var binaryPath: String
        public var enabled: Bool
        public var coordinatorId: String?
        public var pid: Int32?

        public init(
            action: String,
            label: String,
            plistPath: String,
            binaryPath: String,
            enabled: Bool,
            coordinatorId: String? = nil,
            pid: Int32? = nil
        ) {
            self.action = action
            self.label = label
            self.plistPath = plistPath
            self.binaryPath = binaryPath
            self.enabled = enabled
            self.coordinatorId = coordinatorId
            self.pid = pid
        }
    }

    public enum InstallError: Error, Equatable, Sendable {
        case binaryUnresolved
        case plistWrite(String)
        case launchctl(String)
        case activeWork(Int)
        case activationTimeout

        public var message: String {
            switch self {
            case .binaryUnresolved:
                return "could not resolve the running alln binary; invoke it by absolute path, then retry"
            case .plistWrite(let detail): return "could not write the resident coordinator LaunchAgent: \(detail)"
            case .launchctl(let detail): return "could not enable the resident coordinator: \(detail)"
            case .activeWork(let count):
                return "the resident coordinator has \(count) active work item\(count == 1 ? "" : "s"); it was not restarted"
            case .activationTimeout:
                return "launchd accepted the coordinator but it did not publish the current binary identity before the activation deadline"
            }
        }
    }

    public enum LaunchctlOutcome: Sendable, Equatable {
        case success
        case failure(String)
    }

    public static func plistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func isInstalled(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: plistURL(home: home).path)
    }

    public static func plistData(binaryPath: String, pathEnvironment: String? = nil) throws -> Data {
        var payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryPath, "serve"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
        ]
        // launchd does not inherit an interactive shell's PATH. Preserve the
        // installer's executable search path so the resident can locate the
        // already-configured vendor CLIs without per-source workarounds.
        if let pathEnvironment, !pathEnvironment.isEmpty {
            payload["EnvironmentVariables"] = ["PATH": pathEnvironment]
        }
        return try PropertyListSerialization.data(
            fromPropertyList: payload, format: .xml, options: 0
        )
    }

    public static func install(
        argv0: String?,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        launchctl: (@Sendable (_ arguments: [String]) -> LaunchctlOutcome)? = nil,
        currentHealth: (@Sendable () -> CoordinatorHealth)? = nil,
        pause: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        activationAttempts: Int = 50
    ) -> Swift.Result<Result, InstallError> {
        guard let binary = stableRunningBinary(
            argv0: argv0, pathEnvironment: pathEnvironment, fileManager: fileManager
        ) else { return .failure(.binaryUnresolved) }
        let launchctl = launchctl ?? runLaunchctl
        let plist = plistURL(home: home)
        do {
            try fileManager.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plistData(binaryPath: binary, pathEnvironment: pathEnvironment).write(to: plist, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plist.path)
        } catch {
            return .failure(.plistWrite(error.localizedDescription))
        }

        let health = currentHealth ?? {
            ResidentCoordinatorProbe().health(
                binaryVersion: AllnighterVersionIdentity.binaryVersion,
                contractVersion: ContractRegistry.contractVersion
            )
        }
        let beforeRestart = health()
        if beforeRestart.state == .available, beforeRestart.activeObligationCount > 0 {
            return .failure(.activeWork(beforeRestart.activeObligationCount))
        }

        let domain = "gui/\(getuid())"
        // A reinstall replaces a previous registration of this exact label. The
        // best-effort bootout is intentionally scoped to our own plist only.
        _ = launchctl(["bootout", domain, plist.path])
        switch launchctl(["bootstrap", domain, plist.path]) {
        case .success:
            for attempt in 0..<max(1, activationAttempts) {
                let activated = health()
                if activated.state == .available,
                   activated.binaryVersion == AllnighterVersionIdentity.binaryVersion,
                   activated.contractVersion == ContractRegistry.contractVersion,
                   let coordinatorId = activated.coordinatorId,
                   let pid = activated.pid {
                    return .success(.init(
                        action: "installed",
                        label: label,
                        plistPath: plist.path,
                        binaryPath: binary,
                        enabled: true,
                        coordinatorId: coordinatorId,
                        pid: pid
                    ))
                }
                if attempt + 1 < max(1, activationAttempts) { pause(0.1) }
            }
            return .failure(.activationTimeout)
        case .failure(let detail):
            return .failure(.launchctl(detail))
        }
    }

    /// Use the non-resolved installed command path when available. A LaunchAgent
    /// that runs the `alln` symlink picks up the next `alln install-cli` rebuild
    /// instead of pinning an old `.build/.../alln` image forever.
    public static func stableRunningBinary(
        argv0: String?,
        pathEnvironment: String?,
        fileManager: FileManager = .default
    ) -> String? {
        guard let raw = argv0, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return fileManager.fileExists(atPath: expanded)
                ? URL(fileURLWithPath: expanded).standardizedFileURL.path
                : nil
        }
        if expanded.contains("/") {
            let candidate = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(expanded).standardizedFileURL.path
            return fileManager.fileExists(atPath: candidate) ? candidate : nil
        }
        guard let pathEnvironment else { return nil }
        for component in pathEnvironment.split(separator: ":", omittingEmptySubsequences: false) {
            guard !component.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: String(component)).appendingPathComponent(expanded).path
            if fileManager.fileExists(atPath: candidate), fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func runLaunchctl(arguments: [String]) -> LaunchctlOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do { try process.run() } catch { return .failure(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "launchctl exited \(process.terminationStatus)"
            return .failure(detail)
        }
        return .success
    }
}
