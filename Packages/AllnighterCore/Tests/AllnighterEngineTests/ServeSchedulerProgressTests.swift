import XCTest
@testable import AllnighterEngine

final class ServeSchedulerProgressTests: XCTestCase {

    private var tempRoot: URL!
    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_720_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_720_000_200)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    private func makeReceipts() -> ServeRuntimeReceipts {
        ServeRuntimeReceipts(directory: tempRoot, clock: { [t0] in t0 })
    }

    private func makeProgress(
        clock: @escaping @Sendable () -> Date,
        fileManager: FileManager = .default
    ) -> (ServeRuntimeReceipts, ServeSchedulerProgress) {
        let receipts = makeReceipts()
        let progress = ServeSchedulerProgress(
            receipts: receipts,
            daemonId: "daemon-1",
            pid: 42,
            startedAt: t0,
            clock: clock,
            fileManager: fileManager
        )
        return (receipts, progress)
    }

    private func row(
        _ receipts: ServeRuntimeReceipts,
        id: String
    ) -> ServeRuntimeReceipts.SchedulerRow? {
        switch receipts.read() {
        case .present(_, _, _, let rows):
            return rows.first { $0.id == id }
        default:
            return nil
        }
    }

    // MARK: - §9 concurrency kill test

    /// N reporters mutating different ids concurrently — final file must contain every id.
    /// Written first against `ServeRuntimeReceipts.register` (lost rows under RMW);
    /// now proves the serialized recorder keeps every id.
    func testConcurrentRegisterOfDifferentIdsKeepsEveryId() async {
        let receipts = makeReceipts()
        let progress = ServeSchedulerProgress(
            receipts: receipts,
            daemonId: "daemon-concurrency",
            pid: 7,
            startedAt: t0
        )
        let ids = (0..<16).map { "scheduler-\($0)" }
        let wakeAt = t1

        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    for _ in 0..<8 {
                        progress.registered(id: id)
                        progress.attempting(id: id)
                        progress.waiting(id: id, until: wakeAt)
                    }
                }
            }
        }

        let reading = receipts.read()
        switch reading {
        case .present(_, _, _, let rows):
            let present = Set(rows.map(\.id))
            XCTAssertEqual(
                present,
                Set(ids),
                "every concurrently registered id must survive; missing=\(Set(ids).subtracting(present)) extra=\(present.subtracting(Set(ids)))"
            )
        default:
            XCTFail("expected .present after concurrent progress writes, got \(reading)")
        }
    }

    // MARK: - Honest field transitions

    func testSucceededAfterFailedClearsLastErrorKeepsLastAttemptAt() {
        let clock = ClockBox(t0)
        let (receipts, progress) = makeProgress(clock: { clock.now() })

        progress.registered(id: "pendingWake")
        progress.attempting(id: "pendingWake")
        let attemptAt = row(receipts, id: "pendingWake")?.lastAttemptAt
        XCTAssertEqual(attemptAt, t0)

        clock.set(t1)
        progress.failed(id: "pendingWake", error: "wake pass refused")
        XCTAssertEqual(row(receipts, id: "pendingWake")?.lastError, "wake pass refused")
        XCTAssertEqual(row(receipts, id: "pendingWake")?.lastAttemptAt, attemptAt)

        clock.set(t2)
        progress.succeeded(id: "pendingWake")
        let after = row(receipts, id: "pendingWake")
        XCTAssertNil(after?.lastError, "succeeded must clear lastError")
        XCTAssertEqual(after?.lastAttemptAt, attemptAt, "succeeded must keep lastAttemptAt")
        XCTAssertEqual(after?.lastSuccessAt, t2)
    }

    func testFailedAfterSucceededKeepsLastSuccessAt() {
        let clock = ClockBox(t0)
        let (receipts, progress) = makeProgress(clock: { clock.now() })

        progress.registered(id: "pendingWake")
        progress.attempting(id: "pendingWake")
        clock.set(t1)
        progress.succeeded(id: "pendingWake")
        let successAt = row(receipts, id: "pendingWake")?.lastSuccessAt
        XCTAssertEqual(successAt, t1)

        clock.set(t2)
        progress.failed(id: "pendingWake", error: "sleep interrupted")
        let after = row(receipts, id: "pendingWake")
        XCTAssertEqual(after?.lastSuccessAt, successAt, "failed must keep lastSuccessAt")
        XCTAssertEqual(after?.lastError, "sleep interrupted")
        XCTAssertEqual(after?.state, .failed)
    }

    // MARK: - lastError bound

    func testLastErrorTruncatedAt200Characters() {
        let (receipts, progress) = makeProgress(clock: { [t0] in t0 })
        let long = String(repeating: "e", count: 350)
        progress.failed(id: "pendingWake", error: long)
        let stored = row(receipts, id: "pendingWake")?.lastError
        XCTAssertEqual(stored?.count, ServeSchedulerProgress.maxErrorLength)
        XCTAssertEqual(stored, String(long.prefix(ServeSchedulerProgress.maxErrorLength)))
    }

    // MARK: - Failing writer is non-fatal to callers of the recorder

    final class AlwaysFailingFileManager: FileManager, @unchecked Sendable {
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

    func testFailingWriterDoesNotThrowFromProgressMethods() {
        let (_, progress) = makeProgress(
            clock: { [t0] in t0 },
            fileManager: AlwaysFailingFileManager()
        )
        progress.registered(id: "pendingWake")
        progress.attempting(id: "pendingWake")
        progress.succeeded(id: "pendingWake")
        progress.failed(id: "pendingWake", error: "x")
        progress.waiting(id: "pendingWake", until: t1)
        progress.stopped(id: "pendingWake")
    }

    func testAllPathsAreInsideTempRoot() {
        let receipts = makeReceipts()
        XCTAssertTrue(
            receipts.runtimeFile.path.hasPrefix(tempRoot.path),
            "runtime.json must be under temp root, but is at \(receipts.runtimeFile.path)"
        )
    }
}

// MARK: - Clock

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ date: Date) {
        lock.lock()
        value = date
        lock.unlock()
    }
}
