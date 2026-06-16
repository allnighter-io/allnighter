import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Regression gates for the Launch Authority TCC hotfix (slice H6).
///
/// These lock two engine-level invariants that, if they regress, re-open the
/// "Allnighter raises TCC prompts" code red:
///   * H3 — every setup/health probe child process starts from an Allnighter-
///     owned neutral CWD, never `nil` (which inherits the repo/Documents CWD).
///   * H2 — `smoke: false` is quota-free: it never runs the model smoke command
///     and honestly reports `installedNotProbed`.

/// A `CommandRunner` that records every spawn (command, args, CWD) so a test can
/// assert *how* children were launched, then replies via a scripted closure.
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
    CommandResult(stdout: "<<<ALR:claude|\(path ?? "")>>>\n", exitCode: 0)
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

    /// H3: every probe child (resolve shell, --version, smoke) is launched from
    /// the owned scratch dir, never `nil`.
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
        let det = CLIDetector(commandRunner: runner, shellPath: kShell, home: "/tmp/home")
        _ = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))

        let calls = await runner.recorded()
        XCTAssertFalse(calls.isEmpty, "expected the probe to spawn at least a resolve + version child")
        let scratch = AllnighterPaths.probeScratch.path
        for call in calls {
            XCTAssertEqual(
                call.workingDirectory, scratch,
                "probe child \(call.command) must use the neutral scratch CWD, not \(String(describing: call.workingDirectory))"
            )
        }
    }

    /// H3: the Doctor health path (ModelHealthChecker) is likewise CWD-neutral.
    func testModelHealthCheckerUsesNeutralScratchCWD() async {
        let runner = RecordingRunner { _, _ in CommandResult(stdout: "claude 1.0", exitCode: 0) }
        let checker = ModelHealthChecker(commandRunner: runner)
        _ = await checker.detectVersion(kManifest())

        let calls = await runner.recorded()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.workingDirectory, AllnighterPaths.probeScratch.path)
    }

    /// H2: quota-free mode never invokes the model smoke command and reports
    /// `installedNotProbed` rather than inferring readiness.
    func testSmokeFalseSkipsModelCallAndReportsInstalledNotProbed() async {
        let runner = RecordingRunner { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath, args.contains("--version") {
                return CommandResult(stdout: "claude 1.0", exitCode: 0)
            }
            return CommandResult(launchError: "smoke must not run when smoke == false")
        }
        let det = CLIDetector(commandRunner: runner, shellPath: kShell, home: "/tmp/home")
        let record = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(record.status.kind, .installedNotProbed)
        let toolCalls = await runner.recorded().filter { $0.command == kToolPath }
        XCTAssertEqual(toolCalls.count, 1, "only --version should run in detect-only mode")
        XCTAssertTrue(toolCalls.allSatisfy { $0.args.contains("--version") })
    }

    /// H2 contrast: explicit full probe DOES run the smoke command.
    func testSmokeTrueRunsModelCall() async {
        let runner = RecordingRunner { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath {
                return args.contains("--version")
                    ? CommandResult(stdout: "claude 1.0", exitCode: 0)
                    : CommandResult(stdout: "ALLNIGHTER_READY", exitCode: 0)
            }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let det = CLIDetector(commandRunner: runner, shellPath: kShell, home: "/tmp/home")
        let record = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0), smoke: true)

        XCTAssertEqual(record.status.kind, .ready)
        let smokeCalls = await runner.recorded().filter { $0.command == kToolPath && !$0.args.contains("--version") }
        XCTAssertEqual(smokeCalls.count, 1, "full probe must run the smoke command exactly once")
    }
}
