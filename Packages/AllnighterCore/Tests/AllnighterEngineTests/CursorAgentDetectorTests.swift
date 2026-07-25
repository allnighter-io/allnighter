import XCTest
import AllnighterCore
import AgentOSCLI
@testable import AllnighterEngine

private struct ClosureRunner: CommandRunner {
    let handler: @Sendable (String, [String]) -> CommandResult
    func run(command: String, args: [String], stdin: String?, env: [String: String],
             workingDirectory: String?, timeout: Duration) async -> CommandResult {
        handler(command, args)
    }
}

final class CursorAgentDetectorTests: XCTestCase {

    func testKeychainAuthClassifier() async throws {
        let manifest = try Fixtures.manifest(.manifestCursor)
        let det = AllnighterCLIDetector.make(
            commandRunner: ClosureRunner { command, args in
                if args.first == "-lc" {
                    return CommandResult(stdout: "<<<AOS:agent|/tmp/agent>>>\n", exitCode: 0)
                }
                if command == "/tmp/agent" {
                    return args.contains("--version")
                        ? CommandResult(stdout: "2026.06.16", exitCode: 0)
                        : CommandResult(stderr: "ERROR: SecItemCopyMatching failed -67674", exitCode: 1)
                }
                return CommandResult(launchError: "unexpected")
            },
            shellPath: "/bin/zsh", home: "/tmp/home")
        let r = await det.probe(manifest, model: "composer-2.5", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.status.kind, .installedNotSignedIn)
    }

    func testProbeFailedDoesNotFallBackToFastModel() async throws {
        let manifest = try Fixtures.manifest(.manifestCursor)
        let det = AllnighterCLIDetector.make(
            commandRunner: ClosureRunner { command, args in
                if args.first == "-lc" {
                    return CommandResult(stdout: "<<<AOS:agent|/tmp/agent>>>\n", exitCode: 0)
                }
                if command == "/tmp/agent" {
                    return args.contains("--version")
                        ? CommandResult(stdout: "2026.06.16", exitCode: 0)
                        : CommandResult(stderr: "model composer-2.5 not available", exitCode: 1)
                }
                return CommandResult(launchError: "unexpected")
            },
            shellPath: "/bin/zsh", home: "/tmp/home")
        let r = await det.probe(manifest, model: "composer-2.5", now: .init(timeIntervalSince1970: 0))
        if case .probeFailed(let reason) = r.status {
            XCTAssertTrue(reason.contains("composer-2.5") || reason.contains("not available"))
            XCTAssertFalse(reason.lowercased().contains("fast"))
        } else {
            XCTFail("expected probeFailed, got \(r.status)")
        }
    }

    func testCursorAgentFallbackBinKnownPath() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let binDir = root.appendingPathComponent(".local/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let agentPath = binDir.appendingPathComponent("cursor-agent").path
        FileManager.default.createFile(atPath: agentPath, contents: Data([0x7f, 0x45, 0x4c, 0x46]), attributes: [.posixPermissions: 0o755])

        let manifest = DriverManifest(
            id: "cursor_agent", displayName: "Cursor Agent", kind: .headlessCLI,
            detectCommand: "cursor-agent --version",
            smokeTestCommand: "cursor-agent -p probe",
            smokeTestExpect: "ALLNIGHTER_READY",
            invoke: .init(command: "cursor-agent", args: ["-p", "{{prompt}}"]),
            setup: SetupBlock(bins: ["agent", "cursor-agent"], knownPaths: ["~/.local/bin"]))
        let det = AllnighterCLIDetector.make(
            commandRunner: ClosureRunner { command, args in
                if args.first == "-lc" {
                    return CommandResult(stdout: "<<<AOS:agent|\n<<<AOS:cursor-agent|\n", exitCode: 0)
                }
                if command == agentPath {
                    return args.contains("--version")
                        ? CommandResult(stdout: "2026.06.16", exitCode: 0)
                        : CommandResult(stdout: "ALLNIGHTER_READY", exitCode: 0)
                }
                return CommandResult(launchError: "unexpected \(command)")
            },
            shellPath: "/bin/zsh", home: root.path)
        let r = await det.probe(manifest, model: "composer-2.5", now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(r.invocation, .direct(path: agentPath))
        XCTAssertTrue(r.status.isSmokeReady)
        try? FileManager.default.removeItem(at: root)
    }
}
