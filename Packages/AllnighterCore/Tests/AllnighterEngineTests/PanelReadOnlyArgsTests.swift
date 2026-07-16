import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Panel-scoped read-only argv injection + isolation mode planning (PN-S02 + PN-S06).
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
        // No confirmed RO argv shape → clone isolation (not refusal).
        XCTAssertNil(PanelReadOnlyArgs.enforce(on: manifest))
        XCTAssertEqual(PanelSeatIsolation.mode(forManifest: manifest), .clone)
    }

    // MARK: - Isolation modes (PN-S06 — no seat refused)

    func testUnsupportedDriverReturnsNilEnforceUsesClone() {
        for driverId in ["cursor_agent", "grok", "antigravity", "opencode", "manual_paste"] {
            let manifest = DriverManifest(
                id: driverId, displayName: driverId, kind: .headlessCLI,
                invoke: .init(command: driverId, args: ["-p", "{{prompt}}"])
            )
            XCTAssertNil(
                PanelReadOnlyArgs.enforce(on: manifest),
                "\(driverId) has no confirmed RO mode"
            )
            XCTAssertEqual(
                PanelSeatIsolation.mode(forManifest: manifest), .clone,
                "\(driverId) must plan clone isolation, never refusal"
            )
        }
    }

    func testSupportedDriverIdsIsExactlyClaudeAndCodex() {
        XCTAssertEqual(PanelReadOnlyArgs.supportedDriverIds, ["claude_code", "codex"])
    }

    func testDriverEnforcedTrueForClaude() {
        let models = [
            Model(id: "model_claude", displayName: "Claude", modelLabel: "sonnet", driverId: "claude_code"),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
                invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}"])
            ),
        ])
        XCTAssertTrue(PanelReadOnlyArgs.isDriverEnforced(
            workerId: "model_claude", models: models, registry: registry
        ))
    }

    func testDriverEnforcedFalseForCursorPlansClone() {
        let models = [
            Model(id: "model_cursor", displayName: "Cursor", modelLabel: "composer", driverId: "cursor_agent"),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "cursor_agent", displayName: "Cursor Agent", kind: .headlessCLI,
                invoke: .init(command: "agent", args: ["-p", "{{prompt}}"])
            ),
        ])
        XCTAssertFalse(PanelReadOnlyArgs.isDriverEnforced(
            workerId: "model_cursor", models: models, registry: registry
        ))
        let plan = PanelSeatIsolation.plan(
            seats: [PanelSeat(workerId: "model_cursor", lens: "x")],
            models: models,
            registry: registry
        )
        XCTAssertEqual(plan.first?.mode, .clone)
        XCTAssertTrue(plan.first?.advisory?.contains("isolation: clone") == true)
    }

    func testErrorCodeIsRegistered() {
        let codes = Set(ContractRegistry.milestone1.errors.map(\.code))
        XCTAssertTrue(codes.contains("PANEL_SEAT_NOT_ISOLATED"))
        let spec = ContractRegistry.milestone1.errors.first { $0.code == "PANEL_SEAT_NOT_ISOLATED" }
        XCTAssertTrue(spec?.explain.contains("clone") == true, "repurposed explain must mention clone")
        XCTAssertFalse(spec?.explain.contains("v0 refuses") == true)
    }
}
