import XCTest
@testable import AllnighterCore

/// Fixture tests for `source.cursor_agent.shellAllowlist` — never reads the
/// user's real `~/.cursor/cli-config.json` (paths are always temp fixtures).
final class CursorShellAllowlistTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-shell-allowlist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    private func writeConfig(_ json: String, name: String = "cli-config.json") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func doctorInputs(cursorConfig: URL?) -> DoctorReport.Inputs {
        .init(
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0",
            configDirWritable: true,
            runsDirWritable: true,
            full: false,
            cursorCLIConfigURL: cursorConfig
        )
    }

    private func buildDoctor(cursorConfig: URL?) -> DoctorResult {
        let models = [
            Model(id: "model_cursor_auto", displayName: "Auto", modelLabel: "auto",
                  driverId: "cursor_agent", role: .answerer),
        ]
        let manifests = [
            DriverManifest(id: "cursor_agent", displayName: "Cursor Agent", kind: .headlessCLI),
        ]
        let records = [
            ToolProbeRecord(driverId: "cursor_agent", status: .installedNotProbed(version: "1.0"),
                            version: "1.0", lastProbeAt: Date(timeIntervalSince1970: 0)),
        ]
        return DoctorReport.build(
            models: models, manifests: manifests, records: records,
            inputs: doctorInputs(cursorConfig: cursorConfig)
        )
    }

    private func check(_ r: DoctorResult) -> DoctorResult.Check? {
        r.checks.first { $0.name == CursorShellAllowlist.checkName }
    }

    // MARK: - Three config cases (PM acceptance)

    func testRestrictiveAllowlistIsDegradedWarning() throws {
        let url = try writeConfig("""
        {
          "permissions": { "allow": ["Shell(ls)"], "deny": [] },
          "approvalMode": "allowlist",
          "version": 1
        }
        """)
        let c = CursorShellAllowlist.check(configURL: url)
        XCTAssertEqual(c.name, "source.cursor_agent.shellAllowlist")
        XCTAssertEqual(c.status, .degraded)
        XCTAssertTrue(c.requiresManual)
        XCTAssertTrue(c.detail.contains(url.path), "detail must name the config file")
        XCTAssertTrue(c.detail.contains(".cursor/cli.json"), "detail must note project-scoped override")
        XCTAssertTrue(c.detail.contains("Shell(ls)") || c.detail.lowercased().contains("restrictive"))

        // Through the real doctor dispatch path.
        let r = buildDoctor(cursorConfig: url)
        XCTAssertEqual(check(r)?.status, .degraded)
        XCTAssertEqual(r.status, .degraded, "restrictive allowlist degrades overall doctor status")
    }

    func testPermissiveAllowlistIsOk() throws {
        let url = try writeConfig("""
        {
          "permissions": { "allow": ["Shell(*)"], "deny": [] },
          "approvalMode": "allowlist",
          "version": 1
        }
        """)
        let c = CursorShellAllowlist.check(configURL: url)
        XCTAssertEqual(c.status, .ok)
        XCTAssertFalse(c.requiresManual)

        let r = buildDoctor(cursorConfig: url)
        XCTAssertEqual(check(r)?.status, .ok)
        XCTAssertEqual(r.status, .ok)
    }

    func testMissingConfigIsNotChecked() throws {
        let missing = tempDir.appendingPathComponent("does-not-exist-cli-config.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))

        let c = CursorShellAllowlist.check(configURL: missing)
        XCTAssertEqual(c.status, .notChecked)
        XCTAssertTrue(c.detail.contains("not configured") || c.detail.contains("no Cursor CLI config"))

        let r = buildDoctor(cursorConfig: missing)
        XCTAssertEqual(check(r)?.status, .notChecked)
        // Missing optional vendor config must not fail the overall report.
        XCTAssertEqual(r.status, .ok)
    }

    // MARK: - Edge cases

    func testNilPathIsNotChecked() {
        let c = CursorShellAllowlist.check(configURL: nil)
        XCTAssertEqual(c.status, .notChecked)
    }

    func testNoPermissionsBlockIsOk() throws {
        let url = try writeConfig("""
        { "version": 1, "model": { "modelId": "composer-2.5" } }
        """)
        XCTAssertEqual(CursorShellAllowlist.check(configURL: url).status, .ok)
    }

    func testEmptyAllowUnderAllowlistIsRestrictive() throws {
        let url = try writeConfig("""
        { "permissions": { "allow": [], "deny": [] }, "approvalMode": "allowlist" }
        """)
        XCTAssertEqual(CursorShellAllowlist.check(configURL: url).status, .degraded)
    }

    func testAllowWithoutShellUnderAllowlistIsRestrictive() throws {
        let url = try writeConfig("""
        {
          "permissions": { "allow": ["Read(**)"], "deny": [] },
          "approvalMode": "allowlist"
        }
        """)
        let c = CursorShellAllowlist.check(configURL: url)
        XCTAssertEqual(c.status, .degraded)
        XCTAssertTrue(c.detail.contains(".cursor/cli.json"))
    }

    func testCheckNameIsContractListed() {
        let names = ContractRegistry.milestone1.doctorChecks.map(\.name)
        XCTAssertTrue(names.contains(CursorShellAllowlist.checkName))
    }
}
