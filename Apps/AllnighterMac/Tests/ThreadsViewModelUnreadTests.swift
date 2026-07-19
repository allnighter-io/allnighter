import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// UNR-S05: selecting a thread does not mark read; visible-prefix read-clear uses
/// `ThreadStore.markReadToLatestVisible` only.
@MainActor
final class ThreadsViewModelUnreadTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000)
    private let t1 = Date(timeIntervalSinceReferenceDate: 800_100)
    private let t2 = Date(timeIntervalSinceReferenceDate: 800_200)
    private let t3 = Date(timeIntervalSinceReferenceDate: 800_300)

    private func makeVM(active: Bool = true) -> (ThreadsViewModel, ThreadStore) {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-unr-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ThreadStore(rootDirectory: root)
        let vm = ThreadsViewModel(
            store: store,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: CommandRunnerAsStreaming(StubRunner())),
            isAppActiveForReadClear: { active }
        )
        return (vm, store)
    }

    private func seedTwoUnreadWorkers(store: ThreadStore) throws {
        _ = try store.create(id: "a", title: "t", now: t0)
        _ = try store.appendTurn(userTurn("u1", at: t0), toThreadId: "a", now: t0)
        _ = try store.appendTurn(workerTurn("w1", status: .done, at: t1), toThreadId: "a", now: t1)
        _ = try store.appendTurn(userTurn("u2", at: t1), toThreadId: "a", now: t1)
        _ = try store.appendTurn(workerTurn("w2", status: .done, at: t2), toThreadId: "a", now: t2)
    }

    private func userTurn(_ id: String, at: Date) -> ThreadTurn {
        ThreadTurn(
            id: id, threadId: "a", kind: .userMessage, status: .done,
            createdAt: at, completedAt: at, author: .user, text: "hi"
        )
    }

    private func workerTurn(_ id: String, status: ThreadTurnStatus, at: Date) -> ThreadTurn {
        ThreadTurn(
            id: id, threadId: "a", kind: .workerChat, status: status,
            createdAt: at, completedAt: status.isTerminal ? at : nil,
            author: .worker, text: "reply", workerId: "model_opus"
        )
    }

    func testSelectingThreadDoesNotMarkRead() async throws {
        let (vm, store) = makeVM()
        try seedTwoUnreadWorkers(store: store)
        await vm.reloadAsync()
        guard let thread = vm.threads.first(where: { $0.id == "a" }) else {
            return XCTFail("missing thread")
        }
        XCTAssertTrue(thread.hasUnread)

        vm.select(thread)
        XCTAssertEqual(vm.selectedThreadId, "a")
        XCTAssertTrue(vm.selectedThread?.hasUnread == true)
    }

    func testVisibleUnreadPrefixClearsRead() async throws {
        let (vm, store) = makeVM()
        try seedTwoUnreadWorkers(store: store)
        await vm.reloadAsync()
        guard let thread = vm.threads.first(where: { $0.id == "a" }) else {
            return XCTFail("missing thread")
        }
        vm.select(thread)

        vm.reportTimelineVisibility(threadId: "a", visibleTurnIds: ["w1", "u2", "w2"])
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(vm.selectedThread?.hasUnread == true)
        XCTAssertEqual(store.get("a")?.readCursor?.lastReadTurnId, "w2")
    }

    func testNonContiguousVisibleDoesNotClearEarlierUnread() async throws {
        let (vm, store) = makeVM()
        try seedTwoUnreadWorkers(store: store)
        await vm.reloadAsync()
        vm.select(vm.threads.first { $0.id == "a" }!)

        vm.reportTimelineVisibility(threadId: "a", visibleTurnIds: ["w2"])
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(vm.selectedThread?.hasUnread == true)
        XCTAssertEqual(store.get("a")?.firstUnreadTurnId, "w1")
    }

    func testInactiveAppDoesNotClearRead() async throws {
        let (vm, store) = makeVM(active: false)
        try seedTwoUnreadWorkers(store: store)
        await vm.reloadAsync()
        vm.select(vm.threads.first { $0.id == "a" }!)

        vm.reportTimelineVisibility(threadId: "a", visibleTurnIds: ["w1", "u2", "w2"])
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(vm.selectedThread?.hasUnread == true)
    }

    private struct StubRunner: CommandRunner {
        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            CommandResult(stdout: "ok", exitCode: 0)
        }
    }
}
