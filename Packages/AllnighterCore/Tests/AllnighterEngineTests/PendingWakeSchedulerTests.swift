import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Progress-wiring proofs for `PendingWakeScheduler` (ASR-S03e2a).
/// Extends the existing class in `PendingWakeTests.swift` so the §8 filter
/// `PendingWakeSchedulerTests` still selects these cases.
extension PendingWakeSchedulerTests {

    private final class RecordingSleeper: PendingWakeSleeper, @unchecked Sendable {
        var sleepCalls: [Date] = []

        func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
            sleepCalls.append(until)
        }
    }

    private final class AlwaysFailingFileManager: FileManager, @unchecked Sendable {
        override func createDirectory(
            at url: URL,
            withIntermediateDirectories createIntermediates: Bool,
            attributes: [FileAttributeKey: Any]? = nil
        ) throws {
            throw NSError(
                domain: "TestWriteFailure",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "injected write failure"]
            )
        }
    }

    private var progressModels: [Model] {
        [
            Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both),
        ]
    }

    func testWaitingNextWakeAtEqualsDeadlineActuallySleptTo() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wake-progress-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let pendingRoot = root.appendingPathComponent("Pending", isDirectory: true)
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)

        let store = PendingStore(rootDirectory: pendingRoot)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nextWake = Date(timeIntervalSince1970: 1_700_000_100)
        let service = PendingService(store: store, models: progressModels, now: { now })
        let item = try service.add(.init(prompt: "Review", workerToken: "model_opus", submit: true))
        var saved = try XCTUnwrap(store.load(id: item.id))
        saved.projectId = "proj1"
        saved.resume = PendingResume(reason: .cooldown, wakeAfter: nextWake)
        try store.save(saved)

        let receipts = ServeRuntimeReceipts(directory: coordDir)
        let progress = ServeSchedulerProgress(
            receipts: receipts,
            daemonId: "d-wake",
            pid: 9,
            startedAt: now
        )
        progress.registered(id: PendingWakeScheduler.progressId)

        let sleeper = RecordingSleeper()
        let scheduler = PendingWakeScheduler(
            store: store,
            models: progressModels,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "ok", exitCode: 0)]),
            now: { now },
            sleeper: sleeper,
            jitterSeconds: 0,
            progress: progress
        )

        let flag = ShutdownFlag()
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            flag.fire()
        }
        await scheduler.run { flag.isCancelled }

        XCTAssertEqual(sleeper.sleepCalls.first, nextWake, "scheduler must sleep to the planned nextWake")

        switch receipts.read() {
        case .present(_, _, _, let rows):
            let row = try XCTUnwrap(rows.first { $0.id == PendingWakeScheduler.progressId })
            XCTAssertEqual(row.state, .waiting)
            XCTAssertEqual(
                row.nextWakeAt,
                nextWake,
                "nextWakeAt must be the deadline actually slept to, not a recomputed one"
            )
        default:
            XCTFail("expected progress receipt after waiting report")
        }
    }

    func testFailingWriterLeavesSchedulerLoopingToSameDeadline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wake-fail-write-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let pendingRoot = root.appendingPathComponent("Pending", isDirectory: true)
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)

        let store = PendingStore(rootDirectory: pendingRoot)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nextWake = Date(timeIntervalSince1970: 1_700_000_100)
        let service = PendingService(store: store, models: progressModels, now: { now })
        let item = try service.add(.init(prompt: "Review", workerToken: "model_opus", submit: true))
        var saved = try XCTUnwrap(store.load(id: item.id))
        saved.projectId = "proj1"
        saved.resume = PendingResume(reason: .cooldown, wakeAfter: nextWake)
        try store.save(saved)

        let receipts = ServeRuntimeReceipts(directory: coordDir)
        let progress = ServeSchedulerProgress(
            receipts: receipts,
            daemonId: "d-fail",
            pid: 11,
            startedAt: now,
            fileManager: AlwaysFailingFileManager()
        )

        let sleeper = RecordingSleeper()
        let scheduler = PendingWakeScheduler(
            store: store,
            models: progressModels,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "ok", exitCode: 0)]),
            now: { now },
            sleeper: sleeper,
            jitterSeconds: 0,
            progress: progress
        )

        let flag = ShutdownFlag()
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            flag.fire()
        }
        await scheduler.run { flag.isCancelled }

        XCTAssertFalse(sleeper.sleepCalls.isEmpty, "failing progress writer must not stop the wake loop")
        XCTAssertEqual(
            sleeper.sleepCalls.first,
            nextWake,
            "scheduler must still sleep to the same planned deadline when recording fails"
        )
    }
}
