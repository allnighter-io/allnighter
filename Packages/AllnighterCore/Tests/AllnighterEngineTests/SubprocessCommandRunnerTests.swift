import XCTest
@testable import AllnighterEngine

/// Exercises the real subprocess runner with cheap, deterministic system tools
/// (no AI CLIs, zero cost).
final class SubprocessCommandRunnerTests: XCTestCase {
    let runner = SubprocessCommandRunner()

    func testCapturesStdoutAndExitZero() async {
        let result = await runner.run(
            command: "/bin/echo",
            args: ["hello world"],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        XCTAssertFalse(result.timedOut)
        XCTAssertNil(result.launchError)
    }

    func testPromptIsSingleArgvElementNotShellInterpreted() async {
        let nasty = "a; echo PWNED"
        let result = await runner.run(
            command: "/bin/echo",
            args: [nasty],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        // If this were shell-interpreted, the output would be two lines
        // ("a" then "PWNED"); as a single argv element it is one verbatim line.
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), nasty)
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)
    }

    func testStdinIsForwarded() async {
        let result = await runner.run(
            command: "/bin/cat",
            args: [],
            stdin: "piped input",
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "piped input")
    }

    func testNonzeroExitIsReported() async {
        let result = await runner.run(
            command: "/bin/sh",
            args: ["-c", "exit 3"],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        XCTAssertEqual(result.exitCode, 3)
    }

    func testTimeoutKillsLongRunningProcess() async {
        let start = Date()
        let result = await runner.run(
            command: "/bin/sleep",
            args: ["10"],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .milliseconds(300)
        )
        XCTAssertTrue(result.timedOut)
        XCTAssertNil(result.exitCode)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "should not wait the full 10s")
    }

    func testMissingCommandReportsLaunchError() async {
        let result = await runner.run(
            command: "definitely-not-a-real-binary-xyz",
            args: [],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        XCTAssertNotNil(result.launchError)
    }

    func testCancellationTerminatesProcess() async {
        let runner = SubprocessCommandRunner()
        let task = Task {
            await runner.run(
                command: "/bin/sleep",
                args: ["10"],
                stdin: nil,
                env: [:],
                workingDirectory: nil,
                timeout: .seconds(30)
            )
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
    }
}
