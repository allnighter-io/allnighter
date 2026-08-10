import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// URN-S02 — "dispatch guarantees a live notifier"
/// (`docs/archive/phases/Unattended_Round_Notification.md`). `ServeAutoLaunch` is the
/// read-then-shell-out guarantee the four `pair` dispatch verbs call before
/// starting a real dev turn: `ServeDaemonProbe` is the single liveness check,
/// a miss spawns a detached `alln serve`, and a launch failure is swallowed
/// (never allowed to change the caller's exit code).
final class ServeAutoLaunchTests: XCTestCase {

    private func tempDirs() -> (root: URL, store: ServeDaemonStore, probe: ServeDaemonProbe) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("serve-autolaunch-\(UUID().uuidString)")
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let runsDir = root.appendingPathComponent("Runs", isDirectory: true)
        let store = ServeDaemonStore(directory: coordDir)
        let probe = ServeDaemonProbe(store: store, runsDirectory: runsDir)
        return (root, store, probe)
    }

    private func removeIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - isOptedOut

    func testIsOptedOutFlagTrue() {
        XCTAssertTrue(ServeAutoLaunch.isOptedOut(flag: true, environment: [:]))
    }

    func testIsOptedOutEnvNonEmptySuppresses() {
        XCTAssertTrue(ServeAutoLaunch.isOptedOut(flag: false, environment: ["ALLN_NO_AUTO_SERVE": "1"]))
    }

    func testIsOptedOutNeitherPresentReturnsFalse() {
        XCTAssertFalse(ServeAutoLaunch.isOptedOut(flag: false, environment: [:]))
    }

    func testIsOptedOutEnvEmptyStringDoesNotSuppress() {
        // "any non-empty value" opts out; an accidentally-empty env var must
        // not silently suppress auto-launch.
        XCTAssertFalse(ServeAutoLaunch.isOptedOut(flag: false, environment: ["ALLN_NO_AUTO_SERVE": ""]))
    }

    // MARK: - ensureRunning: opt-out

    func testEnsureRunningOptedOutSkipsWithZeroLaunches() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchCount = 0

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: true,
            probe: probe,
            binaryVersion: "0.1.0",
            currentExecutablePath: { "/bin/alln" },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; return 1 }
        )

        XCTAssertEqual(result.outcome, .skipped)
        XCTAssertNil(result.pid)
        XCTAssertEqual(launchCount, 0)
    }

    // MARK: - ensureRunning: liveness

    func testEnsureRunningNoDaemonRecordLaunchesExactlyOnce() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchCount = 0

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            currentExecutablePath: { "/bin/alln" },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; return 4242 }
        )

        XCTAssertEqual(result.outcome, .launched)
        XCTAssertEqual(result.pid, 4242)
        XCTAssertEqual(launchCount, 1)
    }

    func testEnsureRunningStaleDaemonRecordLaunchesExactlyOnce() throws {
        let (root, store, probe) = tempDirs()
        defer { removeIfPresent(root) }
        try store.save(.init(
            daemonId: "stale", pid: 2_000_000, startedAt: Date(),
            loopbackHost: "127.0.0.1", loopbackPort: 18743,
            binaryVersion: "0.1.0", contractVersion: "1.0.0"
        ))
        var launchCount = 0

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            currentExecutablePath: { "/bin/alln" },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; return 4242 }
        )

        XCTAssertEqual(result.outcome, .launched)
        XCTAssertEqual(launchCount, 1)
    }

    func testEnsureRunningLiveDaemonSkipsLaunch() throws {
        let (root, store, probe) = tempDirs()
        defer { removeIfPresent(root) }
        try store.save(.init(
            daemonId: "live", pid: ProcessInfo.processInfo.processIdentifier, startedAt: Date(),
            loopbackHost: "127.0.0.1", loopbackPort: 18743,
            binaryVersion: "0.1.0", contractVersion: "1.0.0"
        ))
        var launchCount = 0

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            currentExecutablePath: { "/bin/alln" },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; return 4242 }
        )

        XCTAssertEqual(result.outcome, .alreadyRunning)
        XCTAssertNil(result.pid)
        XCTAssertEqual(launchCount, 0)
    }

    // MARK: - never fails the round

    func testEnsureRunningThrowingLauncherReturnsFailedWithoutThrowing() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        struct BoomError: Error {}
        var launchCount = 0

        // The function signature itself is non-throwing — a launcher that
        // throws cannot propagate to the caller by construction. This proves
        // the "never fails the round" guarantee directly, not by inspection.
        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            currentExecutablePath: { "/bin/alln" },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; throw BoomError() }
        )

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertNil(result.pid)
        XCTAssertEqual(launchCount, 1)
    }

    func testEnsureRunningUnresolvedExecutableReturnsFailedWithoutLaunching() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchCount = 0

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            argv0: "alln",
            pathEnvironment: nil,
            currentExecutablePath: { nil },
            stagedBinaryPath: { nil },
            resolveOnPath: { _, _ in nil },
            resolveArgv0: { _, _ in nil },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; return 1 }
        )

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(launchCount, 0, "an unresolved executable must never invoke the launcher")
    }

    // MARK: - SC-S03 demand heal: `alln run` dispatch wiring

    private func runCLISource() throws -> String {
        // #filePath = .../Packages/AllnighterCore/Tests/AllnighterEngineTests/<this>.swift
        let here = URL(fileURLWithPath: #filePath)
        let packageRoot = here.deletingLastPathComponent()   // AllnighterEngineTests
            .deletingLastPathComponent()                     // Tests
            .deletingLastPathComponent()                     // AllnighterCore
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/AllnighterCLI/RunCLI.swift"),
            encoding: .utf8
        )
    }

    /// SC-S03: `alln run` (the default mutating dispatch) must attempt
    /// `ensureRunning` — after the dry-run soft path returns (a dry run
    /// dispatches nothing) and before any real `service.run(` dispatch. The
    /// opt-outs are delegated to ServeAutoLaunchCLI; this locks the call site.
    func testRunCLIDispatchEnsuresServeBeforeWork() throws {
        let source = try runCLISource()
        guard let heal = source.range(of: "ServeAutoLaunchCLI.ensureRunning(opts)") else {
            return XCTFail("alln run must call ServeAutoLaunchCLI.ensureRunning (SC-S03 demand heal)")
        }
        guard let dryRun = source.range(of: #"opts.flag("dry-run")"#) else {
            return XCTFail("RunCLI dry-run gate not found — recheck the heal placement")
        }
        guard let dispatch = source.range(of: "service.run(") else {
            return XCTFail("RunCLI dispatch site not found — recheck the heal placement")
        }
        XCTAssertLessThan(
            dryRun.lowerBound, heal.lowerBound,
            "a dry run dispatches nothing — the heal belongs after the dry-run early return")
        XCTAssertLessThan(
            heal.lowerBound, dispatch.lowerBound,
            "the heal must run before the run starts dispatching work")
    }

    // MARK: - executable resolution order (mirrors PilotCLI.detachedHandoffLaunch)

    func testEnsureRunningPrefersCurrentExecutablePathOverPathFallback() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchedURL: URL?

        _ = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            argv0: "alln",
            pathEnvironment: "/should/not/be/searched",
            currentExecutablePath: { "/usr/local/bin/alln-real" },
            homeDirectory: root,
            launch: { url, _ in launchedURL = url; return 1 }
        )

        XCTAssertEqual(launchedURL?.path, "/usr/local/bin/alln-real")
    }

    func testEnsureRunningUsesHomeDirectoryAsWorkingDirectory() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchedCwd: URL?

        _ = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            currentExecutablePath: { "/bin/alln" },
            homeDirectory: root,
            launch: { _, cwd in launchedCwd = cwd; return 1 }
        )

        XCTAssertEqual(launchedCwd, root)
    }

    // MARK: - macOS .app re-exec refuse (2026-08-10 fork bomb)

    func testIsMacAppBundleExecutableDetectsContentsMacOS() {
        XCTAssertTrue(ServeAutoLaunch.isMacAppBundleExecutable(
            "/Users/x/Build/Products/Debug/Allnighter.app/Contents/MacOS/Allnighter"))
        XCTAssertTrue(ServeAutoLaunch.isMacAppBundleExecutable(
            "/Applications/Allnighter.app/Contents/MacOS/Allnighter"))
        XCTAssertFalse(ServeAutoLaunch.isMacAppBundleExecutable("/usr/local/bin/alln"))
        XCTAssertFalse(ServeAutoLaunch.isMacAppBundleExecutable(
            "/Users/x/Library/Application Support/Allnighter/CLI/alln"))
    }

    func testIsServeArgvDetectsDetachedServe() {
        XCTAssertTrue(ServeAutoLaunch.isServeArgv(["/path/Allnighter", "serve"]))
        XCTAssertTrue(ServeAutoLaunch.isServeArgv(["alln", "serve", "--health"]))
        XCTAssertFalse(ServeAutoLaunch.isServeArgv(["/path/Allnighter"]))
        XCTAssertFalse(ServeAutoLaunch.isServeArgv(["alln", "run", "hi"]))
    }

    func testEnsureRunningRefusesMacAppBundleExecutableWithoutLaunching() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchCount = 0

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            argv0: "alln",
            pathEnvironment: nil,
            currentExecutablePath: {
                "/Users/x/Build/Products/Debug/Allnighter.app/Contents/MacOS/Allnighter"
            },
            stagedBinaryPath: { nil },
            homeDirectory: root,
            launch: { _, _ in launchCount += 1; return 1 }
        )

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(launchCount, 0, "must never spawn Allnighter.app as serve")
    }

    func testEnsureRunningSkipsAppBundleAndUsesStagedCLI() {
        let (root, _, probe) = tempDirs()
        defer { removeIfPresent(root) }
        var launchedURL: URL?

        let result = ServeAutoLaunch.ensureRunning(
            optedOut: false,
            probe: probe,
            binaryVersion: "0.1.0",
            argv0: "alln",
            pathEnvironment: nil,
            currentExecutablePath: {
                "/Users/x/Build/Products/Debug/Allnighter.app/Contents/MacOS/Allnighter"
            },
            stagedBinaryPath: { "/tmp/Allnighter/CLI/alln" },
            homeDirectory: root,
            launch: { url, _ in launchedURL = url; return 99 }
        )

        XCTAssertEqual(result.outcome, .launched)
        XCTAssertEqual(result.pid, 99)
        XCTAssertEqual(launchedURL?.path, "/tmp/Allnighter/CLI/alln")
    }

    /// Mac Dock app must not call ServeAutoLaunch.ensureRunning (TCC + fork bomb),
    /// and must circuit-break argv `serve` before activating as another Dock icon.
    func testMacAppLaunchDoesNotDemandHealServe() throws {
        let here = URL(fileURLWithPath: #filePath)
        // …/Packages/AllnighterCore/Tests/AllnighterEngineTests → repo root
        let repoRoot = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let macApp = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Apps/AllnighterMac/Sources/AllnighterMacApp.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            macApp.contains("ServeAutoLaunch.ensureRunning"),
            "Dock app must not demand-heal-spawn serve (fork bomb + TCC identity)"
        )
        XCTAssertTrue(
            macApp.contains("ServeAutoLaunch.isServeArgv"),
            "Dock app must circuit-break argv `serve` before activating"
        )
        XCTAssertTrue(
            macApp.contains("CapacityResidentService.shared.setEnabled"),
            "capacity re-arm on launch remains; it must stay process-quiet"
        )
    }
}
