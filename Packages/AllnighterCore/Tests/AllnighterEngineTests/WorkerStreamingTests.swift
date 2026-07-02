import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// A scripted streaming runner: replays a fixed CommandEvent sequence, optionally
/// pacing chunks so timing-sensitive behavior can be exercised.
final class MockStreamingCommandRunner: StreamingCommandRunner, @unchecked Sendable {
    let events: [CommandEvent]
    init(_ events: [CommandEvent]) { self.events = events }

    func runStreaming(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

// GrokStreamParserTests, CursorStreamParserTests, ClaudeStreamParserTests, CodexStreamParserTests
// deleted (F2_B.1+.2): they exercised Allnighter's now-deleted GrokStreamParser /
// CursorStreamParser / ClaudeStreamParser / CodexStreamParser classes directly. That
// per-driver JSONL parsing logic is now AgentOSCLI's JSONLStreamParser driven by
// StreamParserSpec.forDriver, parity-tested in AgentOS's
// Tests/AgentOSCLITests/StreamParserTests.swift (testGrok, testClaudeCode, testCodexExecJson,
// testCursorAgent, testCursorAgentBufferedFlushWithModelCallIdIsSkipped,
// testClaudeAssistantSnapshotDoesNotDoubleRender, testCodexToolItemIsNotAnswerText,
// testPartialLineBufferedAcrossChunks, testSnapshotSemanticsSuppressesRepeatsAndEmitsSuffix,
// testGuardSeparatesAnswerFromReasoning) — same behaviors, same fixtures, different owner.

final class WorkerInvokeStreamingTests: XCTestCase {

    private func grokManifest() -> DriverManifest {
        var m = TestSupport.headlessManifest(id: "grok", command: "grok")
        m.streaming = .init(supported: true, mode: .jsonlStdout,
                            args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
                            partialOutput: true, finalAnswerSource: .parserAccumulator)
        return m
    }

    func testInvokeStreamingEmitsDeltasThenDoneOutcome() async {
        let manifest = grokManifest()
        let worker = TestSupport.worker("model_grok", driverId: "grok")
        let ndjson = """
        {"type":"text","data":"Hello"}
        {"type":"text","data":" world"}
        {"type":"end","stopReason":"EndTurn"}

        """
        let streamingRunner = MockStreamingCommandRunner([
            .started(startedAt: Date()),
            .stdout(Data(ndjson.utf8)),
            .completed(CommandResult(stdout: ndjson, exitCode: 0)),
        ])
        let runner = DefaultWorkerRunner(streamingRunner: streamingRunner)

        var deltas: [String] = []
        var terminal: WorkerRunOutcome?
        var sawStarted = false
        do {
            for try await event in runner.invoke(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi")) {
                switch event {
                case .started: sawStarted = true
                case .answerDelta(let text, _, _): deltas.append(text)
                case .completed(let outcome): terminal = outcome
                case .failed(let outcome): terminal = outcome
                default: break
                }
            }
        } catch { XCTFail("threw: \(error)") }

        XCTAssertTrue(sawStarted)
        XCTAssertEqual(deltas, ["Hello", " world"])
        XCTAssertEqual(terminal?.status, .done)
        XCTAssertEqual(terminal?.output, "Hello world")
    }

    func testInvokeStreamingNonzeroExitIsFailedTerminal() async {
        let manifest = grokManifest()
        let worker = TestSupport.worker("model_grok", driverId: "grok")
        let streamingRunner = MockStreamingCommandRunner([
            .started(startedAt: Date()),
            .completed(CommandResult(stdout: "", stderr: "boom", exitCode: 1)),
        ])
        let runner = DefaultWorkerRunner(streamingRunner: streamingRunner)
        var terminal: WorkerRunOutcome?
        do {
            for try await event in runner.invoke(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi")) {
                if case .failed(let outcome) = event { terminal = outcome }
            }
        } catch { XCTFail("threw: \(error)") }
        XCTAssertEqual(terminal?.status, .failed)
        XCTAssertEqual(terminal?.exitCode, 1)
    }
}
