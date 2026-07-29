import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

@MainActor
final class ThreadsViewModelNotificationTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 930_000)
    private let t1 = Date(timeIntervalSinceReferenceDate: 930_100)

    func testMuteSuppressesDelivery() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-notif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let policyURL = root.appendingPathComponent("notification_policy.json")
        let store = NotificationPolicyStore(fileURL: policyURL)
        let delivery = CapturingNotificationDelivery()
        let config = AppConfig.loadConfiguration()
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        let vm = ThreadsViewModel(
            store: threadStore,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: CommandRunnerAsStreaming(StubRunner())),
            isAppActiveForReadClear: { false },
            notificationPolicyStore: store,
            notificationDelivery: delivery
        )
        _ = try threadStore.create(id: "a", title: "t", now: t0)
        _ = try threadStore.appendTurn(userTurn("u1"), toThreadId: "a", now: t0)
        await vm.reloadAsync()
        _ = try threadStore.appendTurn(
            workerTurn("w1", status: .running), toThreadId: "a", now: t0
        )
        await vm.reloadAsync()
        vm.setThreadNotificationsMuted("a", muted: true)
        _ = try threadStore.updateTurn(workerTurn("w1", status: .done), inThreadId: "a", now: t1)
        await vm.reloadAsync()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(delivery.delivered.isEmpty)
    }

    func testSuppressesDeliveryWhenServeDaemonIsAvailable() async throws {
        // URN-S01 "exactly one owner": when `alln serve`'s NotificationScheduler
        // is live, it already delivers this transition — the Mac app must not
        // also fire, or the founder gets the same banner twice.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-notif-daemon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let delivery = CapturingNotificationDelivery()
        let config = AppConfig.loadConfiguration()
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))

        let daemonStore = ServeDaemonStore(directory: root.appendingPathComponent("coordinator", isDirectory: true))
        try daemonStore.save(ServeDaemonRecord(
            daemonId: "daemon-1",
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: t0,
            loopbackHost: "127.0.0.1",
            loopbackPort: 0,
            binaryVersion: "test",
            binaryGitSha: "test",
            contractVersion: ContractRegistry.contractVersion
        ))
        let probe = ServeDaemonProbe(store: daemonStore)
        XCTAssertEqual(probe.health(binaryVersion: "").state, .available)

        let vm = ThreadsViewModel(
            store: threadStore,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: CommandRunnerAsStreaming(StubRunner())),
            isAppActiveForReadClear: { false },
            notificationPolicyStore: NotificationPolicyStore(
                fileURL: root.appendingPathComponent("policy.json")
            ),
            notificationDelivery: delivery,
            serveDaemonProbe: probe
        )
        _ = try threadStore.create(id: "a", title: "t", now: t0)
        _ = try threadStore.appendTurn(userTurn("u1"), toThreadId: "a", now: t0)
        await vm.reloadAsync()
        _ = try threadStore.appendTurn(
            workerTurn("w1", status: .running), toThreadId: "a", now: t0
        )
        await vm.reloadAsync()
        _ = try threadStore.updateTurn(workerTurn("w1", status: .done), inThreadId: "a", now: t1)
        await vm.reloadAsync()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(delivery.delivered.isEmpty)
    }

    func testVisibleUnreadSuppressesNotification() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-notif-vis-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = AppConfig.loadConfiguration()
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        let vm = ThreadsViewModel(
            store: threadStore,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: CommandRunnerAsStreaming(StubRunner())),
            isAppActiveForReadClear: { true },
            notificationPolicyStore: NotificationPolicyStore(
                fileURL: root.appendingPathComponent("policy.json")
            ),
            notificationDelivery: CapturingNotificationDelivery()
        )
        let thread = WorkThread(
            id: "a", title: "t", status: .active, createdAt: t0, updatedAt: t1,
            readCursor: ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0),
            turns: [userTurn("u1"), workerTurn("w1", status: .done)]
        )
        try? threadStore.create(id: thread.id, title: thread.title, now: t0)
        try? threadStore.appendTurn(thread.turns[0], toThreadId: "a", now: t0)
        try? threadStore.appendTurn(thread.turns[1], toThreadId: "a", now: t1)
        await vm.reloadAsync()
        vm.select(thread)
        vm.reportTimelineVisibility(threadId: "a", visibleTurnIds: ["w1"])
        let candidate = NotificationCandidate(
            threadId: "a", turnId: "w1", event: .turnCompleted,
            threadTitle: "t", occurredAt: t1
        )
        XCTAssertTrue(vm.shouldSuppressNotification(candidate: candidate))
    }

    func testFloorManagerStatusCountsAttention() {
        let floor = FloorManagerStatus()
        let threads = [
            WorkThread(
                id: "a", title: "fail", status: .active, createdAt: t0, updatedAt: t1,
                readCursor: .empty(at: t0),
                turns: [workerTurn("w1", status: .failed)]
            ),
            WorkThread(
                id: "b", title: "run", status: .active, createdAt: t0, updatedAt: t1,
                readCursor: .empty(at: t0),
                turns: [workerTurn("w2", status: .running)]
            ),
        ]
        floor.update(from: threads)
        XCTAssertEqual(floor.needsAttentionCount, 1)
        XCTAssertTrue(floor.anyThreadRunning)
        XCTAssertEqual(floor.priorityThreadId, "a")
    }

    private func userTurn(_ id: String) -> ThreadTurn {
        ThreadTurn(
            id: id, threadId: "a", kind: .userMessage, status: .done,
            createdAt: t0, completedAt: t0, author: .user, text: "q"
        )
    }

    private func workerTurn(_ id: String, status: ThreadTurnStatus) -> ThreadTurn {
        ThreadTurn(
            id: id, threadId: "a", kind: .workerChat, status: status,
            createdAt: t1, completedAt: status.isTerminal ? t1 : nil,
            author: .worker, text: "r", modelId: "model_opus"
        )
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

@MainActor
private final class CapturingNotificationDelivery: ThreadNotificationDelivering {
    var delivered: [NotificationCandidate] = []

    func deliver(candidate: NotificationCandidate, workerDisplayName: String?) async {
        delivered.append(candidate)
    }
}
