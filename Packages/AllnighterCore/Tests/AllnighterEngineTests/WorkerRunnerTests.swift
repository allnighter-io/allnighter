import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class WorkerRunnerTests: XCTestCase {

    private func runner(_ scripts: [String: MockCommandRunner.Script]) -> WorkerRunner {
        WorkerRunner(commandRunner: MockCommandRunner(scripts: scripts))
    }

    func testSuccessfulAnswer() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let run = runner(["claude": .init(stdout: "Here is my answer.", exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .done)
        XCTAssertEqual(response.output, "Here is my answer.")
        XCTAssertEqual(response.exitCode, 0)
        XCTAssertNotNil(response.durationMs)
    }

    func testAnsiIsStripped() async {
        let manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        let worker = TestSupport.worker("w", driverId: "grok")
        let colored = "\u{1B}[31mred\u{1B}[0m answer"
        let run = runner(["grok": .init(stdout: colored, exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.output, "red answer")
    }

    func testGrokStreamingJsonExtractsOnlyVisibleTextDeltas() async {
        let manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        let worker = TestSupport.worker("w", driverId: "grok")
        let streaming = """
{"type":"thought","data":"Analyzing..."}
{"type":"text","data":"Hello"}
{"type":"text","data":" from Grok"}
{"type":"end","stopReason":"EndTurn","sessionId":"s1","requestId":"r1"}
"""
        let run = runner(["grok": .init(stdout: streaming, exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .done)
        XCTAssertEqual(response.output, "Hello from Grok")
        XCTAssertEqual(response.exitCode, 0)
    }

    func testNonGrokJsonLikeAnswerIsNotRewritten() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let answer = """
Here is the fixture:
{"type":"text","data":"do not extract me"}
"""
        let run = runner(["claude": .init(stdout: answer, exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .done)
        XCTAssertEqual(response.output, answer)
    }

    func testEmptyOutputIsFailure() async {
        let manifest = TestSupport.headlessManifest(id: "codex", command: "codex")
        let worker = TestSupport.worker("w", driverId: "codex")
        let run = runner(["codex": .init(stdout: "   \n", exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorKind, .emptyOutput)
    }

    func testNonzeroExitIsFailure() async {
        let manifest = TestSupport.headlessManifest(id: "gemini", command: "gemini")
        let worker = TestSupport.worker("w", driverId: "gemini")
        let run = runner(["gemini": .init(stderr: "not logged in", exitCode: 1)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorKind, .nonzeroExit)
        XCTAssertEqual(response.errorReason, "not logged in")
    }

    func testTimeoutMapsToTimedOut() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let run = runner(["claude": .init(forcesTimeout: true)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .timedOut)
        XCTAssertEqual(response.errorKind, .timedOut)
    }

    func testCatalogWorkerRunUsesStreamingWhenAvailable() async {
        var manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        manifest.streaming = .init(
            supported: true,
            mode: .jsonlStdout,
            args: ["-p", "{{prompt}}"],
            partialOutput: true,
            finalAnswerSource: .parserAccumulator
        )
        let worker = TestSupport.worker("model_grok", driverId: "grok")
        let assignment = TestSupport.seat("model_grok", skillId: "spec_outside_scout")
        let streamingRunner = MockStreamingCommandRunner([
            .started(startedAt: Date()),
            .stdout(Data((#"{"type":"text","data":"streamed answer"}"# + "\n").utf8)),
            .completed(CommandResult(stdout: "", exitCode: 0))
        ])
        let run = WorkerRunner(
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "fallback answer")]),
            streamingCommandRunner: streamingRunner
        )

        let response = await run.run(assignment: assignment, model: worker, manifest: manifest, prompt: "hi")

        XCTAssertEqual(response.status, .done)
        XCTAssertEqual(response.output, "streamed answer")
    }

    func testMissingCLIMapsToMissing() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let run = runner(["claude": .init(launchError: "command not found: claude")])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorKind, .missingCLI)
    }

    func testFileCaptureReadsOutputFileNotStdout() async {
        // A driver that writes its answer to {{outputFile}}; stdout is noisy.
        var manifest = DriverManifest(
            id: "codex",
            displayName: "codex",
            kind: .headlessCLI,
            invoke: .init(
                command: "/bin/sh",
                args: ["-c", "echo noisy-log-line; printf 'clean answer' > \"$1\"", "sh", "{{outputFile}}"],
                promptVia: .arg,
                env: [:],
                workingDir: nil,
                timeoutSeconds: 5
            ),
            output: .init(capture: .file)
        )
        manifest.output = .init(capture: .file)

        let worker = TestSupport.worker("w", driverId: "codex")
        let run = WorkerRunner(commandRunner: SubprocessCommandRunner())
        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")

        XCTAssertEqual(response.status, .done)
        XCTAssertEqual(response.output, "clean answer")
        XCTAssertFalse(response.output?.contains("noisy-log-line") ?? true)
    }

    func testManualPasteWorkerIsSkipped() async {
        let manifest = DriverManifest(id: "manual_paste", displayName: "Manual", kind: .manualPaste)
        let worker = TestSupport.worker("w", driverId: "manual_paste")
        let run = runner([:])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .skipped)
        XCTAssertNil(response.output)
    }

    // MARK: - Capacity observation (WTK-S01b)

    func testNonzeroClaudeRateLimitCarriesCapacityObservation() async {
        let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"You've been rate limited","retry_after":9900}}"#
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let run = runner(["claude": .init(stderr: stderr, exitCode: 1)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorKind, .nonzeroExit)
        XCTAssertEqual(response.errorReason, stderr)
        XCTAssertEqual(response.capacityObservation?.kind, .accountRateLimit)
        XCTAssertEqual(response.capacityObservation?.source, "claude_code")
        XCTAssertEqual(response.capacityObservation?.sourceConfidence, .structured)
        XCTAssertEqual(response.capacityObservation?.retryAfterSeconds, 9_900)
    }

    func testNonzeroClaudeOverloadedCarriesProviderBusy() async {
        let stderr = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let run = runner(["claude": .init(stderr: stderr, exitCode: 1)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorKind, .nonzeroExit)
        XCTAssertEqual(response.capacityObservation?.kind, .providerBusy)
        XCTAssertEqual(response.capacityObservation?.sourceConfidence, .structured)
    }

    func testNonzeroCodexJSONLUsageLimitIsClassified() async {
        let stdout = #"{"type":"error","message":"usage_limit_reached","resetsAt":"2026-06-19T12:00:00Z"}"#
        let manifest = TestSupport.headlessManifest(id: "codex", command: "codex")
        let worker = TestSupport.worker("model_codex", driverId: "codex")
        let run = runner(["codex": .init(stdout: stdout, exitCode: 1)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorKind, .nonzeroExit)
        XCTAssertEqual(response.capacityObservation?.kind, .accountRateLimit)
        XCTAssertEqual(response.capacityObservation?.source, "codex")
        XCTAssertEqual(response.capacityObservation?.sourceConfidence, .structured)
        XCTAssertNotNil(response.capacityObservation?.observedResetAt)
    }

    func testAuthBlockerClassifiesWithoutWakeTicketSemantics() async {
        let stderr = "Error: not signed in — please run /login"
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let run = runner(["claude": .init(stderr: stderr, exitCode: 1)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.capacityObservation?.kind, .authRequired)
        XCTAssertNil(response.capacityObservation?.wakeAfter)
        XCTAssertNil(response.capacityObservation?.observedResetAt)
    }

    func testManualBlockerClassifiesWithoutWakeTicketSemantics() async {
        let stderr = "awaiting manual paste from user"
        let manifest = TestSupport.headlessManifest(id: "manual_paste_cli", command: "paste")
        let worker = TestSupport.worker("w", driverId: "manual_paste_cli")
        let run = runner(["paste": .init(stderr: stderr, exitCode: 1)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.capacityObservation?.kind, .manualRequired)
        XCTAssertNil(response.capacityObservation?.wakeAfter)
    }

    func testSuccessfulOutputWithCapacityLikeProseIsNotClassified() async {
        let stdout = "Here is my answer. The API was rate limited yesterday but works now."
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let run = runner(["claude": .init(stdout: stdout, exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .done)
        XCTAssertNil(response.capacityObservation)
    }

    // MARK: - Spawn-gate wait telemetry (gateWaitMs)

    /// A serialized driver (maxConcurrentSpawns=1) runs two seats one-at-a-time. The trailing
    /// seat queues behind the lead seat's work — that wait must land in `gateWaitMs` and be
    /// EXCLUDED from `durationMs` (pure work-time), so a queued seat never looks like a slow run.
    func testGatedDriverRecordsQueueWaitSeparatelyFromDuration() async {
        var manifest = TestSupport.headlessManifest(id: "agy_gatewait_test", command: "agy", timeout: 10)
        manifest.maxConcurrentSpawns = 1
        let worker = TestSupport.worker("w", driverId: "agy_gatewait_test")
        // Each spawn does ~250ms of "work" inside the gate.
        let run = WorkerRunner(commandRunner: MockCommandRunner(
            scripts: ["agy": .init(stdout: "answer", delay: .milliseconds(250))]))

        async let a = run.invoke(worker: worker, manifest: manifest, prompt: "one")
        async let b = run.invoke(worker: worker, manifest: manifest, prompt: "two")
        let results = await [a, b]

        // Serialized, nothing dropped: both seats ran to done.
        XCTAssertTrue(results.allSatisfy { $0.status == .done })

        let waits = results.compactMap(\.gateWaitMs).sorted()
        XCTAssertEqual(waits.count, 2, "both seats report a gateWaitMs")
        XCTAssertLessThan(waits[0], 150, "the lead seat acquires immediately — ~0 wait")
        XCTAssertGreaterThan(waits[1], 150, "the trailing seat queues behind the lead seat's work")

        // durationMs stays pure work-time on BOTH paths — the queued seat's ~250ms wait is
        // NOT folded into its duration (which would make it read as a ~500ms run).
        for r in results {
            XCTAssertNotNil(r.durationMs)
            XCTAssertLessThan(r.durationMs!, 600, "durationMs excludes gate wait (≈250ms work)")
        }
    }

    /// An ungated driver has no serialization gate, so there is no wait to attribute.
    func testUngatedDriverReportsNilGateWait() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let run = runner(["claude": .init(stdout: "hi", exitCode: 0)])

        let response = await run.invoke(worker: worker, manifest: manifest, prompt: "hi")
        XCTAssertEqual(response.status, .done)
        XCTAssertNil(response.gateWaitMs, "ungated drivers have no gate wait to report")
    }

    func testRunPropagatesCapacityObservationToWorkerAnswer() async {
        let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"limited","retry_after":120}}"#
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let model = TestSupport.worker("model_opus", driverId: "claude_code")
        let assignment = TestSupport.seat("model_opus")
        let run = runner(["claude": .init(stderr: stderr, exitCode: 1)])

        let answer = await run.run(assignment: assignment, model: model, manifest: manifest, prompt: "hi")
        XCTAssertEqual(answer.capacityObservation?.kind, .accountRateLimit)
        XCTAssertEqual(answer.errorKind, .nonzeroExit)
    }
}
