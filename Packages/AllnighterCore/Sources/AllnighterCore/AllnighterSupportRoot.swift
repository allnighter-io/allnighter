import Foundation

/// Core-owned support-dir resolution (mirrors `AllnighterEngine.AllnighterPaths.support`).
/// Catalog + roster persistence in Core must honor `ALLNIGHTER_SUPPORT_DIR` the same
/// way engine stores do — otherwise isolated config homes split roster state.
///
/// Engine's `AllnighterPaths.support` delegates here so there is one resolver.
public enum AllnighterSupportRoot {
    /// When the process-wide XCTest redirect is active, the temp root it chose.
    /// `nil` in the shipped app / installed `alln`. Inspectable so a debugger
    /// never has to guess which store they are reading.
    public static var activeTestSupportRoot: URL? { testSupportRoot }

    /// True when this process is an XCTest (or wrapper) host that must not
    /// touch the real Application Support tree. See `isRunningUnderTestHost`.
    public static var isTestSupportRedirectActive: Bool { testSupportRoot != nil }

    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }

        if let testRoot = testSupportRoot {
            return testRoot
        }

        // There is ONE durable state root for production hosts. A restricted host
        // (e.g. Codex, whose sandbox denies writes outside its workspace) used to
        // be redirected here to a per-thread temp tree, which silently gave that
        // host a different product: no projects, no teams, no runs. That is an
        // alternate state root — the same forbidden shape as a project mirror,
        // one layer down — and it is the most plausible seed of the Code Red
        // incident. A host that cannot write this root must fail honestly
        // (RUN_JOURNAL_UNAVAILABLE) and be granted access, never be handed a
        // parallel world. See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
        //
        // The XCTest redirect above is deliberate and opposite: test processes
        // must be physically unable to write the developer's real bench. It is
        // gated by `isRunningUnderTestHost`, which is false for the shipped app
        // and installed `alln`.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter", isDirectory: true)
    }

    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }

    /// `…/Allnighter/Release/` — OPC-S06 release-channel cache (mirrors Engine path).
    public static var release: URL {
        support.appendingPathComponent("Release", isDirectory: true)
    }

    // MARK: - Test / real-state seam

    /// Detection signal for the support-root redirect.
    ///
    /// **Primary signal:** a loaded bundle whose path contains `.xctest`.
    /// Empirical (2026-08-12):
    /// - `scripts/swift-test.sh` / SwiftPM XCTest: loads `AllnighterCorePackageTests.xctest`
    /// - `xcodebuild test` / Mac host: loads `AllnighterMacTests.xctest`
    /// - shipped `Allnighter.app` and installed `alln`: do not load any `.xctest` bundle
    ///
    /// **Why not `XCTestConfigurationFilePath` alone** (the suggested primary):
    /// unset under SwiftPM XCTest; present-but-empty under Mac XCTest. Key
    /// presence covers Mac only.
    ///
    /// **Why not `ALLNIGHTER_TEST_TOKEN`:** `scripts/check.sh` and
    /// `scripts/swift-test.sh` mint and export it, then invoke the real installed
    /// `alln` binary (install-cli, serve, etc.). A developer may also have it in
    /// their shell. Empirical (2026-08-12, freshly built `alln`):
    /// - `alln menu --json` → `ready` 5, `notInstalled` 3 (correct)
    /// - `ALLNIGHTER_TEST_TOKEN=abc123 alln menu --json` → headline
    ///   `neverScanned`, `measured` 0, `needsCheck` 9 (parallel empty root)
    /// That is the CODE_RED forbidden shape: production CLI silently handed a
    /// parallel world. Deliberately NOT a signal.
    ///
    /// Belts (any one also trips): `XCTestConfigurationFilePath` key present,
    /// `XCTestSessionIdentifier`, `XCTestBundlePath` containing `.xctest`,
    /// `argv0` ending in `xctest`.
    /// Deliberately omitted: `SWIFT_TESTING_ENABLED` (an end user could set it).
    public static var isRunningUnderTestHost: Bool {
        let bundles = Bundle.allBundles + Bundle.allFrameworks
        if bundles.contains(where: {
            $0.bundlePath.localizedCaseInsensitiveContains(".xctest")
        }) {
            return true
        }

        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        if let bundlePath = env["XCTestBundlePath"],
           bundlePath.localizedCaseInsensitiveContains(".xctest") {
            return true
        }
        if let argv0 = ProcessInfo.processInfo.arguments.first,
           argv0.hasSuffix("xctest") {
            return true
        }
        return false
    }

    /// Per-process temp root, created once on first need. `nil` outside test hosts.
    private static let testSupportRoot: URL? = {
        guard isRunningUnderTestHost else { return nil }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "allnighter-test-support-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Loud, not silent: one line so a future debugger never confuses the
        // redirected store with ~/Library/Application Support/Allnighter/.
        fputs(
            "allnighter: XCTest host — support root redirected to \(root.path) (real Application Support unreachable)\n",
            stderr
        )
        fflush(stderr)
        return root
    }()
}
