import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Unified Run Model: mutating runs take `RunWriteLock` per repo root. These guard
/// the honest refuse path (busy root) and a happy mutating run via `RunService`.
@MainActor
final class ThreadsViewModelMutatingRunTests: XCTestCase {

    private struct StubRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            let answer = "Added retry with backoff; ran tests — all green."
            // Mirror a real file-capture CLI (codex's `-o <path>`, `finalAnswerSource:
            // "output_file"`): write the answer to the output file so
            // `DefaultWorkerRunner.normalize` can read it there, exactly like a real
            // codex run would. A plain-prose stub that only answers on stdout leaves the
            // manifest's declared output file empty, which F2_B.0's file-capture guard
            // (deliberately ignoring noisy stdout for these drivers) then reads as an
            // empty answer. Without this, a real vendor CLI would settle `.done`, but the
            // test double wouldn't — a fixture-realism gap, not a production bug.
            if let flagIndex = args.firstIndex(of: "-o"), args.indices.contains(flagIndex + 1) {
                try? answer.write(toFile: args[flagIndex + 1], atomically: true, encoding: .utf8)
            }
            return CommandResult(stdout: answer, exitCode: 0)
        }
    }

    private func tempDir() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-repo-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeVM(toolStatuses: [ToolProbeRecord], writeLock: RunWriteLockRegistry) -> ThreadsViewModel {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-tvm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stub = StubRunner()
        return ThreadsViewModel(
            store: ThreadStore(rootDirectory: root),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry, models: config.models, toolStatuses: toolStatuses,
            runner: WorkerInvokerFactory.makeWorkerInvoker(
                commandRunner: CommandRunnerAsStreaming(stub),
                routeOpenCodeToServe: false
            ),
            commandRunner: stub,
            writeLock: writeLock,
            projectStore: ProjectStore(rootDirectory: root.appendingPathComponent("projects", isDirectory: true)),
            routeOpenCodeToServe: false
        )
    }

    private func readyExecutorId(_ ready: [ToolProbeRecord]) -> String? {
        let config = AppConfig.loadConfiguration()
        let readyDrivers = Set(ready.filter { $0.status.isSmokeReady }.map(\.driverId))
        return config.models.first {
            $0.enabled && readyDrivers.contains($0.driverId)
            && config.registry.manifest(for: $0)?.kind == .headlessCLI
        }?.id
    }

    private func routing(_ to: String, _ text: String, team: String? = nil) -> ComposeRouting {
        ComposeRouting(team: team, to: to, effort: .med, lane: .code, text: text)
    }

    private func firstRunTurn(_ vm: ThreadsViewModel, kind: ThreadTurnKind) async throws -> ThreadTurn? {
        for _ in 0..<300 {
            if let t = vm.selectedThread?.turns.first(where: { $0.kind == kind }), t.status.isTerminal {
                return t
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        return vm.selectedThread?.turns.first { $0.kind == kind }
    }

    func testChatWithoutProjectDoesNotCreateUnboundThread() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let vm = makeVM(toolStatuses: ready, writeLock: RunWriteLockRegistry())
        let to = try XCTUnwrap(readyExecutorId(ready))
        vm.sendRouting(routing(to, "hello without a repo"), createThread: true)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.threads.isEmpty)
        XCTAssertNil(vm.selectedThreadId)
    }

    func testBusyWriteLockQueuesConcurrentMutatingRun() async throws {
        let reg = RunWriteLockRegistry()
        let dir = tempDir()
        let key = RunWriteLock.key(repoRoot: dir)
        let token = await reg.acquire(key)
        XCTAssertNotNil(token, "precondition: write lock is held")

        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let vm = makeVM(toolStatuses: ready, writeLock: reg)
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        _ = vm.newThread(title: "t", workingDir: dir)
        XCTAssertNotNil(vm.selectedThread?.projectId)

        // One writer per repo: a busy root QUEUES the run, it does not refuse. While the lock
        // is held elsewhere, the run must stay pending (running) — never fail.
        vm.sendRouting(routing(to, "edit the repo concurrently"))
        try await Task.sleep(nanoseconds: 200_000_000)
        let waiting = vm.selectedThread?.turns.first { $0.kind == .mutatingRun }
        XCTAssertEqual(waiting?.status, .running, "a busy repo root queues (waits), never refuses")

        // Release the holder — the queued run is granted the lock and runs to completion.
        await reg.release(key, token: try XCTUnwrap(token))
        let settled = try await firstRunTurn(vm, kind: .mutatingRun)
        let turn = try XCTUnwrap(settled)
        XCTAssertEqual(turn.status, .done, "the queued run completes once the lock frees")
    }

    func testMutatingRunCompletesWithDurableTeamRun() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        let dir = tempDir()
        let vm = makeVM(toolStatuses: ready, writeLock: RunWriteLockRegistry())
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(routing(to, "add exponential backoff retry"))
        let settled = try await firstRunTurn(vm, kind: .mutatingRun)
        let turn = try XCTUnwrap(settled)
        XCTAssertEqual(turn.status, .done)
        let runId = try XCTUnwrap(turn.runId)
        let run = try XCTUnwrap(vm.teamRun(forRunId: runId))
        XCTAssertFalse(run.answers.isEmpty)
    }

    func testWriteLockReleasedAfterRunSettles() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready))
        let dir = tempDir()
        let reg = RunWriteLockRegistry()
        let vm = makeVM(toolStatuses: ready, writeLock: reg)
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(routing(to, "first order"))
        _ = try await firstRunTurn(vm, kind: .mutatingRun)
        let heldAfter = await reg.isHeld(RunWriteLock.key(repoRoot: dir))
        XCTAssertFalse(heldAfter, "the write lock must be released once the run settles")
    }
}
