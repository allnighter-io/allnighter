import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// A `CommandRunner` driven by a closure over (command, args) so a single tool
/// path can return different output for `--version` vs the smoke run — which the
/// command-keyed `MockCommandRunner` can't express.
private struct ClosureRunner: CommandRunner {
    let handler: @Sendable (String, [String]) -> CommandResult
    func run(command: String, args: [String], stdin: String?, env: [String: String],
             workingDirectory: String?, timeout: Duration) async -> CommandResult {
        handler(command, args)
    }
}

// File-scope so the @Sendable handlers don't capture `self`.
private let kShell = "/bin/zsh"
private let kToolPath = "/opt/test/claude"

private func kResolved(_ path: String?) -> CommandResult {
    CommandResult(stdout: "<<<ALR:claude|\(path ?? "")>>>\n", exitCode: 0)
}

private func kManifest(authPatterns: [String] = ["/login"]) -> DriverManifest {
    DriverManifest(
        id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
        detectCommand: "claude --version",
        smokeTestCommand: "claude -p \"probe\" --model {{model}}",
        smokeTestExpect: "ALLNIGHTER_READY",
        invoke: .init(command: "claude", args: ["-p", "{{prompt}}"]),
        setup: SetupBlock(
            bins: ["claude"], knownPaths: [],
            loginFlow: LoginFlow(interactiveCommand: "claude", instructions: "Run `claude`, then /login.",
                                 authErrorPatterns: authPatterns)
        )
    )
}

private func kDetector(_ handler: @escaping @Sendable (String, [String]) -> CommandResult) -> CLIDetector {
    CLIDetector(commandRunner: ClosureRunner(handler: handler), shellPath: kShell, home: "/tmp/home")
}

final class CLIDetectorTests: XCTestCase {

    func testReadyWhenSmokeReturnsToken() async {
        let det = kDetector { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath {
                return args.contains("--version")
                    ? CommandResult(stdout: "claude 9.9.9", exitCode: 0)
                    : CommandResult(stdout: "ALLNIGHTER_READY", exitCode: 0)
            }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let r = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.status, .ready(version: "claude 9.9.9"))
        XCTAssertEqual(r.invocation, .direct(path: kToolPath))
        XCTAssertTrue(r.status.isReady)
    }

    func testNotSignedInWhenSmokeHitsAuthPattern() async {
        let det = kDetector { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath {
                return args.contains("--version")
                    ? CommandResult(stdout: "claude 9.9.9", exitCode: 0)
                    : CommandResult(stderr: "Error: please run /login to authenticate", exitCode: 1)
            }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let r = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.status.kind, .installedNotSignedIn)
        XCTAssertFalse(r.status.isReady)
    }

    func testProbeFailedWhenSmokeErrorIsNotAuth() async {
        let det = kDetector { command, args in
            if args.first == "-lc" { return kResolved(kToolPath) }
            if command == kToolPath {
                return args.contains("--version")
                    ? CommandResult(stdout: "claude 9.9.9", exitCode: 0)
                    : CommandResult(stderr: "error: unknown flag --model (exit 2)", exitCode: 2)
            }
            return CommandResult(launchError: "unexpected \(command)")
        }
        let r = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.status.kind, .probeFailed)
    }

    func testNotInstalledWhenUnresolved() async {
        let det = kDetector { _, args in
            if args.first == "-lc" { return kResolved(nil) }
            return CommandResult(launchError: "should not run")
        }
        let r = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.status, .notInstalled)
    }

    func testShimmedWhenResolvedToAlias() async {
        let det = kDetector { _, args in
            if args.first == "-lc" {
                return CommandResult(stdout: "<<<ALR:claude|claude: aliased to claude --foo>>>\n", exitCode: 0)
            }
            return CommandResult(launchError: "should not run an ambiguous alias")
        }
        let r = await det.probe(kManifest(), model: "opus", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.status.kind, .shimmedNeedsConfirm)
        if case .loginShell(let name) = r.invocation { XCTAssertEqual(name, "claude") }
        else { XCTFail("expected loginShell invocation") }
    }

    /// Round-trips the persisted record (Codable with associated values).
    func testProbeRecordCodableRoundTrip() throws {
        let rec = ToolProbeRecord(
            driverId: "claude_code",
            status: .installedNotSignedIn(LoginFlow(interactiveCommand: "claude", instructions: "x", authErrorPatterns: ["/login"])),
            invocation: .direct(path: "/opt/test/claude"), version: "claude 9.9.9",
            lastProbeAt: .init(timeIntervalSince1970: 123)
        )
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(ToolProbeRecord.self, from: data)
        XCTAssertEqual(rec, back)
    }
}
