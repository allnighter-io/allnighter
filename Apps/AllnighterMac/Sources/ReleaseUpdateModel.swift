import Foundation
import AllnighterCore

/// OPC-S06b — Mac About/status projection of the shared release channel.
///
/// One owner for truth: `ReleaseChannel` (same cache as CLI `menu.update`).
/// This model only projects for humans: quiet badge + About page. Never a
/// second "latest version" constant, never auto-apply.
@MainActor
@Observable
final class ReleaseUpdateModel {
    /// App update when running appVersion < latest.appVersion.
    private(set) var appUpdate: ReleaseAppUpdateInfo?
    /// CLI update when binary identity is behind latest.cliVersion (informational).
    private(set) var cliUpdate: ReleaseUpdateInfo?
    /// Absolute path of cold-start standalone home (`~/.local/share/allnighter/bin/alln`).
    private(set) var standaloneHomePath: String = ""
    /// What `command -v alln` would resolve to (first PATH hit), if any.
    private(set) var resolvedPathAlln: String?
    /// True when PATH resolves somewhere that is not the standalone home.
    private(set) var pathConflict: Bool = false
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking: Bool = false

    /// Marketing version of the running Mac app (CFBundleShortVersionString).
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var hasAnyUpdate: Bool {
        appUpdate != nil || cliUpdate != nil
    }

    /// Quiet title-bar badge copy — empty when up to date / check skipped.
    var badgeText: String? {
        if appUpdate != nil { return "update" }
        if cliUpdate != nil { return "cli update" }
        return nil
    }

    init() {
        standaloneHomePath = ReleaseChannel.standaloneBinaryPath()
    }

    /// Load from cache (or network on miss). Fail-open: never throws.
    func refresh(force: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let env = ProcessInfo.processInfo.environment
        let now = Date()
        // One cache read/refresh for both surfaces.
        let manifest = ReleaseChannel.loadManifest(
            now: now,
            environment: env,
            forceRefresh: force
        )
        if let manifest {
            appUpdate = ReleaseChannel.announceApp(
                manifest: manifest,
                currentVersion: appVersion
            )
            cliUpdate = ReleaseChannel.announce(
                manifest: manifest,
                currentVersion: AllnighterVersionIdentity.binaryVersion,
                binaryPath: resolvedPathAlln
            )
        } else {
            appUpdate = nil
            cliUpdate = nil
        }

        refreshPathResolution()
        // Re-attach binaryPath after PATH resolve so agents/humans see conflict context.
        if let cli = cliUpdate {
            cliUpdate = ReleaseUpdateInfo(
                available: cli.available,
                current: cli.current,
                latest: cli.latest,
                binaryPath: resolvedPathAlln ?? cli.binaryPath,
                command: cli.command
            )
        }
        lastCheckedAt = now
    }

    private func refreshPathResolution() {
        standaloneHomePath = ReleaseChannel.standaloneBinaryPath()
        let pathEnv = ProcessInfo.processInfo.environment["PATH"]
        resolvedPathAlln = InstallCLI.resolveOnPath(
            command: "alln",
            pathEnvironment: pathEnv,
            fileManager: .default
        )
        if let resolved = resolvedPathAlln {
            let homeResolved = (standaloneHomePath as NSString).resolvingSymlinksInPath
            let pathResolved = (resolved as NSString).resolvingSymlinksInPath
            pathConflict = pathResolved != homeResolved
                && !InstallCLI.sameExecutable(resolved, standaloneHomePath)
        } else {
            pathConflict = false
        }
    }
}
