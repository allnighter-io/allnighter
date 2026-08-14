import XCTest
import AgentOSCLI
@testable import AllnighterCore

final class SetupRecoveryCopyTests: XCTestCase {

    func testCursorNotInstalledNeverEquatesIDE() throws {
        let manifest = BundledDefaults.cursorManifest
        let detail = SetupRecoveryCopy.notInstalledDetail(for: manifest, cursorAppPresent: false)
        XCTAssertTrue(detail.contains("Cursor app is not the seat"))
        XCTAssertTrue(detail.contains("curl") || detail.contains("agent"))
        XCTAssertEqual(
            SetupRecoveryCopy.notInstalledFixCommand(for: manifest),
            "https://cursor.com/docs/cli/installation"
        )
        XCTAssertEqual(
            SetupRecoveryCopy.notInstalledInstallShellCommand(for: manifest),
            CursorAgentCLIInstall.shellCommand
        )
        XCTAssertEqual(
            SetupRecoveryCopy.loginDocsURL(for: manifest),
            "https://cursor.com/docs/cli/using"
        )
    }

    func testCursorNotInstalledWithAppPresentOffersInstall() throws {
        let manifest = BundledDefaults.cursorManifest
        let detail = SetupRecoveryCopy.notInstalledDetail(for: manifest, cursorAppPresent: true)
        XCTAssertTrue(detail.contains("You have Cursor"), detail)
        XCTAssertTrue(detail.contains("app is not the seat"), detail)
        XCTAssertEqual(
            SetupRecoveryCopy.attentionDetail(
                driverId: "cursor_agent",
                state: .notInstalled,
                probeReason: nil,
                cursorAppPresent: true
            ),
            "You have Cursor — install the Agent CLI to use Composer."
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
        XCTAssertTrue(
            check.detail.contains("Cursor app is not the seat")
                || check.detail.contains("You have Cursor"),
            check.detail
        )
        XCTAssertEqual(check.fixCommand, CursorAgentCLIInstall.shellCommand)
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

    func testAttentionDetailSurfacesOpenCodeBadModel() {
        let detail = SetupRecoveryCopy.attentionDetail(
            driverId: "opencode",
            state: .probeFailed,
            probeReason: #"opencode smoke: messageFailed("HTTP 500: {\"name\":\"UnknownError\"}")"#
        )
        XCTAssertTrue(detail.lowercased().contains("serve") || detail.lowercased().contains("binary"), detail)
        XCTAssertFalse(detail.lowercased().contains("locate"), detail)
        XCTAssertFalse(detail.lowercased().contains("zen"), detail)
    }

    func testAttentionDetailMapsOpaqueClaudeSmokeToLogin() {
        let detail = SetupRecoveryCopy.attentionDetail(
            driverId: "claude_code",
            state: .probeFailed,
            probeReason: "smoke exited 1"
        )
        XCTAssertTrue(detail.contains("/login"), detail)
        XCTAssertTrue(detail.lowercased().contains("re-check"), detail)
    }

    func testAttentionDetailClaudeNeedsLoginNamesExpiredLogin() {
        let detail = SetupRecoveryCopy.attentionDetail(
            driverId: "claude_code",
            state: .needsLogin,
            probeReason: nil
        )
        XCTAssertTrue(detail.contains("/login"), detail)
        XCTAssertTrue(detail.lowercased().contains("claude code"), detail)
        XCTAssertFalse(detail.lowercased().contains("run `claude`, type"), detail)
    }

    func testNeedsLoginDetailPrefersCatalogInstructionsForKimi() {
        let detail = SetupRecoveryCopy.needsLoginDetail(
            driverId: "kimi",
            loginCommand: "kimi login",
            loginInstructions: "Run `kimi login` and complete the device-code flow in the browser."
        )
        XCTAssertEqual(
            detail,
            "Run `kimi login` and complete the device-code flow in the browser."
        )
    }

    func testNeedsLoginDetailFallsBackToCommandWhenNoInstructions() {
        let detail = SetupRecoveryCopy.needsLoginDetail(
            driverId: "codex",
            loginCommand: "codex",
            loginInstructions: nil
        )
        XCTAssertTrue(detail.contains("`codex`"), detail)
    }

    func testRecoveryClaudeOpaqueSmokeIsNeedsSignIn() {
        let recovery = SetupRecoveryCopy.recovery(
            for: ToolProbeRecord(
                driverId: "claude_code",
                status: .probeFailed(reason: "smoke exited 1"),
                lastProbeAt: .distantPast
            ),
            manifest: nil
        )
        XCTAssertEqual(recovery.statusKind, "needsSignIn")
        XCTAssertNil(recovery.fixCommand)
        XCTAssertEqual(recovery.nextAction?.kind, "signInClaude")
        XCTAssertEqual(recovery.nextAction?.command, "alln help get setup_and_auth")
        XCTAssertFalse(
            recovery.nextAction?.command.contains("detect") == true,
            "Claude nextAction must not loop agents on alln detect"
        )
    }

    func testDetectReportJSONSurfacesCursorInstall() throws {
        let manifest = BundledDefaults.cursorManifest
        let report = DetectReport.build(
            records: [
                ToolProbeRecord(
                    driverId: "cursor_agent",
                    status: .notInstalled,
                    lastProbeAt: .distantPast
                )
            ],
            registry: DriverRegistry([manifest]),
            assembled: .init(benchModelIds: [], planWriterModelId: nil)
        )
        let source = try XCTUnwrap(report.sources.first)
        XCTAssertEqual(source.status, "notInstalled")
        XCTAssertEqual(source.fixCommand, CursorAgentCLIInstall.shellCommand)
        XCTAssertEqual(report.nextActions.first?.kind, "installCLI")
    }

    func testDetectNextActionsPreferSignInOverInstall() {
        let kimi = DriverManifest(
            id: "kimi",
            displayName: "Kimi",
            kind: .headlessCLI,
            setup: SetupBlock(
                bins: ["kimi"],
                loginFlow: LoginFlow(interactiveCommand: "kimi login", instructions: "Run `kimi login`.")
            )
        )
        let anti = DriverManifest(
            id: "antigravity",
            displayName: "Antigravity",
            kind: .headlessCLI,
            setup: SetupBlock(
                bins: ["agy"],
                installHint: "curl -fsSL https://antigravity.google/cli/install.sh | bash",
                docsURL: "https://antigravity.google/docs/cli-install"
            )
        )
        let report = DetectReport.build(
            records: [
                ToolProbeRecord(
                    driverId: "antigravity",
                    status: .notInstalled,
                    lastProbeAt: .distantPast
                ),
                ToolProbeRecord(
                    driverId: "kimi",
                    status: .installedNotSignedIn(
                        LoginFlow(interactiveCommand: "kimi login", instructions: "Run `kimi login`.")
                    ),
                    version: "1",
                    lastProbeAt: .distantPast
                ),
            ],
            registry: DriverRegistry([anti, kimi]),
            assembled: .init(benchModelIds: [], planWriterModelId: nil)
        )
        XCTAssertEqual(report.nextActions.first?.kind, "signInCLI", "installed sign-in beats missing install")
        XCTAssertEqual(report.nextActions.first?.command, "kimi login")
        let install = report.nextActions.first { $0.kind == "installCLI" }
        XCTAssertEqual(
            install?.command,
            "curl -fsSL https://antigravity.google/cli/install.sh | bash"
        )
    }

    func testNotInstalledOnlyPrefersInstallCurlForAgyAndQwen() throws {
        let agy = DriverManifest(
            id: "antigravity",
            displayName: "Antigravity",
            kind: .headlessCLI,
            setup: SetupBlock(
                bins: ["agy"],
                installHint: "curl -fsSL https://antigravity.google/cli/install.sh | bash",
                docsURL: "https://antigravity.google/docs/cli-install",
                loginFlow: LoginFlow(
                    interactiveCommand: "agy",
                    instructions: "Run `agy`. It tries silent auth via the Apple Keychain."
                )
            )
        )
        let qwen = DriverManifest(
            id: "qwen",
            displayName: "Qwen Code",
            kind: .headlessCLI,
            setup: SetupBlock(
                bins: ["qwen"],
                installHint: "Install with: curl -fsSL https://example.com/install-qwen.sh | bash",
                docsURL: "https://qwenlm.github.io/qwen-code-docs/en/users/overview/",
                loginFlow: LoginFlow(
                    interactiveCommand: "qwen",
                    instructions: "Run `qwen`, then use `/auth` to connect a provider."
                )
            )
        )
        XCTAssertEqual(
            SetupRecoveryCopy.notInstalledInstallShellCommand(for: agy),
            "curl -fsSL https://antigravity.google/cli/install.sh | bash"
        )
        XCTAssertEqual(
            SetupRecoveryCopy.notInstalledInstallShellCommand(for: qwen),
            "curl -fsSL https://example.com/install-qwen.sh | bash"
        )

        let report = DetectReport.build(
            records: [
                ToolProbeRecord(driverId: "antigravity", status: .notInstalled, lastProbeAt: .distantPast),
                ToolProbeRecord(driverId: "qwen", status: .notInstalled, lastProbeAt: .distantPast),
            ],
            registry: DriverRegistry([agy, qwen]),
            assembled: .init(benchModelIds: [], planWriterModelId: nil)
        )
        XCTAssertTrue(report.nextActions.allSatisfy { $0.kind == "installCLI" })
        XCTAssertTrue(report.nextActions.contains { $0.command.contains("antigravity.google") })
        XCTAssertTrue(report.nextActions.contains { $0.command.contains("install-qwen") })
        XCTAssertFalse(report.nextActions.contains { $0.command.hasPrefix("https://") })

        let qwenSignedOut = SetupRecoveryCopy.recovery(
            for: ToolProbeRecord(
                driverId: "qwen",
                status: .installedNotSignedIn(
                    LoginFlow(
                        interactiveCommand: "qwen",
                        instructions: "Run `qwen`, then use `/auth` to connect a provider."
                    )
                ),
                lastProbeAt: .distantPast
            ),
            manifest: qwen
        )
        XCTAssertEqual(qwenSignedOut.statusKind, "needsSignIn")
        XCTAssertNil(qwenSignedOut.fixCommand, "Qwen /auth is not a shell login")
        XCTAssertTrue(qwenSignedOut.detail?.contains("/auth") == true, qwenSignedOut.detail ?? "")
        XCTAssertEqual(qwenSignedOut.nextAction?.command, "alln help get setup_and_auth")

        let agySignedOut = SetupRecoveryCopy.recovery(
            for: ToolProbeRecord(
                driverId: "antigravity",
                status: .installedNotSignedIn(
                    LoginFlow(
                        interactiveCommand: "agy",
                        instructions: "Run `agy`. It tries silent auth via the Apple Keychain."
                    )
                ),
                lastProbeAt: .distantPast
            ),
            manifest: agy
        )
        XCTAssertEqual(agySignedOut.fixCommand, "agy")
        XCTAssertTrue(agySignedOut.detail?.contains("agy") == true, agySignedOut.detail ?? "")
    }

    func testDriversNotReadySurfacesLoginFixInFreshness() throws {
        let kimi = DriverManifest(
            id: "kimi",
            displayName: "Kimi",
            kind: .headlessCLI,
            setup: SetupBlock(
                bins: ["kimi"],
                loginFlow: LoginFlow(interactiveCommand: "kimi login", instructions: "Run `kimi login`.")
            )
        )
        let list = DriverListProjector.build(
            registry: DriverRegistry([kimi]),
            probeRecords: [
                ToolProbeRecord(
                    driverId: "kimi",
                    status: .installedNotSignedIn(
                        LoginFlow(interactiveCommand: "kimi login", instructions: "Run `kimi login`.")
                    ),
                    version: "0.34.0",
                    lastProbeAt: Date()
                ),
            ],
            models: [],
            parkedDriverIds: []
        )
        let row = try XCTUnwrap(list.drivers.first)
        XCTAssertEqual(row.status, "notReady")
        // Driver list keeps probeDetail short for the 25 KiB menu budget; the
        // runnable login command lives on freshness.nextAction (see DriverListProjector).
        XCTAssertEqual(
            row.probeDetail,
            "Installed but signed out — sign in to use its models."
        )
        XCTAssertEqual(row.freshness.nextAction.command, "kimi login")
    }
}
