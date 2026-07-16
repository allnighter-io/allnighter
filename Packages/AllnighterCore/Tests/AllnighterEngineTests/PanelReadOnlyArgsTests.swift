import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PN-S02 panel-scoped read-only argv injection + refusal for non-enforcing drivers.
final class PanelReadOnlyArgsTests: XCTestCase {

    // MARK: - claude_code

    private func claudeManifest(
        invokeArgs: [String] = ["-p", "{{prompt}}", "--model", "{{model}}", "--permission-mode", "bypassPermissions"]
    ) -> DriverManifest {
        DriverManifest(
            id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
            invoke: .init(command: "claude", args: invokeArgs)
        )
    }

    func testClaudeReplacesBypassWithPlan() {
        let enforced = PanelReadOnlyArgs.enforce(on: claudeManifest())
        XCTAssertEqual(
            enforced?.invoke?.args,
            ["-p", "{{prompt}}", "--model", "{{model}}", "--permission-mode", "plan"]
        )
    }

    func testClaudeAppendsPermissionModeWhenAbsent() {
        let enforced = PanelReadOnlyArgs.enforce(on: claudeManifest(
            invokeArgs: ["-p", "{{prompt}}", "--model", "{{model}}"]
        ))
        XCTAssertEqual(
            enforced?.invoke?.args,
            ["-p", "{{prompt}}", "--model", "{{model}}", "--permission-mode", "plan"]
        )
    }

    // MARK: - codex

    func testCodexInsertsReadOnlySandboxAfterExec() {
        let manifest = DriverManifest(
            id: "codex", displayName: "Codex", kind: .headlessCLI,
            invoke: .init(command: "codex", args: ["exec", "--skip-git-repo-check", "-m", "{{model}}", "{{prompt}}"])
        )
        let enforced = PanelReadOnlyArgs.enforce(on: manifest)
        XCTAssertEqual(enforced?.invoke?.args, [
            "exec", "--sandbox", "read-only", "--ask-for-approval", "never",
            "--skip-git-repo-check", "-m", "{{model}}", "{{prompt}}",
        ])
    }

    func testCodexFailsClosedWhenArgsDoNotStartWithExec() {
        let manifest = DriverManifest(
            id: "codex", displayName: "Codex", kind: .headlessCLI,
            invoke: .init(command: "codex", args: ["-p", "{{prompt}}"])
        )
        XCTAssertNil(PanelReadOnlyArgs.enforce(on: manifest))
    }

    // MARK: - Refusal

    func testUnsupportedDriverReturnsNilNeverPromptOnly() {
        for driverId in ["cursor_agent", "grok", "antigravity", "opencode", "manual_paste"] {
            let manifest = DriverManifest(
                id: driverId, displayName: driverId, kind: .headlessCLI,
                invoke: .init(command: driverId, args: ["-p", "{{prompt}}"])
            )
            XCTAssertNil(
                PanelReadOnlyArgs.enforce(on: manifest),
                "\(driverId) must fail closed in v0"
            )
        }
    }

    func testSupportedDriverIdsIsExactlyClaudeAndCodex() {
        XCTAssertEqual(PanelReadOnlyArgs.supportedDriverIds, ["claude_code", "codex"])
    }

    func testIsolationRefusalNamesCodeAndPN_S06() {
        let refusal = PanelReadOnlyArgs.isolationRefusal(
            workerId: "model_cursor", driverId: "cursor_agent", displayName: "Cursor"
        )
        XCTAssertEqual(refusal.code, "PANEL_SEAT_NOT_ISOLATED")
        XCTAssertTrue(refusal.message.contains("PANEL_SEAT_NOT_ISOLATED"))
        XCTAssertTrue(refusal.message.contains("PN-S06"))
        XCTAssertTrue(refusal.message.contains("cursor_agent"))
        XCTAssertTrue(refusal.message.contains("claude_code"))
    }

    func testCapabilityViolationNilForSupportedDriver() {
        let models = [
            Model(id: "model_claude", displayName: "Claude", modelLabel: "sonnet", driverId: "claude_code"),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
                invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}"])
            ),
        ])
        XCTAssertNil(PanelReadOnlyArgs.capabilityViolation(
            workerId: "model_claude", models: models, registry: registry
        ))
    }

    func testCapabilityViolationForUnsupportedDriver() {
        let models = [
            Model(id: "model_cursor", displayName: "Cursor", modelLabel: "composer", driverId: "cursor_agent"),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "cursor_agent", displayName: "Cursor Agent", kind: .headlessCLI,
                invoke: .init(command: "agent", args: ["-p", "{{prompt}}"])
            ),
        ])
        let violation = PanelReadOnlyArgs.capabilityViolation(
            workerId: "model_cursor", models: models, registry: registry
        )
        XCTAssertEqual(violation?.code, "PANEL_SEAT_NOT_ISOLATED")
        XCTAssertTrue(violation?.message.contains("PN-S06") == true)
    }

    func testErrorCodeIsRegistered() {
        let codes = Set(ContractRegistry.milestone1.errors.map(\.code))
        XCTAssertTrue(codes.contains("PANEL_SEAT_NOT_ISOLATED"))
    }
}
