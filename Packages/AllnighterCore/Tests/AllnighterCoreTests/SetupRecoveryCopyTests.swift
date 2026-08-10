import XCTest
import AgentOSCLI
@testable import AllnighterCore

final class SetupRecoveryCopyTests: XCTestCase {

    func testCursorNotInstalledNeverEquatesIDE() throws {
        let manifest = BundledDefaults.cursorManifest
        let detail = SetupRecoveryCopy.notInstalledDetail(for: manifest)
        XCTAssertTrue(detail.contains("Cursor app is not the seat"))
        XCTAssertTrue(detail.contains("curl") || detail.contains("agent"))
        XCTAssertEqual(
            SetupRecoveryCopy.notInstalledFixCommand(for: manifest),
            "https://cursor.com/docs/cli/installation"
        )
        XCTAssertEqual(
            SetupRecoveryCopy.loginDocsURL(for: manifest),
            "https://cursor.com/docs/cli/using"
        )
    }

    func testDoctorNotInstalledUsesRecoveryCopy() throws {
        let manifest = BundledDefaults.cursorManifest
        let record = ToolProbeRecord(
            driverId: "cursor_agent",
            status: .notInstalled,
            lastProbeAt: .distantPast
        )
        let result = DoctorReport.build(
            models: [],
            manifests: [manifest],
            records: [record],
            inputs: DoctorReport.Inputs(
                binaryVersion: "1.0.0",
                contractVersion: "1.0.0",
                docsVersionMatchesBinary: true,
                configDirWritable: true,
                runsDirWritable: true,
                full: false
            )
        )
        let check = try XCTUnwrap(result.checks.first { $0.name == "source.cursor_agent.installed" })
        XCTAssertEqual(check.status, .degraded)
        XCTAssertTrue(check.detail.contains("Cursor app is not the seat"))
        XCTAssertEqual(check.fixCommand, "https://cursor.com/docs/cli/installation")
    }
}
