import XCTest
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// PO-F5 — `alln run --idle-timeout` + progress-truth idle reset on the run streaming path.
///
/// The `alln run` driver uses `ProcessGroupCommandRunner` (via `RunService` →
/// `WorkerInvokerFactory` → `DefaultWorkerRunner`). Idle stall budget is the
/// `timeout` argument; F1 already resets it on any stdout/stderr bytes (tool-call
/// JSON, reasoning, child chatter — not answer tokens alone). These tests lock that
/// contract for the run path and prove the CLI override reaches the runner.
final class RunIdleTimeoutTests: XCTestCase {

    // The RunService cases below build without an explicit runStore (default = the
    // real ~/Library Runs). Redirect the support root to a temp dir so "hi" probe
    // runs never leak into real user state.
    private var supportDir: URL!
    override func setUpWithError() throws {
        supportDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("runidle-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", supportDir.path, 1)
    }
    override func tearDownWithError() throws {
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: supportDir)
    }

    // MARK: - CLI parse (typed CLI_USAGE_ERROR)

    func testParseIdleTimeoutSecondsAcceptsPositiveInteger() {
        let parsed = RunCLI.parseIdleTimeoutSeconds("600")
        XCTAssertEqual(parsed.value, 600)
        XCTAssertNil(parsed.error)
    }

    func testParseIdleTimeoutSecondsNilMeansDefaultBudget() {
        let parsed = RunCLI.parseIdleTimeoutSeconds(nil)
        XCTAssertNil(parsed.value, "omit flag → no override (manifest default, typically 300s)")
        XCTAssertNil(parsed.error)
    }

    func testParseIdleTimeoutSecondsRejectsNonNumeric() throws {
        let parsed = RunCLI.parseIdleTimeoutSeconds("abc")
        XCTAssertNil(parsed.value)
        let message = try XCTUnwrap(parsed.error)
        XCTAssertTrue(message.contains("--idle-timeout"), message)
        XCTAssertTrue(message.contains("abc"), message)
    }

    func testParseIdleTimeoutSecondsRejectsNonPositive() {
        for raw in ["0", "-5"] {
            let parsed = RunCLI.parseIdleTimeoutSeconds(raw)
            XCTAssertNil(parsed.value, raw)
            XCTAssertNotNil(parsed.error, raw)
            XCTAssertTrue(parsed.error?.contains("--idle-timeout") == true, parsed.error ?? raw)
        }
    }

    // MARK: - RunService honors workerTimeoutSeconds → runner timeout

    func testRunServiceHonorsWorkerTimeoutSecondsOverride() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("po-f5-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let spy = TimeoutCapturingStreamingRunner()
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok", timeout: 300)]),
            commandRunner: spy,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )

        let result = await service.run(
            RunRequest(
                message: "hi",
                repoRoot: repo.path,
                workerId: "model_grok",
                workerTimeoutSeconds: 777
            ),
            origin: .cli,
            runId: "po-f5-override"
        )
        guard case .success = result else {
            return XCTFail("run failed: \(result)")
        }
        let captured = spy.lastTimeout
        XCTAssertEqual(
            captured?.components.seconds, 777,
            "RunRequest.workerTimeoutSeconds must reach the streaming runner as Duration.seconds"
        )
    }

    func testRunServiceDefaultLeavesTimeoutNilForManifestBudget() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("po-f5-default-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let spy = TimeoutCapturingStreamingRunner()
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok", timeout: 300)]),
            commandRunner: spy,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, workerId: "model_grok"),
            origin: .cli,
            runId: "po-f5-default"
        )
        guard case .success = result else {
            return XCTFail("run failed: \(result)")
        }
        // nil override → DefaultWorkerRunner uses manifest.invoke.timeoutSeconds (300).
        // The spy sees whatever DefaultWorkerRunner passes; when WorkerInvocation.timeout
        // is nil the runner substitutes the manifest value before runStreaming.
        // Capture the spy's last timeout: DefaultWorkerRunner always passes a concrete Duration.
        XCTAssertNotNil(spy.lastTimeout)
        XCTAssertEqual(spy.lastTimeout?.components.seconds, 300,
                       "without --idle-timeout, runner gets the manifest default (300s)")
    }

    // MARK: - Progress-truth: tool-only stream past budget is NOT timed out

    func testToolOnlyStreamPastIdleBudgetIsNotTimedOut() async throws {
        // Emit only non-answer tool-call JSON every 200ms for ~2.2s (2× a 1s stall budget).
        // Any stdout chunk is progress (F1 / PO-F5) — answer tokens are not required.
        let stallBudget: Duration = .seconds(1)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(30), maxBufferedBytes: 1_000_000)
        )
        let script = """
        i=0
        while [ $i -lt 12 ]; do
          printf '%s\\n' '{"type":"tool_call","title":"read_file","path":"AGENTS.md"}'
          i=$((i+1))
          sleep 0.2
        done
        printf '%s\\n' 'done'
        """
        var terminal: CommandEvent?
        let start = Date()
        do {
            for try await event in runner.runStreaming(
                command: "/bin/sh",
                args: ["-c", script],
                stdin: nil,
                env: [:],
                workingDirectory: nil,
                timeout: stallBudget
            ) {
                switch event {
                case .completed, .timedOut, .cancelled, .failed, .bufferOverflow:
                    terminal = event
                default:
                    break
                }
            }
        } catch {
            XCTFail("stream threw: \(error)")
        }
        let elapsed = Date().timeIntervalSince(start)
        guard case .completed(let result)? = terminal else {
            return XCTFail(
                "tool-only stream past idle budget must complete, not time out; got \(String(describing: terminal))"
            )
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertGreaterThan(elapsed, 1.5, "must have run longer than the idle budget")
        XCTAssertFalse(result.stdout.isEmpty, "tool-call lines should be captured")
    }

    func testTotalSilencePastIdleBudgetIsReapedAtWallNotIdle() async throws {
        let stallBudget: Duration = .seconds(1)
        let wallBudget: Duration = .seconds(4)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: wallBudget, maxBufferedBytes: 1_000_000)
        )
        let start = Date()
        var terminal: CommandEvent?
        do {
            for try await event in runner.runStreaming(
                command: "/bin/sleep",
                args: ["30"],
                stdin: nil,
                env: [:],
                workingDirectory: nil,
                timeout: stallBudget
            ) {
                switch event {
                case .completed, .timedOut, .cancelled, .failed, .bufferOverflow:
                    terminal = event
                default:
                    break
                }
            }
        } catch {
            XCTFail("stream threw: \(error)")
        }
        let elapsed = Date().timeIntervalSince(start)
        guard case .timedOut? = terminal else {
            return XCTFail(
                "identity-alive silence must be reaped at wall, not idle; got \(String(describing: terminal))"
            )
        }
        XCTAssertGreaterThan(elapsed, 2.5, "must survive past the idle stall budget")
        XCTAssertLessThan(elapsed, 10, "must reap near the wall backstop, not the full sleep")
    }

    func testReasoningOnlyStreamPastIdleBudgetIsNotTimedOut() async throws {
        // Reasoning/thought deltas on stdout are also progress (PO-F5).
        let stallBudget: Duration = .seconds(1)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(30), maxBufferedBytes: 1_000_000)
        )
        let script = """
        i=0
        while [ $i -lt 12 ]; do
          printf '%s\\n' '{"type":"thought","data":"reading files…"}'
          i=$((i+1))
          sleep 0.2
        done
        """
        var terminal: CommandEvent?
        do {
            for try await event in runner.runStreaming(
                command: "/bin/sh",
                args: ["-c", script],
                stdin: nil,
                env: [:],
                workingDirectory: nil,
                timeout: stallBudget
            ) {
                switch event {
                case .completed, .timedOut, .cancelled, .failed, .bufferOverflow:
                    terminal = event
                default:
                    break
                }
            }
        } catch {
            XCTFail("stream threw: \(error)")
        }
        guard case .completed? = terminal else {
            return XCTFail(
                "reasoning-only stream past idle budget must complete; got \(String(describing: terminal))"
            )
        }
    }
}

// MARK: - Spies

/// Records the `timeout` passed into `runStreaming` / `run` so PO-F5 can prove
/// `RunRequest.workerTimeoutSeconds` reaches the runner.
private final class TimeoutCapturingStreamingRunner: CommandRunner, StreamingCommandRunner, @unchecked Sendable {
    nonisolated(unsafe) private(set) var lastTimeout: Duration?

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        lastTimeout = timeout
        return CommandResult(stdout: "ok", exitCode: 0)
    }

    func runStreaming(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        lastTimeout = timeout
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(startedAt: Date()))
            continuation.yield(.stdout(Data("ok".utf8)))
            continuation.yield(.completed(CommandResult(stdout: "ok", exitCode: 0)))
            continuation.finish()
        }
    }
}
