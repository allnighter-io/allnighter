import Foundation
import AllnighterCore

/// URN-S02 — "dispatch guarantees a live notifier"
/// (`docs/archive/phases/Unattended_Round_Notification.md`). URN-S01 taught `alln
/// serve` to post OS notifications for relay/pilot state, but that is inert
/// for a founder who never remembered to start it. The four `pair` verbs that
/// actually dispatch a real dev turn (`pilot handoff`, `relay`, `relay-resume`,
/// `relay adopt`) call `ensureRunning` before dispatch so a live notifier is
/// guaranteed, silently, by default (founder ruling 2026-07-27 — no
/// confirmation prompt; reversible via `--no-auto-serve` / `ALLN_NO_AUTO_SERVE`).
///
/// Strictly read-then-shell-out: `ServeDaemonProbe` is the ONE liveness check
/// (never a second heuristic like `pgrep`), and a miss spawns a detached `alln
/// serve` of a **CLI** binary. This type never touches `RunService`,
/// `AsyncTeamService`, or `RunWriteLockRegistry` — it is not allowed to
/// mutate a run, only to make sure the notifier exists (architecture-policy
/// inference ban, see the packet's §Inference bans).
///
/// **Never re-exec a macOS `.app` bundle executable.** SC-S03 demand-heal from
/// the Dock app used "same running binary" resolution and spawned
/// `Allnighter.app/…/Allnighter serve`; the GUI `@main` ignores CLI verbs,
/// paints another Dock icon, and demand-heals again — an infinite fork bomb
/// (`docs/operations/debugger/2026-08-10-mac-serve-fork-bomb-PACKET.md`).
public enum ServeAutoLaunch {
    public enum Outcome: String, Sendable, Equatable {
        case alreadyRunning
        case launched
        case skipped
        case failed
    }

    public struct LaunchResult: Sendable, Equatable {
        public let outcome: Outcome
        public let pid: Int32?

        public init(outcome: Outcome, pid: Int32? = nil) {
            self.outcome = outcome
            self.pid = pid
        }
    }

    /// Opt-out union: an explicit `--no-auto-serve` flag (parsed by the CLI
    /// caller) OR `ALLN_NO_AUTO_SERVE` set to any non-empty value. Either one
    /// suppresses auto-launch; this is the single place both are checked.
    public static func isOptedOut(
        flag: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if flag { return true }
        if let value = environment["ALLN_NO_AUTO_SERVE"], !value.isEmpty { return true }
        return false
    }

    /// True when argv is a detached `serve` invocation. The Dock app must never
    /// honor this — it is not the CLI and must not demand-heal-spawn itself.
    public static func isServeArgv(_ arguments: [String] = CommandLine.arguments) -> Bool {
        Array(arguments.dropFirst()).first == "serve"
    }

    /// Fail-closed guard: paths under `Something.app/Contents/MacOS/` are Dock
    /// (or helper) app binaries, not the `alln` CLI. Re-execing them as `serve`
    /// creates another GUI process.
    public static func isMacAppBundleExecutable(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        return normalized.range(of: ".app/Contents/MacOS/", options: .caseInsensitive) != nil
    }

    /// Resolve a **CLI** binary that can run `serve`. Order:
    /// 1. current executable when it is not an `.app/Contents/MacOS/` path
    /// 2. staged `ServeStableBinary` (`…/Application Support/Allnighter/CLI/alln`)
    /// 3. `alln` on PATH
    /// 4. argv0 resolution when that path is also not an app-bundle executable
    ///
    /// Returns `nil` rather than an app-bundle path — fail closed.
    public static func resolveServeExecutablePath(
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath,
        stagedBinaryPath: () -> String? = {
            let path = ServeStableBinary.defaultDestinationURL().path
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        },
        resolveOnPath: (String, String?) -> String? = { command, pathEnv in
            InstallCLI.resolveOnPath(command: command, pathEnvironment: pathEnv)
        },
        resolveArgv0: (String?, String?) -> String? = { argv0, pathEnv in
            InstallCLI.resolvedRunningBinary(argv0: argv0, pathEnvironment: pathEnv)
        }
    ) -> String? {
        if let current = currentExecutablePath(), !isMacAppBundleExecutable(current) {
            return current
        }
        if let staged = stagedBinaryPath(), !isMacAppBundleExecutable(staged) {
            return staged
        }
        if let onPath = resolveOnPath(InstallCLI.symlinkName, pathEnvironment),
           !isMacAppBundleExecutable(onPath) {
            return onPath
        }
        if let fromArgv = resolveArgv0(argv0, pathEnvironment),
           !isMacAppBundleExecutable(fromArgv) {
            return fromArgv
        }
        return nil
    }

    /// Guarantees a live `alln serve` daemon exists, launching a detached one
    /// if the probe reports anything other than `.available` (both
    /// `.foregroundOnly` — no record — and `.unavailable` — a stale record
    /// with a dead pid — mean "launch a daemon").
    ///
    /// **Never fails the round.** This function never throws. A resolution or
    /// spawn failure is logged to stderr (one line) and reported back as
    /// `.failed` — callers must not let that outcome change their own exit
    /// code or JSON envelope (see the packet's §Inference bans: "a failed
    /// notifier launch means the round failed" is a banned inference).
    ///
    /// Executable resolution is `resolveServeExecutablePath` — CLI-only, never
    /// a macOS app-bundle executable. Working directory is irrelevant to
    /// `serve`, so the detached child's cwd is the user's home.
    @discardableResult
    public static func ensureRunning(
        optedOut: Bool,
        probe: ServeDaemonProbe = ServeDaemonProbe(),
        binaryVersion: String = AllnighterVersionIdentity.binaryVersion,
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath,
        stagedBinaryPath: (() -> String?)? = nil,
        resolveOnPath: ((String, String?) -> String?)? = nil,
        resolveArgv0: ((String?, String?) -> String?)? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        launch: (URL, URL) throws -> Int32 = defaultLaunch
    ) -> LaunchResult {
        if optedOut { return LaunchResult(outcome: .skipped) }

        let state = probe.health(binaryVersion: binaryVersion).state
        if state == .available { return LaunchResult(outcome: .alreadyRunning) }

        let executablePath = resolveServeExecutablePath(
            argv0: argv0,
            pathEnvironment: pathEnvironment,
            currentExecutablePath: currentExecutablePath,
            stagedBinaryPath: stagedBinaryPath ?? {
                let path = ServeStableBinary.defaultDestinationURL().path
                return FileManager.default.isExecutableFile(atPath: path) ? path : nil
            },
            resolveOnPath: resolveOnPath ?? { command, pathEnv in
                InstallCLI.resolveOnPath(command: command, pathEnvironment: pathEnv)
            },
            resolveArgv0: resolveArgv0 ?? { argv0, pathEnv in
                InstallCLI.resolvedRunningBinary(argv0: argv0, pathEnvironment: pathEnv)
            }
        )
        guard let executablePath else {
            FileHandle.standardError.write(Data(
                "alln serve auto-launch: could not resolve a CLI binary (refusing macOS .app re-exec)\n".utf8
            ))
            return LaunchResult(outcome: .failed)
        }
        // Defense in depth — resolver already filters; never launch an .app path.
        if isMacAppBundleExecutable(executablePath) {
            FileHandle.standardError.write(Data(
                "alln serve auto-launch: refused macOS app-bundle executable \(executablePath)\n".utf8
            ))
            return LaunchResult(outcome: .failed)
        }

        do {
            let pid = try launch(URL(fileURLWithPath: executablePath), homeDirectory)
            return LaunchResult(outcome: .launched, pid: pid)
        } catch {
            FileHandle.standardError.write(Data(
                "alln serve auto-launch failed: \(error)\n".utf8
            ))
            return LaunchResult(outcome: .failed)
        }
    }

    /// Spawns `<executable> serve` fully detached (null stdio) — the same
    /// shape `PilotCLI.dispatchHandoffInBackground` uses for its own re-exec.
    /// `public` only because it is the default value of a public parameter;
    /// not intended to be called directly outside `ensureRunning`.
    public static func defaultLaunch(executableURL: URL, currentDirectoryURL: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = currentDirectoryURL
        process.arguments = ["serve"]
        process.environment = AllnighterSpawnEnvironmentPolicy.processEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }
}
