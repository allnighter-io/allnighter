import XCTest
import AgentOSCLI
@testable import AllnighterCore

final class CursorAgentCLIInstallTests: XCTestCase {

    func testShouldPromptInstallOnlyWithAppAndMissingCLI() {
        XCTAssertTrue(CursorAgentCLIInstall.shouldPromptInstall(
            cliAbsentOrUnchecked: true, cursorAppPresent: true))
        XCTAssertFalse(CursorAgentCLIInstall.shouldPromptInstall(
            cliAbsentOrUnchecked: true, cursorAppPresent: false))
        XCTAssertFalse(CursorAgentCLIInstall.shouldPromptInstall(
            cliAbsentOrUnchecked: false, cursorAppPresent: true))
    }

    func testDetectsCursorAppBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Cursor.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(CursorAgentCLIInstall.isCursorAppInstalled(appBundlePath: app.path))
        XCTAssertFalse(CursorAgentCLIInstall.isCursorAppInstalled(appBundlePath: root.appendingPathComponent("Missing.app").path))
    }

    func testRunSucceedsWhenInstallerCreatesLauncher() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = ClosureCommandRunner { command, args in
            XCTAssertEqual(command, "/bin/bash")
            XCTAssertEqual(args.first, "-lc")
            XCTAssertTrue(args.dropFirst().first?.contains("cursor.com/install") == true)
            let launcher = bin.appendingPathComponent("cursor-agent")
            FileManager.default.createFile(
                atPath: launcher.path,
                contents: Data([0x7f]),
                attributes: [.posixPermissions: 0o755]
            )
            return CommandResult(stdout: "installed\n", exitCode: 0)
        }
        let outcome = await CursorAgentCLIInstall.run(
            commandRunner: runner,
            home: root.path
        )
        XCTAssertTrue(outcome.succeeded, outcome.detail)
        XCTAssertEqual(outcome.launcherPath, CursorAgentCLIInstall.launcherPath(home: root.path))
    }

    func testRunFailsWhenLauncherMissingAfterInstall() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = ClosureCommandRunner { _, _ in CommandResult(stdout: "ok\n", exitCode: 0) }
        let outcome = await CursorAgentCLIInstall.run(commandRunner: runner, home: root.path)
        XCTAssertFalse(outcome.succeeded)
        XCTAssertTrue(outcome.detail.contains("cursor-agent"), outcome.detail)
    }
}

private struct ClosureCommandRunner: CommandRunner {
    let handler: @Sendable (String, [String]) -> CommandResult
    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        handler(command, args)
    }
}
