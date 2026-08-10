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

    func testAttentionDetailNamesCursorGrokCollision() {
        let detail = SetupRecoveryCopy.attentionDetail(
            driverId: "cursor_agent",
            state: .probeFailed,
            probeReason: "error: a value is required for '--single <PROMPT>'"
        )
        XCTAssertTrue(detail.lowercased().contains("cursor"), detail)
        XCTAssertFalse(detail.lowercased().contains("health check failed"), detail)
    }

    func testAttentionDetailSurfacesOpenCodePort() {
        let detail = SetupRecoveryCopy.attentionDetail(
            driverId: "opencode",
            state: .probeFailed,
            probeReason: "opencode serve: portOwnedByForeignProcess(listenerPID: 40234)"
        )
        XCTAssertTrue(detail.lowercased().contains("opencode") || detail.contains("4096"), detail)
    }

    func testAttentionDetailPassesClaudeSmokeReason() {
        let detail = SetupRecoveryCopy.attentionDetail(
            driverId: "claude_code",
            state: .probeFailed,
            probeReason: "smoke exited 1"
        )
        XCTAssertEqual(detail, "smoke exited 1")
    }
}
