import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class AntigravityAwareWorkerRunnerTests: XCTestCase {
    private let sessionId = "sess-123"

    /// Writes `<brainDir>/<sessionId>/.system_generated/logs/transcript.jsonl` with the
    /// given raw JSONL text, creating intermediate directories.
    private func writeTranscript(_ jsonl: String, brainDir: URL, sessionId: String) throws {
        let url = AntigravityTranscript.transcriptURL(brainDir: brainDir, sessionId: sessionId)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
    }

    private func antigravityManifest(brainDir: URL) -> DriverManifest {
        var m = TestSupport.headlessManifest(id: "antigravity", command: "agy")
        m.session = DriverManifest.Session(
            continuity: .vendorSession,
            acquire: .capture,
            capture: .init(from: .sessionDir, dir: brainDir.path)
        )
        return m
    }

    private func innerReturning(output: String, sessionId: String?) -> MockWorkerInvoking {
        MockWorkerInvoking(events: [
            .started(workerId: "mock", modelId: "mock", sourceId: "antigravity"),
            .completed(WorkerRunResult(status: .done, output: output, capturedSessionId: sessionId)),
        ])
    }

    func testRewritesAnswerAndReasoningFromTranscript() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeTranscript("""
        {"type":"PLANNER_RESPONSE","content":"I will look at the file."}
        {"type":"PLANNER_RESPONSE","content":"Final clean answer."}
        """, brainDir: tmp, sessionId: sessionId)

        let manifest = antigravityManifest(brainDir: tmp)
        let worker = TestSupport.worker("w", driverId: "antigravity")
        let aware = AntigravityAwareWorkerRunner(inner: innerReturning(output: "raw narration dump", sessionId: sessionId))

        let result = await aware.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.output, "Final clean answer.")
        XCTAssertEqual(result.reasoning, "I will look at the file.")
    }

    func testPassesThroughUnmodifiedForNonAntigravityDriver() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let worker = TestSupport.worker("w", driverId: "claude_code")
        let aware = AntigravityAwareWorkerRunner(inner: MockWorkerInvoking.answering(["untouched answer"]))

        let result = await aware.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.output, "untouched answer")
        XCTAssertNil(result.reasoning)
    }

    func testNoRewriteWhenTranscriptFileIsMissing() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manifest = antigravityManifest(brainDir: tmp)
        let worker = TestSupport.worker("w", driverId: "antigravity")
        let aware = AntigravityAwareWorkerRunner(inner: innerReturning(output: "raw stdout kept", sessionId: sessionId))

        let result = await aware.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.output, "raw stdout kept")
        XCTAssertNil(result.reasoning)
    }

    func testNoRewriteWhenNoSessionIdCaptured() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manifest = antigravityManifest(brainDir: tmp)
        let worker = TestSupport.worker("w", driverId: "antigravity")
        let aware = AntigravityAwareWorkerRunner(inner: innerReturning(output: "raw stdout kept", sessionId: nil))

        let result = await aware.collect(WorkerInvocation(model: worker, manifest: manifest, prompt: "hi"))

        XCTAssertEqual(result.output, "raw stdout kept")
    }
}
