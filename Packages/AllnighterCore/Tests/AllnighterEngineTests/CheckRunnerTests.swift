import XCTest
@testable import AllnighterEngine

final class CheckRunnerTests: XCTestCase {
    func testRunsRepoCheckCommand() async {
        let runner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "ok\n", exitCode: 0),
        ]))
        let result = await runner.run(
            check: .init(method: .command, command: "echo ok"),
            repoRoot: "/tmp"
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.passed)
        XCTAssertFalse(result.skipped)
    }

    func testNonZeroCheckFails() async {
        let runner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "fail", exitCode: 1),
        ]))
        let result = await runner.run(
            check: .init(method: .command, command: "false"),
            repoRoot: "/tmp"
        )
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.passed)
    }

    func testMinimalCheckEnvironmentKeepsBaseKeysAndAllnVars() {
        let parent = [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "LANG": "en_US.UTF-8",
            "TMPDIR": "/var/tmp",
            "ALLN_TEST_FLAG": "1",
            "OPENAI_API_KEY": "sk-secret",
            "RANDOM_HOST_SECRET": "leak",
        ]
        let env = CheckRunner.minimalCheckEnvironment(from: parent)
        XCTAssertEqual(env["PATH"], "/usr/bin")
        XCTAssertEqual(env["HOME"], "/Users/test")
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
        XCTAssertEqual(env["TMPDIR"], "/var/tmp")
        XCTAssertEqual(env["ALLN_TEST_FLAG"], "1")
        XCTAssertNil(env["OPENAI_API_KEY"])
        XCTAssertNil(env["RANDOM_HOST_SECRET"])
    }

    func testMinimalCheckEnvironmentStripsCredentialPrefixes() {
        let parent = [
            "PATH": "/bin",
            "OPENAI_API_KEY": "sk-openai",
            "ANTHROPIC_API_KEY": "sk-ant",
            "FEATHERLESS_TOKEN": "feather-secret",
        ]
        let env = CheckRunner.minimalCheckEnvironment(from: parent)
        XCTAssertEqual(env["PATH"], "/bin")
        XCTAssertEqual(env.count, 1)
    }

    func testCheckRunnerForwardsMinimalEnvironment() async {
        let capture = EnvCapturingCommandRunner()
        let runner = CheckRunner(commandRunner: capture)
        _ = await runner.run(
            check: .init(method: .command, command: "echo ok"),
            repoRoot: "/tmp"
        )
        let parent = ProcessInfo.processInfo.environment
        let expected = CheckRunner.minimalCheckEnvironment(from: parent)
        XCTAssertEqual(capture.lastEnvironment, expected)
        XCTAssertNil(capture.lastEnvironment?["OPENAI_API_KEY"])
    }
}

private final class EnvCapturingCommandRunner: CommandRunner, @unchecked Sendable {
    private(set) var lastEnvironment: [String: String]?

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        lastEnvironment = env
        return CommandResult(stdout: "ok", exitCode: 0)
    }
}
