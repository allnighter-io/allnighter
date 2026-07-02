import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// PERF-S01 gates: a burst of live streaming deltas must NOT pay the app-wide tax —
/// no full `ThreadStore.list()` reload per delta, and no `thread.json` rewrite per
/// delta. Live text streams into the published `threads` in memory; disk is a throttled
/// checkpoint. Reloads coalesce to one flush per runloop tick.
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
    private func seedRunningTurn(_ vm: ThreadsViewModel, _ store: ThreadStore) throws -> (threadId: String, turnId: String) {
        let thread = try store.create(id: UUID().uuidString, title: "t", now: Date(), workingDir: nil)
        let turn = ThreadTurn(
            id: UUID().uuidString, threadId: thread.id, kind: .workerChat, status: .running,
            createdAt: Date(), author: .worker, workerId: "w")
        _ = try store.appendTurn(turn, toThreadId: thread.id, now: Date())
        vm.reload()
        return (thread.id, turn.id)
    }

    func testStreamingDeltasDoNotReloadOrRewritePerDelta() throws {
        let (vm, store, _) = makeVM()
        let seat = try seedRunningTurn(vm, store)

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
        _ = try seedRunningTurn(vm, store)

        PerfCounters.reset()
        for _ in 0..<8 { vm.requestReload() }
        XCTAssertEqual(PerfCounters.value(.reloadRequested), 8)
        XCTAssertEqual(PerfCounters.value(.reloadCoalesced), 7, "7 of 8 fold into the scheduled flush")
        XCTAssertEqual(PerfCounters.value(.threadsReload), 0, "nothing flushed synchronously")

        // Let the single scheduled flush run.
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(PerfCounters.value(.threadsReload), 1, "exactly one reload for the whole burst")
    }

    func testLiveDeltaDoesNotInvalidateRailRows() throws {
        let (vm, store, _) = makeVM()
        let seat = try seedRunningTurn(vm, store)
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

    func testRailRowSearchUsesPrecomputedText() throws {
        let (vm, store, _) = makeVM()
        let thread = try store.create(id: UUID().uuidString, title: "Rate limiter", now: Date(), workingDir: nil)
        let turn = ThreadTurn(id: UUID().uuidString, threadId: thread.id, kind: .workerChat,
                              status: .done, createdAt: Date(), author: .worker,
                              text: "Use a token BUCKET for bursts")
        _ = try store.appendTurn(turn, toThreadId: thread.id, now: Date())
        vm.reload()

        let row = try XCTUnwrap(vm.railRows.first { $0.id == thread.id })
        XCTAssertTrue(row.matchesSearch("bucket"), "search matches turn text via the precomputed summary")
        XCTAssertTrue(row.matchesSearch("RATE"), "search matches the title, case-insensitively")
        XCTAssertFalse(row.matchesSearch("nonexistent"))
    }

    func testLiveDeltaIgnoresSettledTurns() throws {
        let (vm, store, _) = makeVM()
        let thread = try store.create(id: UUID().uuidString, title: "t", now: Date(), workingDir: nil)
        let done = ThreadTurn(id: UUID().uuidString, threadId: thread.id, kind: .workerChat,
                              status: .done, createdAt: Date(), author: .worker, text: "final")
        _ = try store.appendTurn(done, toThreadId: thread.id, now: Date())
        vm.reload()

        PerfCounters.reset()
        let applied = vm.applyLiveDelta(threadId: thread.id, turnId: done.id,
                                        isAnswer: true, text: "late token", truncated: false)
        XCTAssertFalse(applied, "a settled turn never accepts a late streaming delta")
        XCTAssertEqual(vm.threads.first { $0.id == thread.id }?.turn(id: done.id)?.text, "final")
    }
}
