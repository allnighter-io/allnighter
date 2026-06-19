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
