import XCTest
import AllnighterCore
@testable import AllnighterEngine

private let notifT0 = Date(timeIntervalSinceReferenceDate: 940_000)
private let notifT1 = Date(timeIntervalSinceReferenceDate: 940_100)

final class NotificationSchedulerTests: XCTestCase {
    private let models = [
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both),
    ]

    // MARK: - Full-loop (`tick`) behavior

    func testColdStartDeliversNothing() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        _ = try threadStore.create(id: "a", title: "t", now: notifT0)
        _ = try threadStore.appendTurn(notifUserTurn(), toThreadId: "a", now: notifT0)
        _ = try threadStore.appendTurn(notifWorkerTurn(status: .running), toThreadId: "a", now: notifT0)

        let recorder = RecordingCommandRunner()
        let scheduler = makeScheduler(root: root, threadStore: threadStore, commandRunner: recorder, now: { notifT0 })

        let result = await scheduler.tick(previousThreads: nil, previousRuns: nil, ledger: .init(), tickTime: notifT0)

        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertFalse(result.threads.isEmpty)
    }

    func testTransitionDeliversExactlyOnceWithExpectedArgv() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        _ = try threadStore.create(id: "a", title: "t", now: notifT0)
        _ = try threadStore.appendTurn(notifUserTurn(), toThreadId: "a", now: notifT0)
        _ = try threadStore.appendTurn(notifWorkerTurn(status: .running), toThreadId: "a", now: notifT0)

        let recorder = RecordingCommandRunner()
        let scheduler = makeScheduler(root: root, threadStore: threadStore, commandRunner: recorder, now: { notifT1 })

        let cold = await scheduler.tick(previousThreads: nil, previousRuns: nil, ledger: .init(), tickTime: notifT0)

        _ = try threadStore.updateTurn(notifWorkerTurn(status: .done), inThreadId: "a", now: notifT1)

        let warm = await scheduler.tick(
            previousThreads: cold.threads, previousRuns: cold.runs, ledger: cold.ledger, tickTime: notifT1
        )

        XCTAssertEqual(recorder.calls.count, 1)
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.command, "osascript")
        XCTAssertEqual(call.args.count, 2)
        XCTAssertEqual(call.args[0], "-e")
        XCTAssertTrue(call.args[1].hasPrefix("display notification \""))
        XCTAssertTrue(call.args[1].contains("with title \""))

        let candidate = NotificationCandidate(
            threadId: "a", turnId: "w1", event: .turnCompleted, threadTitle: "t", occurredAt: notifT1
        )
        XCTAssertTrue(warm.ledger.deliveredIds.contains(candidate.id))
    }

    func testRealRestartAfterDeliveryReplaysNothing() async throws {
        // Simulate: a prior daemon session already delivered `turnCompleted`
        // and the thread is durably `.done` on disk. A brand-new scheduler
        // instance (before: nil, i.e. cold start) must not replay it — this
        // is the actual restart shape (a new process never carries the
        // in-memory previous-tick snapshot forward).
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        _ = try threadStore.create(id: "a", title: "t", now: notifT0)
        _ = try threadStore.appendTurn(notifUserTurn(), toThreadId: "a", now: notifT0)
        _ = try threadStore.appendTurn(notifWorkerTurn(status: .done), toThreadId: "a", now: notifT0)

        let ledgerStore = DeliveredNotificationLedgerStore(fileURL: root.appendingPathComponent("delivered.json"))
        let priorCandidate = NotificationCandidate(
            threadId: "a", turnId: "w1", event: .turnCompleted, threadTitle: "t", occurredAt: notifT0
        )
        ledgerStore.save(DeliveredNotificationLedger(deliveredIds: [priorCandidate.id]))

        let recorder = RecordingCommandRunner()
        let scheduler = NotificationScheduler(
            threadStore: threadStore,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            policyStore: NotificationPolicyStore(fileURL: root.appendingPathComponent("policy.json")),
            ledgerStore: ledgerStore,
            commandRunner: recorder,
            models: models,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            now: { notifT1 }
        )

        _ = await scheduler.tick(previousThreads: nil, previousRuns: nil, ledger: ledgerStore.load(), tickTime: notifT1)

        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testRunLoopStopsCleanlyAndDeliversOnTransition() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        _ = try threadStore.create(id: "a", title: "t", now: notifT0)
        _ = try threadStore.appendTurn(notifUserTurn(), toThreadId: "a", now: notifT0)
        _ = try threadStore.appendTurn(notifWorkerTurn(status: .running), toThreadId: "a", now: notifT0)

        let recorder = RecordingCommandRunner()
        let sleeper = TickCountingSleeper(mutateAtCount: 1, cancelAtCount: 2) {
            // Land the transition between tick 1 (cold, captures "running") and
            // tick 2 (should observe the running->done transition and deliver).
            _ = try? threadStore.updateTurn(notifWorkerTurn(status: .done), inThreadId: "a", now: notifT1)
        }
        let scheduler = NotificationScheduler(
            threadStore: threadStore,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            policyStore: NotificationPolicyStore(fileURL: root.appendingPathComponent("policy.json")),
            ledgerStore: DeliveredNotificationLedgerStore(fileURL: root.appendingPathComponent("delivered.json")),
            commandRunner: recorder,
            models: models,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            now: { notifT1 },
            sleeper: sleeper,
            pollInterval: 0
        )

        await scheduler.run { sleeper.isCancelled }

        XCTAssertEqual(recorder.calls.count, 1)
    }

    // MARK: - Pure delivery-eligibility filter (delegates to `NotificationDeliveryFilter`)

    func testAlreadyDeliveredLedgerEntryBlocksRedelivery() {
        var ledger = DeliveredNotificationLedger()
        let candidate = notifSampleCandidate()
        ledger.deliveredIds.insert(candidate.id)

        let result = NotificationScheduler.deliverableCandidates(
            [candidate], ledger: ledger, policy: NotificationPolicy(), now: notifT0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testMutedThreadBlocksDelivery() {
        var policy = NotificationPolicy()
        policy.mutedThreadIds.insert("t1")
        let result = NotificationScheduler.deliverableCandidates(
            [notifSampleCandidate()], ledger: .init(), policy: policy, now: notifT0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testDisabledPolicyBlocksDelivery() {
        let policy = NotificationPolicy(enabled: false)
        let result = NotificationScheduler.deliverableCandidates(
            [notifSampleCandidate()], ledger: .init(), policy: policy, now: notifT0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testQuietHoursBlocksDelivery() {
        let policy = NotificationPolicy(quietHoursEnabled: true, quietHoursStartMinutes: 0, quietHoursEndMinutes: 24 * 60)
        let result = NotificationScheduler.deliverableCandidates(
            [notifSampleCandidate()], ledger: .init(), policy: policy, now: notifT0
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - AppleScript escaping (thread titles are user-controlled text)

    func testAppleScriptEscapingNeutralizesQuotesAndBackslashes() {
        let escaped = NotificationScheduler.appleScriptEscaped(#"say "hi" \ bye"#)
        XCTAssertEqual(escaped, #"say \"hi\" \\ bye"#)
    }

    // MARK: - Helpers

    private func makeScheduler(
        root: URL,
        threadStore: ThreadStore,
        commandRunner: CommandRunner,
        now: @escaping @Sendable () -> Date
    ) -> NotificationScheduler {
        NotificationScheduler(
            threadStore: threadStore,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            policyStore: NotificationPolicyStore(fileURL: root.appendingPathComponent("policy.json")),
            ledgerStore: DeliveredNotificationLedgerStore(fileURL: root.appendingPathComponent("delivered.json")),
            commandRunner: commandRunner,
            models: models,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            now: now
        )
    }

    private func tempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif-sched-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private func notifSampleCandidate() -> NotificationCandidate {
    NotificationCandidate(threadId: "t1", turnId: "w1", event: .turnCompleted, threadTitle: "Thread", occurredAt: notifT0)
}

private func notifUserTurn() -> ThreadTurn {
    ThreadTurn(
        id: "u1", threadId: "a", kind: .userMessage, status: .done,
        createdAt: notifT0, completedAt: notifT0, author: .user, text: "hi"
    )
}

private func notifWorkerTurn(status: ThreadTurnStatus) -> ThreadTurn {
    ThreadTurn(
        id: "w1", threadId: "a", kind: .workerChat, status: status,
        createdAt: notifT0, completedAt: status.isTerminal ? notifT1 : nil,
        author: .worker, text: "reply", workerId: "model_opus"
    )
}

/// Records every invocation (command + args) so a test can assert exact argv,
/// unlike `MockCommandRunner`, which only replays canned output keyed by
/// command name.
private final class RecordingCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Sendable {
        let command: String
        let args: [String]
    }

    private let lock = NSLock()
    private var _calls: [Call] = []

    var calls: [Call] {
        withLock { _calls }
    }

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        record(Call(command: command, args: args))
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    private func record(_ call: Call) {
        withLock { _calls.append(call) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Deterministic sleeper: fires `onMutate` after the `mutateAtCount`-th sleep
/// call (i.e. between two specific ticks) and flips `isCancelled` after the
/// `cancelAtCount`-th — lets a `run(isCancelled:)` loop test land a state
/// change on disk between exactly two ticks without racing real time.
private final class TickCountingSleeper: PendingWakeSleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let mutateAtCount: Int
    private let cancelAtCount: Int
    private let onMutate: () -> Void
    private var cancelled = false

    init(mutateAtCount: Int, cancelAtCount: Int, onMutate: @escaping () -> Void) {
        self.mutateAtCount = mutateAtCount
        self.cancelAtCount = cancelAtCount
        self.onMutate = onMutate
    }

    var isCancelled: Bool {
        withLock { cancelled }
    }

    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
        let currentCount = bumpCount()
        if currentCount == mutateAtCount { onMutate() }
        if currentCount >= cancelAtCount {
            markCancelled()
        }
    }

    private func bumpCount() -> Int {
        withLock {
            count += 1
            return count
        }
    }

    private func markCancelled() {
        withLock { cancelled = true }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
