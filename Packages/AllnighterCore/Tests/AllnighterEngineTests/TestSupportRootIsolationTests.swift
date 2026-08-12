import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Behavioral guard: an XCTest process must never resolve the real user
/// Application Support tree. The seam is `AllnighterSupportRoot` /
/// `AllnighterPaths` — not call-site injection.
final class TestSupportRootIsolationTests: XCTestCase {
    private var previousSupportDir: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousSupportDir = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"]
        // Clear explicit override so we exercise the automatic test redirect,
        // not a per-test hermetic ALLNIGHTER_SUPPORT_DIR.
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
    }

    override func tearDownWithError() throws {
        if let previousSupportDir {
            setenv("ALLNIGHTER_SUPPORT_DIR", previousSupportDir, 1)
        } else {
            unsetenv("ALLNIGHTER_SUPPORT_DIR")
        }
        previousSupportDir = nil
        try super.tearDownWithError()
    }

    func testResolvedSupportRootIsNotRealUserLocationUnderTest() throws {
        XCTAssertTrue(
            AllnighterSupportRoot.isRunningUnderTestHost,
            "this test must run under an XCTest host"
        )

        let real = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ).appendingPathComponent("Allnighter", isDirectory: true)
        let realPath = real.standardizedFileURL.path

        let engine = AllnighterPaths.support.standardizedFileURL
        let core = AllnighterSupportRoot.support.standardizedFileURL

        XCTAssertEqual(engine, core, "Core and Engine must share one redirected root")
        XCTAssertNotEqual(
            engine.path, realPath,
            "XCTest must not resolve the real user support root; got \(engine.path)"
        )
        XCTAssertFalse(
            engine.path.hasPrefix(realPath + "/"),
            "redirected root must not nest under the real user tree: \(engine.path)"
        )
        XCTAssertTrue(
            AllnighterSupportRoot.isTestSupportRedirectActive,
            "redirect must be discoverable via isTestSupportRedirectActive"
        )
        XCTAssertEqual(
            AllnighterSupportRoot.activeTestSupportRoot?.standardizedFileURL,
            engine,
            "activeTestSupportRoot must name the redirected root"
        )

        // Default SetupStore (no injection) must land under the redirect —
        // this is the exact seam that corrupted cli_setup.json.
        let setupURL = SetupStore().fileURL.standardizedFileURL
        XCTAssertTrue(
            setupURL.path.hasPrefix(engine.path + "/"),
            "SetupStore default path must be under the redirected root; got \(setupURL.path)"
        )
        XCTAssertFalse(
            setupURL.path.hasPrefix(realPath + "/"),
            "SetupStore must not touch real Application Support; got \(setupURL.path)"
        )
    }

    /// `ALLNIGHTER_TEST_TOKEN` is exported by test wrappers into production
    /// `alln` invocations — it must NOT trip the XCTest redirect. In-process
    /// we cannot assert the negative (this host always loads a `.xctest`
    /// bundle), so spawn the built `alln` binary with only that env var set.
    func testProductionAllnIgnoresTestTokenEnv() throws {
        let alln = try locateAllnBinary()
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        var env: [String: String] = [
            "HOME": home,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
            "ALLNIGHTER_TEST_TOKEN": "abc123",
        ]
        for key in [
            "ALLNIGHTER_SUPPORT_DIR",
            "XCTestConfigurationFilePath",
            "XCTestSessionIdentifier",
            "XCTestBundlePath",
        ] {
            env.removeValue(forKey: key)
        }

        let baseline = try runAlln(
            alln,
            ["menu", "--json"],
            env: ["HOME": home, "PATH": env["PATH"]!]
        )
        XCTAssertEqual(baseline.status, 0, "baseline menu failed: \(baseline.stderr)")

        let withToken = try runAlln(alln, ["menu", "--json"], env: env)
        XCTAssertEqual(withToken.status, 0, "token menu failed: \(withToken.stderr)")
        XCTAssertFalse(
            withToken.stderr.contains("support root redirected"),
            "production alln must not redirect on ALLNIGHTER_TEST_TOKEN alone: \(withToken.stderr)"
        )

        let baselineHeadline = try menuBenchHeadline(from: baseline.stdout)
        let tokenHeadline = try menuBenchHeadline(from: withToken.stdout)
        XCTAssertEqual(
            tokenHeadline, baselineHeadline,
            "ALLNIGHTER_TEST_TOKEN must not switch to a parallel empty bench; baseline=\(baselineHeadline) token=\(tokenHeadline)"
        )
    }

    private func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: TestSupportRootIsolationTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "alln binary missing at \(binary.path) — build the alln product first"
        )
        return binary
    }

    private struct ProcessResult { var status: Int32; var stdout: String; var stderr: String }

    private func runAlln(_ alln: URL, _ arguments: [String], env: [String: String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func menuBenchHeadline(from stdout: String) throws -> String {
        let data = Data(stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tally = json?["benchTally"] as? [String: Any]
        let headline = tally?["headline"] as? String
        return try XCTUnwrap(headline, "menu JSON missing benchTally.headline: \(stdout.prefix(400))")
    }
}
