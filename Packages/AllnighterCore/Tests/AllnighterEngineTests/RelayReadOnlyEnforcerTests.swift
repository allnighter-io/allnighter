import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// `--pm-read-only` mechanical enforcement (PM_Relay.md §4.2). `RelayReadOnlyEnforcer`
/// is the ONE place that decides which drivers can mechanically refuse to write and how
/// — these tests exercise it directly with fake manifests (mirrors
/// `DriverManifestSessionArgsTests`' fixture shape) so the mechanism-selection logic is
/// provable without spinning up a real relay/RunService.
final class RelayReadOnlyEnforcerTests: XCTestCase {
    // MARK: - claude_code

    private func claudeManifest(streamingArgs: [String] = [], session: DriverManifest.Session? = nil) -> DriverManifest {
        DriverManifest(
            id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
            invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}", "--permission-mode", "bypassPermissions"]),
            streaming: streamingArgs.isEmpty ? nil : .init(supported: true, mode: .jsonlStdout, args: streamingArgs),
            session: session
        )
    }

    func testClaudeReplacesBypassPermissionsWithPlanInInvokeArgs() {
        let manifest = claudeManifest()
        let enforced = RelayReadOnlyEnforcer.enforce(on: manifest)
        XCTAssertEqual(enforced?.invoke?.args, ["-p", "{{prompt}}", "--model", "{{model}}", "--permission-mode", "plan"])
    }

    func testClaudeAppendsPermissionModeWhenAbsentFromInvokeArgs() {
        let manifest = DriverManifest(
            id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
            invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}"]))
        let enforced = RelayReadOnlyEnforcer.enforce(on: manifest)
        XCTAssertEqual(enforced?.invoke?.args, ["-p", "{{prompt}}", "--model", "{{model}}", "--permission-mode", "plan"])
    }

    func testClaudeReplacesBypassPermissionsInStreamingArgsIndependentlyOfInvoke() {
        let manifest = claudeManifest(streamingArgs: [
            "-p", "{{prompt}}", "--model", "{{model}}", "--output-format", "stream-json", "--permission-mode", "bypassPermissions",
        ])
        let enforced = RelayReadOnlyEnforcer.enforce(on: manifest)
        XCTAssertEqual(enforced?.streaming?.args, [
            "-p", "{{prompt}}", "--model", "{{model}}", "--output-format", "stream-json", "--permission-mode", "plan",
        ])
        // invoke.args is a SEPARATE surface — it still carries its own bypassPermissions -> plan rewrite.
        XCTAssertEqual(enforced?.invoke?.args.last, "plan")
    }

    func testClaudeReplacesBypassPermissionsInSessionFirstTurnAndResumeArgs() {
        let session = DriverManifest.Session(
            continuity: .vendorSession, acquire: .set,
            firstTurnArgs: ["-p", "{{prompt}}", "--permission-mode", "bypassPermissions", "--session-id", "{{sessionId}}"],
            resumeArgs: ["-p", "{{prompt}}", "--permission-mode", "bypassPermissions", "--resume", "{{sessionId}}"])
        let manifest = claudeManifest(session: session)
        let enforced = RelayReadOnlyEnforcer.enforce(on: manifest)
        XCTAssertEqual(enforced?.session?.firstTurnArgs, ["-p", "{{prompt}}", "--permission-mode", "plan", "--session-id", "{{sessionId}}"])
        XCTAssertEqual(enforced?.session?.resumeArgs, ["-p", "{{prompt}}", "--permission-mode", "plan", "--resume", "{{sessionId}}"])
    }

    // MARK: - codex

    private func codexManifest(invokeArgs: [String], streamingArgs: [String] = [], resumeArgs: [String]? = nil) -> DriverManifest {
        DriverManifest(
            id: "codex", displayName: "Codex / ChatGPT", kind: .headlessCLI,
            invoke: .init(command: "codex", args: invokeArgs),
            streaming: streamingArgs.isEmpty ? nil : .init(supported: true, mode: .jsonlStdout, args: streamingArgs),
            session: resumeArgs.map { DriverManifest.Session(continuity: .vendorSession, acquire: .capture, resumeArgs: $0) }
        )
    }

    func testCodexInsertsReadOnlySandboxAndNeverApprovalRightAfterExec() {
        let manifest = codexManifest(invokeArgs: ["exec", "--skip-git-repo-check", "-m", "{{model}}", "{{prompt}}"])
        let enforced = RelayReadOnlyEnforcer.enforce(on: manifest)
        XCTAssertEqual(enforced?.invoke?.args, [
            "exec", "--sandbox", "read-only", "--ask-for-approval", "never", "--skip-git-repo-check", "-m", "{{model}}", "{{prompt}}",
        ])
    }

    func testCodexTransformsStreamingArgsAndResumeArgsIndependently() {
        let manifest = codexManifest(
            invokeArgs: ["exec", "-m", "{{model}}", "{{prompt}}"],
            streamingArgs: ["exec", "--json", "-m", "{{model}}", "{{prompt}}"],
            resumeArgs: ["exec", "resume", "{{sessionId}}", "-m", "{{model}}", "{{prompt}}"]
        )
        let enforced = RelayReadOnlyEnforcer.enforce(on: manifest)
        XCTAssertEqual(enforced?.streaming?.args, ["exec", "--sandbox", "read-only", "--ask-for-approval", "never", "--json", "-m", "{{model}}", "{{prompt}}"])
        XCTAssertEqual(enforced?.session?.resumeArgs, ["exec", "--sandbox", "read-only", "--ask-for-approval", "never", "resume", "{{sessionId}}", "-m", "{{model}}", "{{prompt}}"])
    }

    func testCodexEmptyStreamingArgsPassThroughUnchangedSinceItFallsBackToInvokeArgs() {
        // streaming.args == [] is a real, valid manifest shape (resolvedStreamingArgs falls
        // back to the already-transformed invoke.args) — must not be treated as a failure.
        let manifest = codexManifest(invokeArgs: ["exec", "-m", "{{model}}", "{{prompt}}"], streamingArgs: [])
        XCTAssertNotNil(RelayReadOnlyEnforcer.enforce(on: manifest))
    }

    func testCodexFailsClosedWhenInvokeArgsDoNotStartWithExec() {
        // An unrecognized/malformed argv shape — the mechanism cannot safely claim to
        // have locked this down, so the WHOLE manifest transform fails (nil), not a
        // partial transform that silently claims success.
        let manifest = codexManifest(invokeArgs: ["-p", "{{prompt}}", "--model", "{{model}}"])
        XCTAssertNil(RelayReadOnlyEnforcer.enforce(on: manifest))
    }

    // MARK: - Unsupported drivers (fail closed)

    func testUnsupportedDriverReturnsNilNeverAPromptOnlyFallback() {
        for driverId in ["cursor_agent", "grok", "antigravity", "opencode", "manual_paste", "some_future_driver"] {
            let manifest = DriverManifest(
                id: driverId, displayName: driverId, kind: .headlessCLI,
                invoke: .init(command: driverId, args: ["-p", "{{prompt}}"]))
            XCTAssertNil(RelayReadOnlyEnforcer.enforce(on: manifest), "\(driverId) has no confirmed mechanism — must fail closed")
        }
    }

    func testSupportedDriverIdsIsExactlyClaudeAndCodex() {
        XCTAssertEqual(RelayReadOnlyEnforcer.supportedDriverIds, ["claude_code", "codex"])
    }

    // MARK: - capabilityViolation (the CLI/MCP start-time pre-flight)

    private func models() -> [Model] {
        [
            Model(id: "model_claude", displayName: "Claude", modelLabel: "sonnet", driverId: "claude_code"),
            Model(id: "model_cursor", displayName: "Cursor", modelLabel: "composer", driverId: "cursor_agent"),
        ]
    }

    private func registry() -> DriverRegistry {
        DriverRegistry([
            DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
                            invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}"])),
            DriverManifest(id: "cursor_agent", displayName: "Cursor Agent", kind: .headlessCLI,
                            invoke: .init(command: "agent", args: ["-p", "{{prompt}}", "--trust"])),
        ])
    }

    func testCapabilityViolationNilForSupportedDriver() {
        XCTAssertNil(RelayReadOnlyEnforcer.capabilityViolation(pmWorkerId: "model_claude", models: models(), registry: registry()))
    }

    func testCapabilityViolationNamesTheDriverAndTheSupportedSeatsForUnsupportedDriver() {
        let violation = RelayReadOnlyEnforcer.capabilityViolation(pmWorkerId: "model_cursor", models: models(), registry: registry())
        XCTAssertNotNil(violation)
        XCTAssertTrue(violation!.contains("cursor_agent"))
        XCTAssertTrue(violation!.contains("claude_code"))
        XCTAssertTrue(violation!.contains("codex"))
    }

    func testCapabilityViolationForUnknownWorkerIdStillNamesSupportedSeats() {
        let violation = RelayReadOnlyEnforcer.capabilityViolation(pmWorkerId: "model_ghost", models: models(), registry: registry())
        XCTAssertNotNil(violation)
        XCTAssertTrue(violation!.contains("model_ghost"))
        XCTAssertTrue(violation!.contains("claude_code"))
        XCTAssertTrue(violation!.contains("codex"))
    }

    func testCapabilityViolationForModelWithNoRegisteredManifest() {
        let orphanModel = Model(id: "model_orphan", displayName: "Orphan", modelLabel: "x", driverId: "no_such_driver")
        let violation = RelayReadOnlyEnforcer.capabilityViolation(pmWorkerId: "model_orphan", models: [orphanModel], registry: registry())
        XCTAssertNotNil(violation)
        XCTAssertTrue(violation!.contains("model_orphan"))
    }
}
