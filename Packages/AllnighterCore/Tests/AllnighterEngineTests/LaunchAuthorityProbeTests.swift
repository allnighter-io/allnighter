import XCTest
import AllnighterCore
import AgentOSCLI
@testable import AllnighterEngine

/// Allnighter cutover gates for TCC scratch CWD + smoke-false posture via
/// `AllnighterCLIDetector` (shared detector + Allnighter scratch path).
private actor RecordingRunner: CommandRunner {
    struct Call: Sendable {
        let command: String
        let args: [String]
        let workingDirectory: String?
    }

    private(set) var calls: [Call] = []
    private let responder: @Sendable (String, [String]) -> CommandResult

    init(responder: @escaping @Sendable (String, [String]) -> CommandResult) {
        self.responder = responder
    }

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        calls.append(Call(command: command, args: args, workingDirectory: workingDirectory))
        return responder(command, args)
    }

    func recorded() -> [Call] { calls }
}

private let kShell = "/bin/zsh"
private let kToolPath = "/opt/test/claude"

private func kResolved(_ path: String?) -> CommandResult {
    CommandResult(stdout: "<<<AOS:claude|\(path ?? "")>>>\n", exitCode: 0)
}

private func kManifest() -> DriverManifest {
    DriverManifest(
        id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
        detectCommand: "claude --version",
        smokeTestCommand: "claude -p \"probe\" --model {{model}}",
        smokeTestExpect: "ALLNIGHTER_READY",
        invoke: .init(command: "claude", args: ["-p", "{{prompt}}"]),
        setup: SetupBlock(
            bins: ["claude"], knownPaths: [],
            loginFlow: LoginFlow(interactiveCommand: "claude", instructions: "Run `claude`, then /login.",
                                 authErrorPatterns: ["/login"])
        )
    )
}

final class LaunchAuthorityProbeTests: XCTestCase {

    func testProbeChildProcessesUseNeutralScratchCWD() async {
        let runner = RecordingRunner { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath {
                return args.contains("--version")
                    ? CommandResult(stdout: "claude 1.0", exitCode: 0)
                    : CommandResult(stdout: "ALLNIGHTER_READY", exitCode: 0)
            }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let det = AllnighterCLIDetector.make(commandRunner: runner, shellPath: kShell, home: "/tmp/home")
        _ = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))

        let calls = await runner.recorded()
        XCTAssertFalse(calls.isEmpty)
        let scratch = AllnighterPaths.probeScratch.path
        for call in calls {
            XCTAssertEqual(call.workingDirectory, scratch)
        }
    }

    func testModelHealthCheckerUsesNeutralScratchCWD() async {
        let runner = RecordingRunner { _, _ in CommandResult(stdout: "claude 1.0", exitCode: 0) }
        let checker = ModelHealthChecker(commandRunner: runner)
        _ = await checker.detectVersion(kManifest())

        let calls = await runner.recorded()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.workingDirectory, AllnighterPaths.probeScratch.path)
    }

    func testSmokeFalseSkipsModelCallAndReportsInstalledNotProbed() async {
        let runner = RecordingRunner { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath, args.contains("--version") {
                return CommandResult(stdout: "claude 1.0", exitCode: 0)
            }
            return CommandResult(launchError: "smoke must not run when smoke == false")
        }
        let det = AllnighterCLIDetector.make(commandRunner: runner, shellPath: kShell, home: "/tmp/home")
        let record = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(record.status.kind, .installedNotProbed)
        let toolCalls = await runner.recorded().filter { $0.command == kToolPath }
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertTrue(toolCalls.allSatisfy { $0.args.contains("--version") })
    }

    func testResolveShellModeFollowsInteractiveFlag() async {
        func resolveFlag(interactive: Bool) async -> String? {
            let runner = RecordingRunner { _, _ in kResolved(kToolPath) }
            let det = AllnighterCLIDetector.make(
                commandRunner: runner, shellPath: kShell, home: "/tmp/home", interactive: interactive
            )
            _ = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0), smoke: false)
            return await runner.recorded().first { $0.command == kShell }?.args.first
        }
        let safe = await resolveFlag(interactive: false)
        let setup = await resolveFlag(interactive: true)
        XCTAssertEqual(safe, "-lc")
        XCTAssertEqual(setup, "-lic")
    }

    /// 2026-08-13: signed DMG Find my team must not spawn zsh -lic (Documents TCC).
    func testMacFindMyTeamCallSiteIsNonInteractive() throws {
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here
            .deletingLastPathComponent() // LaunchAuthorityProbeTests.swift dir
            .deletingLastPathComponent() // AllnighterEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AllnighterCore
            .deletingLastPathComponent() // Packages
        let sources = repoRoot
            .appendingPathComponent("Apps/AllnighterMac/Sources")
        let appModel = try String(
            contentsOf: sources.appendingPathComponent("AppModel.swift"),
            encoding: .utf8
        )
        guard let probe = appModel.range(of: "func runSetupProbe(userInitiated:") else {
            return XCTFail("runSetupProbe not found")
        }
        guard let cursorInstall = appModel.range(of: "func installCursorAgentCLI()") else {
            return XCTFail("installCursorAgentCLI not found")
        }
        let body = appModel[probe.lowerBound..<cursorInstall.lowerBound]
        XCTAssertFalse(body.contains("interactive: true"), "Find my team must not spawn zsh -lic")
        XCTAssertTrue(body.contains("interactive: false"), "Find my team must pin -lc")

        let appConfig = try String(
            contentsOf: sources.appendingPathComponent("AppConfig.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            appConfig.contains("\"-lic\""),
            "LoginShell Process arguments must not include interactive -lic"
        )
        XCTAssertTrue(appConfig.contains("\"-lc\""), "LoginShell must use -lc")
        XCTAssertTrue(
            appConfig.contains("ensuredProbeScratchPath"),
            "LoginShell must chdir to ProbeScratch"
        )
    }
}
