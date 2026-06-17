import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// One-worker chat with optimistic turns, terminal-state settling, and the
/// manual-paste fallback (PWT-S05). Deterministic via MockCommandRunner and
/// injected id/clock factories.
final class WorkerChatCoordinatorTests: XCTestCase {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("chat-\(UUID().uuidString)")
    }

    private func manualManifest(id: String) -> DriverManifest {
        DriverManifest(id: id, displayName: id, kind: .manualPaste,
                       detectCommand: nil, smokeTestCommand: nil, smokeTestExpect: nil,
                       invoke: nil, output: nil)
    }

    /// A coordinator wired to a temp store, a scripted runner, and a fixed clock.
    private func makeCoordinator(
        dir: URL,
        scripts: [String: MockCommandRunner.Script],
        models: [Model],
        manifests: [DriverManifest]
    ) -> (WorkerChatCoordinator, ThreadStore) {
        let store = ThreadStore(rootDirectory: dir)
        let fixedClock = clock
        let commandRunner = MockCommandRunner(scripts: scripts)
        let runner = WorkerRunner(commandRunner: commandRunner, now: { fixedClock })
        let imageInvoker = WorkerImageInvoker(commandRunner: commandRunner, now: { fixedClock })
        let counter = Counter()
        let coordinator = WorkerChatCoordinator(
            store: store,
            runner: runner,
            imageInvoker: imageInvoker,
            registry: DriverRegistry(manifests),
            models: models,
            idFactory: { counter.next() },
            now: { fixedClock }
        )
        return (coordinator, store)
    }

    /// Lock-guarded monotonic id source so the factory is `@Sendable`.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> String { lock.lock(); defer { lock.unlock() }; n += 1; return "id\(n)" }
    }

    private let clock = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Headless happy path

    func testBeginSendPersistsOptimisticTurnsBeforeInvoke() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let (coord, store) = makeCoordinator(dir: dir,
            scripts: ["claude": .init(stdout: "late reply", exitCode: 0)],
            models: [worker], manifests: [manifest])
        try store.create(id: "t1", title: "T", now: clock, defaultWorkerId: "model_opus")

        let checkpoint = try await coord.beginSend(message: "hello", toThreadId: "t1")
        guard case .awaitingInvoke(let pending) = checkpoint else {
            return XCTFail("expected headless invoke pending")
        }

        let mid = store.get("t1")!
        XCTAssertEqual(mid.turns.count, 2)
        XCTAssertEqual(mid.turns[0].kind, .userMessage)
        XCTAssertEqual(mid.turns[0].text, "hello")
        XCTAssertEqual(mid.turns[1].kind, .workerChat)
        XCTAssertEqual(mid.turns[1].status, .running)
        XCTAssertTrue(mid.isRunning)

        _ = try await coord.completeSend(pending)
        let settled = store.get("t1")!
        XCTAssertEqual(settled.turns[1].status, .done)
        XCTAssertEqual(settled.turns[1].text, "late reply")
        XCTAssertFalse(settled.isRunning)
    }

    func testSendCreatesUserAndWorkerTurnsAndLandsReply() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let (coord, store) = makeCoordinator(dir: dir,
            scripts: ["claude": .init(stdout: "Use a single owner-scoped flag.", exitCode: 0)],
            models: [worker], manifests: [manifest])

        try store.create(id: "t1", title: "Team accounts", now: clock, defaultWorkerId: "model_opus")
        let result = try await coord.send(message: "brainstorm the simplest approach", toThreadId: "t1")

        XCTAssertFalse(result.awaitingManualPaste)
        XCTAssertEqual(result.outcome?.status, .done)

        let thread = store.get("t1")!
        XCTAssertEqual(thread.turns.count, 2)
        XCTAssertEqual(thread.turns[0].kind, .userMessage)
        XCTAssertEqual(thread.turns[0].text, "brainstorm the simplest approach")
        XCTAssertEqual(thread.turns[1].kind, .workerChat)
        XCTAssertEqual(thread.turns[1].status, .done)
        XCTAssertEqual(thread.turns[1].text, "Use a single owner-scoped flag.")
        XCTAssertEqual(thread.turns[1].workerId, "model_opus")
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention)
    }

    func testContextPacketIsPersistedAndRevealable() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let (coord, store) = makeCoordinator(dir: dir,
            scripts: ["claude": .init(stdout: "ok", exitCode: 0)],
            models: [worker], manifests: [manifest])
        try store.create(id: "t1", title: "T", now: clock)

        let r = try await coord.send(message: "first", toThreadId: "t1")
        let packet = await coord.revealContext(threadId: "t1", packetId: r.contextPacketId)
        XCTAssertNotNil(packet)
        XCTAssertTrue(packet!.text.contains("Latest user message:\nfirst"))
        XCTAssertEqual(store.get("t1")!.turns[1].contextPacketId, r.contextPacketId)
    }

    func testSecondTurnContextIncludesEarlierTurns() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let grok = TestSupport.worker("model_grok", driverId: "grok")
        let claudeM = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let grokM = TestSupport.headlessManifest(id: "grok", command: "grok")
        let (coord, store) = makeCoordinator(dir: dir,
            scripts: ["claude": .init(stdout: "owner flag", exitCode: 0),
                      "grok": .init(stdout: "agreed", exitCode: 0)],
            models: [opus, grok], manifests: [claudeM, grokM])
        try store.create(id: "t1", title: "T", now: clock, defaultWorkerId: "model_opus")

        _ = try await coord.send(message: "first question", toThreadId: "t1")
        // Route the follow-up to a different worker.
        let r2 = try await coord.send(message: "follow up", toThreadId: "t1", requestedWorkerId: "model_grok")
        XCTAssertEqual(r2.workerId, "model_grok")

        let packet = await coord.revealContext(threadId: "t1", packetId: r2.contextPacketId)!
        XCTAssertTrue(packet.text.contains("User: first question"))
        XCTAssertTrue(packet.text.contains("model_opus: owner flag"))
        XCTAssertTrue(packet.includedTurnIds.contains { $0 != "" })
    }

    // MARK: - Failure / timeout are turns too

    func testNonzeroExitLeavesFailedTurnNeedingAttention() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let (coord, store) = makeCoordinator(dir: dir,
            scripts: ["claude": .init(stdout: "", stderr: "boom", exitCode: 2)],
            models: [worker], manifests: [manifest])
        try store.create(id: "t1", title: "T", now: clock)

        let r = try await coord.send(message: "go", toThreadId: "t1")
        XCTAssertEqual(r.outcome?.status, .failed)
        let thread = store.get("t1")!
        XCTAssertEqual(thread.turns[1].status, .failed)
        XCTAssertTrue(thread.needsAttention)
    }

    func testTimeoutLeavesTimedOutTurn() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let (coord, store) = makeCoordinator(dir: dir,
            scripts: ["claude": .init(stdout: "", exitCode: 0, forcesTimeout: true)],
            models: [worker], manifests: [manifest])
        try store.create(id: "t1", title: "T", now: clock)

        _ = try await coord.send(message: "go", toThreadId: "t1")
        XCTAssertEqual(store.get("t1")!.turns[1].status, .timedOut)
    }

    // MARK: - Manual-paste fallback

    func testManualPasteWorkerEntersAwaitingThenCompletes() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let worker = TestSupport.worker("worker_manual", driverId: "manual")
        let (coord, store) = makeCoordinator(dir: dir, scripts: [:],
            models: [worker], manifests: [manualManifest(id: "manual")])
        try store.create(id: "t1", title: "T", now: clock, defaultWorkerId: "worker_manual")

        let r = try await coord.send(message: "draft a plan", toThreadId: "t1")
        XCTAssertTrue(r.awaitingManualPaste)
        XCTAssertNil(r.outcome)
        XCTAssertNotNil(r.manualNoteTurnId)

        // While awaiting: worker turn is running, thread needs attention.
        var thread = store.get("t1")!
        XCTAssertEqual(thread.turn(id: r.workerTurnId)?.status, .running)
        XCTAssertTrue(thread.isRunning)
        XCTAssertTrue(thread.needsAttention)

        // Reveal must expose the exact context the user should hand over.
        let packet = await coord.revealContext(threadId: "t1", packetId: r.contextPacketId)
        XCTAssertTrue(packet!.text.contains("Latest user message:\ndraft a plan"))

        // Paste the reply: worker turn completes, attention clears.
        thread = try await coord.completeManualPaste(
            threadId: "t1", workerTurnId: r.workerTurnId,
            manualNoteTurnId: r.manualNoteTurnId, reply: "Here is the plan."
        )
        XCTAssertEqual(thread.turn(id: r.workerTurnId)?.status, .done)
        XCTAssertEqual(thread.turn(id: r.workerTurnId)?.text, "Here is the plan.")
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention)
    }

    // MARK: - Model resolution

    func testResolutionPrefersRequestedThenDefaultThenLast() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let grok = TestSupport.worker("model_grok", driverId: "grok")
        let (coord, store) = makeCoordinator(dir: dir, scripts: [:],
            models: [opus, grok],
            manifests: [TestSupport.headlessManifest(id: "claude_code", command: "claude"),
                        TestSupport.headlessManifest(id: "grok", command: "grok")])

        let withDefault = try store.create(id: "t1", title: "T", now: clock, defaultWorkerId: "model_grok")
        let resolvedDefault = await coord.resolveWorkerId(for: withDefault, requested: nil)
        XCTAssertEqual(resolvedDefault, "model_grok")

        let requested = await coord.resolveWorkerId(for: withDefault, requested: "model_opus")
        XCTAssertEqual(requested, "model_opus")

        let noDefault = WorkThread(id: "t2", title: "T", createdAt: clock, updatedAt: clock)
        let firstHealthy = await coord.resolveWorkerId(for: noDefault, requested: nil)
        XCTAssertEqual(firstHealthy, "model_opus")   // first enabled headless CLI
    }

    func testSendToMissingThreadThrows() async {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(dir: dir, scripts: [:], models: [], manifests: [])
        do {
            _ = try await coord.send(message: "x", toThreadId: "ghost")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? WorkerChatCoordinator.ChatError, .threadNotFound("ghost"))
        }
    }
}
