import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// PERF-S01 / S04a / S04b gates: a burst of live streaming deltas must NOT pay the
/// app-wide tax — no full `ThreadStore.list()` reload per delta, and no `thread.json`
/// rewrite per delta. Live text streams into the published `threads` in memory; disk
/// is a throttled checkpoint. Reloads coalesce, list off-main, and publish
/// generation-safe snapshots.
@MainActor
final class ThreadStreamingPerformanceTests: XCTestCase {

    private struct StubRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            CommandResult(stdout: "ok", exitCode: 0)
        }
    }

    private func makeVM() -> (vm: ThreadsViewModel, store: ThreadStore, root: URL) {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-perf-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ThreadStore(rootDirectory: root)
        let vm = ThreadsViewModel(
            store: store,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            toolStatuses: [],
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: CommandRunnerAsStreaming(StubRunner())),
            commandRunner: StubRunner(),
            projectStore: ProjectStore(rootDirectory: root.appendingPathComponent("projects", isDirectory: true))
        )
        return (vm, store, root)
    }

    /// Seed a thread carrying one running worker turn, and publish it into the VM.
    private func seedRunningTurn(_ vm: ThreadsViewModel, _ store: ThreadStore) async throws -> (threadId: String, turnId: String) {
        let thread = try store.create(id: UUID().uuidString, title: "t", now: Date(), workingDir: nil)
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: thread.id, kind: .workerChat, status: .running,
            createdAt: Date(), author: .worker, modelId: "w")
        _ = try store.appendTurn(turn, toThreadId: thread.id, now: Date())
        await vm.reloadAsync()
        return (thread.id, turn.id)
    }

    func testStreamingDeltasDoNotReloadOrRewritePerDelta() async throws {
        let (vm, store, _) = makeVM()
        let seat = try await seedRunningTurn(vm, store)

        PerfCounters.reset()
        let n = 60
        for i in 0..<n {
            vm.applyLiveDelta(threadId: seat.threadId, turnId: seat.turnId,
                              isAnswer: true, text: "token \(i)", truncated: false)
        }

        XCTAssertEqual(PerfCounters.value(.liveDeltaApplied), n, "every delta updates the in-memory turn")
        XCTAssertEqual(PerfCounters.value(.threadsReload), 0, "NO full ThreadStore.list() per delta")
        XCTAssertLessThanOrEqual(PerfCounters.value(.threadJSONWrite), 1,
                                 "durable thread.json is a throttled checkpoint, not per-token")
        // The visible turn carries the latest streamed text without a reload.
        let live = vm.threads.first { $0.id == seat.threadId }?.turn(id: seat.turnId)
        XCTAssertEqual(live?.text, "token \(n - 1)")
    }

    func testRequestReloadCoalescesABurstIntoOneFlush() async throws {
        let (vm, store, _) = makeVM()
        _ = try await seedRunningTurn(vm, store)

        PerfCounters.reset()
        for _ in 0..<8 { vm.requestReload() }
        XCTAssertEqual(PerfCounters.value(.reloadRequested), 8)
        XCTAssertEqual(PerfCounters.value(.reloadCoalesced), 7, "7 of 8 fold into the scheduled flush")
        XCTAssertEqual(PerfCounters.value(.threadsReload), 0, "nothing flushed synchronously")

        // Let the single scheduled flush run.
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(PerfCounters.value(.threadsReload), 1, "exactly one reload for the whole burst")
        XCTAssertEqual(PerfCounters.value(.threadStoreListOffMain), 1,
                       "coalesced reload must list off the MainActor")
    }

    func testLiveDeltaDoesNotInvalidateRailRows() async throws {
        let (vm, store, _) = makeVM()
        let seat = try await seedRunningTurn(vm, store)
        let railBefore = vm.railRows
        XCTAssertFalse(railBefore.isEmpty, "the seeded running thread produces a rail row")

        for i in 0..<30 {
            vm.applyLiveDelta(threadId: seat.threadId, turnId: seat.turnId,
                              isAnswer: true, text: "tok \(i)", truncated: false)
        }
        // PERF-S02: the rail summaries are byte-identical — a streaming delta touches the
        // selected detail (`threads`) only, never the rail.
        XCTAssertEqual(vm.railRows, railBefore, "live deltas must not rebuild/invalidate rail rows")
        XCTAssertEqual(vm.threads.first { $0.id == seat.threadId }?.turn(id: seat.turnId)?.text, "tok 29")
    }

    func testRailRowSearchUsesPrecomputedText() async throws {
        let (vm, store, _) = makeVM()
        let thread = try store.create(id: UUID().uuidString, title: "Rate limiter", now: Date(), workingDir: nil)
        let turn = ThreadTurn(id: UUID().uuidString, threadId: thread.id, kind: .workerChat,
                              status: .done, createdAt: Date(), author: .worker,
                              text: "Use a token BUCKET for bursts")
        _ = try store.appendTurn(turn, toThreadId: thread.id, now: Date())
        await vm.reloadAsync()

        let row = try XCTUnwrap(vm.railRows.first { $0.id == thread.id })
        XCTAssertTrue(row.matchesSearch("bucket"), "search matches turn text via the precomputed summary")
        XCTAssertTrue(row.matchesSearch("RATE"), "search matches the title, case-insensitively")
        XCTAssertFalse(row.matchesSearch("nonexistent"))
    }

    func testLiveDeltaIgnoresSettledTurns() async throws {
        let (vm, store, _) = makeVM()
        let thread = try store.create(id: UUID().uuidString, title: "t", now: Date(), workingDir: nil)
        let done = ThreadTurn(id: UUID().uuidString, threadId: thread.id, kind: .workerChat,
                              status: .done, createdAt: Date(), author: .worker, text: "final")
        _ = try store.appendTurn(done, toThreadId: thread.id, now: Date())
        await vm.reloadAsync()

        PerfCounters.reset()
        let applied = vm.applyLiveDelta(threadId: thread.id, turnId: done.id,
                                        isAnswer: true, text: "late token", truncated: false)
        XCTAssertFalse(applied, "a settled turn never accepts a late streaming delta")
        XCTAssertEqual(vm.threads.first { $0.id == thread.id }?.turn(id: done.id)?.text, "final")
    }

    /// PERF-S04a: default-chat streaming uses `applyLiveDelta(persistCheckpoint: false)` —
    /// the coordinator already flushes durable partials, so the overlay must not reload
    /// via `ThreadStore.list` or write a second thread.json checkpoint per delta.
    /// (`runChat` wires LivePartialObserver → this path and no longer schedules a 150 ms poll.)
    func testDefaultChatStreamingDoesNotPollReload() async throws {
        let (vm, store, _) = makeVM()
        let seat = try await seedRunningTurn(vm, store)

        PerfCounters.reset()
        let n = 60
        for i in 0..<n {
            // Simulate the chat LivePartialObserver path (persistCheckpoint: false).
            let applied = vm.applyLiveDelta(
                threadId: seat.threadId, turnId: seat.turnId,
                isAnswer: true, text: "chat token \(i)", truncated: false,
                persistCheckpoint: false
            )
            XCTAssertTrue(applied)
        }

        XCTAssertEqual(PerfCounters.value(.liveDeltaApplied), n)
        XCTAssertEqual(PerfCounters.value(.threadsReload), 0,
                       "default-chat overlay must not call ThreadStore.list during stream")
        XCTAssertEqual(PerfCounters.value(.threadJSONWrite), 0,
                       "chat path skips VM checkpoint writes; coordinator owns durable flushes")
        let live = vm.threads.first { $0.id == seat.threadId }?.turn(id: seat.turnId)
        XCTAssertEqual(live?.text, "chat token \(n - 1)")
    }

    /// PERF-S04b: a stale background list publish must not clobber newer in-memory live text.
    func testStaleReloadPublishDoesNotClobberLiveDelta() async throws {
        let (vm, store, _) = makeVM()
        let seat = try await seedRunningTurn(vm, store)
        let staleGeneration = vm.publishGenerationForTesting
        let staleSnapshot = vm.threads

        PerfCounters.reset()
        XCTAssertTrue(vm.applyLiveDelta(
            threadId: seat.threadId, turnId: seat.turnId,
            isAnswer: true, text: "live wins", truncated: false,
            persistCheckpoint: false
        ))
        XCTAssertGreaterThan(vm.publishGenerationForTesting, staleGeneration)

        vm.publishListedThreadsForTesting(staleSnapshot, generation: staleGeneration)

        XCTAssertEqual(PerfCounters.value(.reloadPublishDiscarded), 1)
        XCTAssertEqual(PerfCounters.value(.threadsReload), 0, "stale generation must not count as a publish")
        let live = vm.threads.first { $0.id == seat.threadId }?.turn(id: seat.turnId)
        XCTAssertEqual(live?.text, "live wins")
    }

    /// PERF-S04b: full-store `list()` for reload runs off the MainActor.
    func testReloadListsOffMainActor() async throws {
        let (vm, store, _) = makeVM()
        _ = try await seedRunningTurn(vm, store)

        PerfCounters.reset()
        await vm.reloadAsync()

        XCTAssertEqual(PerfCounters.value(.threadsReload), 1)
        XCTAssertEqual(PerfCounters.value(.threadStoreListOffMain), 1)
        XCTAssertEqual(PerfCounters.value(.reloadPublishDiscarded), 0)
    }

    // MARK: - PERF-S06 named aliases (phase doc gate names)

    func testStreamingDeltasDoNotCallThreadStoreListPerDelta() async throws {
        try await testStreamingDeltasDoNotReloadOrRewritePerDelta()
    }

    func testStreamingDeltasDoNotRewriteThreadJSONPerDelta() async throws {
        try await testStreamingDeltasDoNotReloadOrRewritePerDelta()
    }
}
