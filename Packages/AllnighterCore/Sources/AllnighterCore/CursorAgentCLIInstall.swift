import Foundation
import AgentOSCLI

/// One-click install of Cursor's headless Agent CLI (`cursor-agent` / `agent`).
///
/// The Cursor **app** is not the seat — Alln needs this separate CLI. When the
/// app is already on the Mac, setup should offer install as the primary fix,
/// not a docs dump. Official installer: `https://cursor.com/install`.
public enum CursorAgentCLIInstall {
    public static let driverId = "cursor_agent"
    public static let installPageURL = "https://cursor.com/docs/cli/installation"
    /// Cursor's documented one-liner (also what `cursor.com/install` serves).
    public static let shellCommand = "curl https://cursor.com/install -fsS | bash"
    public static let defaultAppBundlePath = "/Applications/Cursor.app"

    /// True when the Cursor macOS app bundle is present (IDE ≠ Agent CLI).
    public static func isCursorAppInstalled(
        fileManager: FileManager = .default,
        appBundlePath: String = defaultAppBundlePath
    ) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: appBundlePath, isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue
    }

    /// Stable launcher the installer creates (preferred over ambiguous `agent`).
    public static func launcherPath(home: String = NSHomeDirectory()) -> String {
        (home as NSString).appendingPathComponent(".local/bin/cursor-agent")
    }

    public static func isLauncherPresent(
        home: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        let path = launcherPath(home: home)
        return fileManager.isExecutableFile(atPath: path)
            || fileManager.fileExists(atPath: path)
    }

    /// When Cursor.app is on the Mac but the Agent CLI is missing (or never checked),
    /// setup must surface an install prompt — not hide the seat as a catalog absence.
    public static func shouldPromptInstall(
        cliAbsentOrUnchecked: Bool,
        cursorAppPresent: Bool? = nil
    ) -> Bool {
        guard cliAbsentOrUnchecked else { return false }
        return cursorAppPresent ?? isCursorAppInstalled()
    }

    public struct Outcome: Sendable, Equatable {
        public var succeeded: Bool
        public var detail: String
        public var launcherPath: String?

        public init(succeeded: Bool, detail: String, launcherPath: String? = nil) {
            self.succeeded = succeeded
            self.detail = detail
            self.launcherPath = launcherPath
        }
    }

    /// Runs Cursor's official installer, then confirms `~/.local/bin/cursor-agent`.
    public static func run(
        commandRunner: CommandRunner,
        home: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        timeout: Duration = .seconds(180)
    ) async -> Outcome {
        let result = await commandRunner.run(
            command: "/bin/bash",
            args: ["-lc", shellCommand],
            stdin: nil,
            env: ["HOME": home, "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"],
            workingDirectory: home,
            timeout: timeout
        )
        if let launchError = result.launchError, !launchError.isEmpty {
            return Outcome(succeeded: false, detail: "Could not start installer: \(launchError)")
        }
        if result.timedOut {
            return Outcome(succeeded: false, detail: "Cursor Agent CLI install timed out.")
        }
        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = [err, out].first { !$0.isEmpty }.map { String($0.prefix(200)) } ?? "exit \(result.exitCode ?? -1)"
            return Outcome(succeeded: false, detail: "Installer failed: \(clipped)")
        }
        let path = launcherPath(home: home)
        guard isLauncherPresent(home: home, fileManager: fileManager) else {
            return Outcome(
                succeeded: false,
                detail: "Installer finished but cursor-agent was not found at \(path). Add ~/.local/bin to PATH and Re-check."
            )
        }
        return Outcome(
            succeeded: true,
            detail: "Cursor Agent CLI installed at \(path).",
            launcherPath: path
        )
    }
}
