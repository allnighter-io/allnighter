import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// STR-S07: the chat send path streams partials onto the running turn and settles
/// correctly (final answer on success, preserved partial on failure/timeout).
final class StreamingSendCoordinatorTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func streamingGrokManifest() -> DriverManifest {
        var m = TestSupport.headlessManifest(id: "grok", command: "grok")
        m.streaming = .init(supported: true, mode: .jsonlStdout, args: [],
                            partialOutput: true, finalAnswerSource: .parserAccumulator)
        return m
    }

    private func makeStore() -> (ThreadStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stream-send-\(UUID().uuidString)")
        let store = ThreadStore(rootDirectory: root.appendingPathComponent("threads"))
        return (store, root)
    }

    private func coordinator(store: ThreadStore, manifest: DriverManifest,
                             events: [CommandEvent]) -> ThreadSendCoordinator {
        let clock = self.clock
        let runner = DefaultWorkerRunner(streamingRunner: MockStreamingCommandRunner(events), now: { clock })
        return ThreadSendCoordinator(
            store: store, runner: runner,
            registry: DriverRegistry([manifest]),
            models: [TestSupport.worker("grok", driverId: "grok")],
            defaultDriverWorkerId: "grok",
            now: { clock })
    }

    func testStreamingSendSettlesWithFinalAnswer() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.create(id: "t1", title: "chat", now: clock, defaultWorkerId: "grok")

        let ndjson = """
        {"type":"text","data":"Hello"}
        {"type":"text","data":" world"}
        {"type":"end","stopReason":"EndTurn"}

        """
        let coord = coordinator(store: store, manifest: streamingGrokManifest(), events: [
            .started(startedAt: clock),
            .stdout(Data(ndjson.utf8)),
            .completed(CommandResult(stdout: ndjson, exitCode: 0)),
        ])

        let result = try await coord.send(
            request: .init(message: "hi"), toThreadId: "t1")

        XCTAssertEqual(result.outcome?.status, .done)
        let turn = try XCTUnwrap(store.get("t1")?.turn(id: result.workerTurnId))
        XCTAssertEqual(turn.status, .done)
        XCTAssertEqual(turn.text, "Hello world")
        XCTAssertFalse(turn.partialOutputTruncated)
    }

    func testStreamingTimeoutPreservesPartialText() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.create(id: "t1", title: "chat", now: clock, defaultWorkerId: "grok")

        // A delta streamed, then a timeout — the partial must survive settlement.
        let partial = #"{"type":"text","data":"Half an answer"}"# + "\n"
        let coord = coordinator(store: store, manifest: streamingGrokManifest(), events: [
            .started(startedAt: clock),
            .stdout(Data(partial.utf8)),
            .timedOut(partialStdout: Data(partial.utf8), partialStderr: Data()),
        ])

        let result = try await coord.send(request: .init(message: "hi"), toThreadId: "t1")

        XCTAssertEqual(result.outcome?.status, .timedOut)
        let turn = try XCTUnwrap(store.get("t1")?.turn(id: result.workerTurnId))
        XCTAssertEqual(turn.status, .timedOut)
        XCTAssertEqual(turn.text, "Half an answer", "the real partial must not be erased by the error")
    }

    func testNonStreamingWorkerStillSettles() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.create(id: "t1", title: "chat", now: clock, defaultWorkerId: "grok")

        // No streaming block on the manifest; `DefaultWorkerRunner` still drives the
        // one seam and settles from the single terminal event (F2_B.3c: there is no
        // longer a separate non-streaming spawn path to distinguish).
        let manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        let coord = coordinator(store: store, manifest: manifest, events: [
            .started(startedAt: clock),
            .completed(CommandResult(stdout: "Plain final answer", exitCode: 0)),
        ])

        let result = try await coord.send(request: .init(message: "hi"), toThreadId: "t1")

        XCTAssertEqual(result.outcome?.status, .done)
        let turn = try XCTUnwrap(store.get("t1")?.turn(id: result.workerTurnId))
        XCTAssertEqual(turn.text, "Plain final answer")
    }
}
