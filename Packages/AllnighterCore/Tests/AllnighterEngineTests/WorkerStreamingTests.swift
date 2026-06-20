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

final class GrokStreamParserTests: XCTestCase {

    private func collect(_ parser: GrokStreamParser, _ ndjson: String) -> [WorkerStreamEvent] {
        parser.receiveStdout(Data(ndjson.utf8))
    }

    func testTextEventsBecomeAnswerDeltasReasoningDoesNot() {
        let parser = GrokStreamParser()
        let events = collect(parser, """
        {"type":"thought","data":"The user asked for one word.\\n"}
        {"type":"text","data":"P"}
        {"type":"text","data":"ONG"}
        {"type":"end","stopReason":"EndTurn","sessionId":"s","requestId":"r"}

        """)
        let deltas = events.compactMap { event -> String? in
            if case .answerDelta(let text, _, _) = event { return text }
            return nil
        }
        // Only the two text events are deltas; thought + end never produce answer text.
        XCTAssertEqual(deltas, ["P", "ONG"])
        XCTAssertEqual(deltas.count, events.filter { if case .answerDelta = $0 { return true }; return false }.count)
        XCTAssertEqual(parser.finalAnswer(result: CommandResult(exitCode: 0), outputFileText: nil), "PONG")
    }

    func testLineSplitAcrossChunksStillParses() {
        let parser = GrokStreamParser()
        // First chunk cuts a JSON object mid-way; the second completes it.
        let first = parser.receiveStdout(Data(#"{"type":"text","da"#.utf8))
        XCTAssertTrue(first.isEmpty, "partial line must not emit yet")
        let second = parser.receiveStdout(Data("ta\":\"Hi\"}\n".utf8))
        guard case .answerDelta(let text, _, _)? = second.first else {
            return XCTFail("expected an answer delta once the line completes")
        }
        XCTAssertEqual(text, "Hi")
    }

    func testDegradedStreamFallsBackToPostExitExtraction() {
        // No deltas streamed; finalAnswer extracts from the full stdout buffer.
        let parser = GrokStreamParser()
        let full = #"{"type":"text","data":"Recovered"}"# + "\n"
        let answer = parser.finalAnswer(result: CommandResult(stdout: full, exitCode: 0), outputFileText: nil)
        XCTAssertEqual(answer, "Recovered")
    }
}

final class CursorStreamParserTests: XCTestCase {

    func testOnlyDeltaFormAssistantEventsBecomeAnswerText() {
        let parser = CursorStreamParser()
        // The spec's verified sequence: five character-level deltas (timestamp_ms,
        // no model_call_id), then a duplicate full end-of-turn flush (no timestamp_ms),
        // then the canonical result.
        let ndjson = """
        {"type":"system","subtype":"init","session_id":"s","model":"Composer 2.5"}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Count 1-3"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"1"}]},"timestamp_ms":1}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\\n"}]},"timestamp_ms":2}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"2"}]},"timestamp_ms":3}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\\n"}]},"timestamp_ms":4}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"3"}]},"timestamp_ms":5}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"1\\n2\\n3"}]}}
        {"type":"result","subtype":"success","is_error":false,"result":"1\\n2\\n3"}

        """
        let events = parser.receiveStdout(Data(ndjson.utf8))
        let deltas = events.compactMap { event -> String? in
            if case .answerDelta(let text, _, _) = event { return text }
            return nil
        }
        // Five incremental deltas; the no-timestamp flush + result are NOT deltas.
        XCTAssertEqual(deltas, ["1", "\n", "2", "\n", "3"])
        // Canonical final answer comes from result.result.
        XCTAssertEqual(parser.finalAnswer(result: CommandResult(exitCode: 0), outputFileText: nil), "1\n2\n3")
    }

    func testBufferedFlushWithModelCallIdIsSkipped() {
        let parser = CursorStreamParser()
        let ndjson = #"{"type":"assistant","message":{"content":[{"type":"text","text":"X"}]},"timestamp_ms":1,"model_call_id":"mc"}"# + "\n"
        let events = parser.receiveStdout(Data(ndjson.utf8))
        XCTAssertFalse(events.contains { if case .answerDelta = $0 { return true }; return false })
    }
}

final class ClaudeStreamParserTests: XCTestCase {

    func testTextDeltasConcatenateAndThinkingStreamsSeparately() {
        let parser = ClaudeStreamParser()
        let ndjson = """
        {"type":"system","subtype":"init","model":"claude-opus-4-8"}
        {"type":"stream_event","event":{"type":"message_start","message":{"role":"assistant"}}}
        {"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}}
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me think…"}}}
        {"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}}
        {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hi"}}}
        {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"! What can I help with today?"}}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Hi! What can I help with today?"}]}}
        {"type":"result","subtype":"success","is_error":false,"result":"Hi! What can I help with today?"}

        """
        let events = parser.receiveStdout(Data(ndjson.utf8))
        let answers = events.compactMap { e -> String? in if case .answerDelta(let t, _, _) = e { return t }; return nil }
        let thoughts = events.compactMap { e -> String? in if case .reasoningDelta(let t, _) = e { return t }; return nil }
        XCTAssertEqual(answers, ["Hi", "! What can I help with today?"])
        XCTAssertEqual(thoughts, ["Let me think…"])
        XCTAssertEqual(parser.finalAnswer(result: CommandResult(exitCode: 0), outputFileText: nil), "Hi! What can I help with today?")
    }

    func testAssistantSnapshotDoesNotDoubleRender() {
        let parser = ClaudeStreamParser()
        // A bare assistant snapshot (no stream_event deltas) must not produce answer text.
        let ndjson = #"{"type":"assistant","message":{"content":[{"type":"text","text":"snapshot"}]}}"# + "\n"
        let events = parser.receiveStdout(Data(ndjson.utf8))
        XCTAssertTrue(events.allSatisfy { if case .answerDelta = $0 { return false }; return true })
    }
}

final class CodexStreamParserTests: XCTestCase {

    func testAgentMessageSnapshotBecomesAnswerAndDedupes() {
        let parser = CodexStreamParser()
        let ndjson = """
        {"type":"thread.started","thread_id":"t"}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
        {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
        {"type":"turn.completed","usage":{"output_tokens":3}}

        """
        let events = parser.receiveStdout(Data(ndjson.utf8))
        let answers = events.compactMap { e -> String? in if case .answerDelta(let t, _, _) = e { return t }; return nil }
        XCTAssertEqual(answers, ["OK"], "duplicate item.id must not render twice")
        // Output-file capture is canonical when present.
        XCTAssertEqual(parser.finalAnswer(result: CommandResult(exitCode: 0), outputFileText: "OK"), "OK")
        XCTAssertEqual(parser.finalAnswer(result: CommandResult(exitCode: 0), outputFileText: nil), "OK")
    }

    func testToolAndReasoningItemsAreNotAnswerText() {
        let parser = CodexStreamParser()
        let ndjson = """
        {"type":"item.completed","item":{"id":"r0","type":"reasoning","text":"thinking about it"}}
        {"type":"item.completed","item":{"id":"c0","type":"command_execution","exit_code":0}}

        """
        let events = parser.receiveStdout(Data(ndjson.utf8))
        XCTAssertTrue(events.allSatisfy { if case .answerDelta = $0 { return false }; return true })
        XCTAssertTrue(events.contains { if case .reasoningDelta(let t, _) = $0 { return t == "thinking about it" }; return false })
    }
}

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
        let runner = WorkerRunner(commandRunner: MockCommandRunner(scripts: [:]),
                                  streamingCommandRunner: streamingRunner)

        var deltas: [String] = []
        var terminal: WorkerRunOutcome?
        var sawStarted = false
        do {
            for try await event in runner.invokeStreaming(
                worker: worker, manifest: manifest, prompt: "hi",
                parser: WorkerStreamParsers.make(for: manifest)!) {
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
        let runner = WorkerRunner(commandRunner: MockCommandRunner(scripts: [:]),
                                  streamingCommandRunner: streamingRunner)
        var terminal: WorkerRunOutcome?
        do {
            for try await event in runner.invokeStreaming(
                worker: worker, manifest: manifest, prompt: "hi",
                parser: WorkerStreamParsers.make(for: manifest)!) {
                if case .failed(let outcome) = event { terminal = outcome }
            }
        } catch { XCTFail("threw: \(error)") }
        XCTAssertEqual(terminal?.status, .failed)
        XCTAssertEqual(terminal?.exitCode, 1)
    }
}
