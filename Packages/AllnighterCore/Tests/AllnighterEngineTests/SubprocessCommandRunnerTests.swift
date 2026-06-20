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

    // MARK: - STR-S02/S03: streaming runner

    private func terminalEvent(of events: [CommandEvent]) -> CommandEvent? {
        events.last { event in
            switch event {
            case .completed, .failed, .timedOut, .cancelled: return true
            default: return false
            }
        }
    }

    func testStreamingEmitsStdoutChunksBeforeCompletion() async {
        let stream = runner.runStreaming(
            command: "/bin/sh",
            args: ["-c", "printf 'early\\n'; sleep 0.4; printf 'late\\n'"],
            stdin: nil, env: [:], workingDirectory: nil, timeout: .seconds(10))

        var firstStdoutAt: Date?
        var completedAt: Date?
        var text = ""
        var completedExit: Int32?
        do {
            for try await event in stream {
                switch event {
                case .stdout(let data):
                    if firstStdoutAt == nil { firstStdoutAt = Date() }
                    text += String(decoding: data, as: UTF8.self)
                case .completed(let result):
                    completedAt = Date()
                    completedExit = result.exitCode
                default:
                    break
                }
            }
        } catch {
            XCTFail("stream threw: \(error)")
        }

        XCTAssertEqual(completedExit, 0)
        XCTAssertTrue(text.contains("early"), "got: \(text)")
        XCTAssertTrue(text.contains("late"), "got: \(text)")
        guard let first = firstStdoutAt, let done = completedAt else {
            return XCTFail("missing stdout/completion timing")
        }
        // The first chunk must arrive well before exit — proof of LIVE streaming,
        // not a post-exit replay (the script sleeps 0.4s between the two prints).
        XCTAssertGreaterThan(done.timeIntervalSince(first), 0.2)
    }

    func testStreamingTimeoutPreservesPartialStdout() async {
        var events: [CommandEvent] = []
        do {
            for try await event in runner.runStreaming(
                command: "/bin/sh", args: ["-c", "printf 'partial'; sleep 10"],
                stdin: nil, env: [:], workingDirectory: nil, timeout: .milliseconds(400)) {
                events.append(event)
            }
        } catch {
            XCTFail("stream threw: \(error)")
        }
        guard case .timedOut(let partialStdout, _)? = terminalEvent(of: events) else {
            return XCTFail("expected timedOut terminal, got \(String(describing: terminalEvent(of: events)))")
        }
        XCTAssertTrue(String(decoding: partialStdout, as: UTF8.self).contains("partial"))
    }

    func testStreamingFailedOnMissingCommand() async {
        var events: [CommandEvent] = []
        do {
            for try await event in runner.runStreaming(
                command: "definitely-not-a-real-binary-xyz", args: [],
                stdin: nil, env: [:], workingDirectory: nil, timeout: .seconds(5)) {
                events.append(event)
            }
        } catch {}
        guard case .failed? = terminalEvent(of: events) else {
            return XCTFail("expected failed terminal, got \(String(describing: terminalEvent(of: events)))")
        }
    }

    func testStreamingCancelKillsProcessGroup() async {
        let runner = SubprocessCommandRunner()
        let start = Date()
        let task = Task {
            do {
                for try await _ in runner.runStreaming(
                    command: "/bin/sleep", args: ["10"],
                    stdin: nil, env: [:], workingDirectory: nil, timeout: .seconds(30)) {}
            } catch {}
        }
        try? await Task.sleep(for: .milliseconds(250))
        task.cancel()
        _ = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "cancel must kill the process, not wait the full 10s")
    }
}
