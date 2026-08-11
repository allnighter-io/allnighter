import XCTest
@testable import AllnighterEngine

final class ServeRuntimeReceiptsTests: XCTestCase {

    private var tempRoot: URL!
    private var coordDir: URL!
    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipts-\(UUID().uuidString)", isDirectory: true)
        coordDir = tempRoot.appendingPathComponent("Coordinator", isDirectory: true)
        try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            removeIfPresent(tempRoot)
        }
        tempRoot = nil
        coordDir = nil
        try super.tearDownWithError()
    }

    private func makeReceipts() -> ServeRuntimeReceipts {
        ServeRuntimeReceipts(directory: coordDir, clock: { [t0] in t0 })
    }

    // MARK: 1 — Round-trip

    func testRoundTripDaemonIdentityAndRows() {
        let receipts = makeReceipts()
        let rows: [ServeRuntimeReceipts.SchedulerRow] = [
            .init(id: "pmTurnWake", state: .registered),
            .init(id: "pendingWake", state: .registered),
        ]
        let result = receipts.write(daemonId: "abc-123", pid: 42, startedAt: t0, rows: rows)
        XCTAssertNotNil(try? result.get())

        let reading = receipts.read()
        switch reading {
        case .present(let daemonId, let pid, let startedAt, let readRows):
            XCTAssertEqual(daemonId, "abc-123")
            XCTAssertEqual(pid, 42)
            XCTAssertEqual(startedAt, t0)
            XCTAssertEqual(readRows.count, 2)
            let byId = Dictionary(grouping: readRows, by: { $0.id })
            XCTAssertNotNil(byId["pmTurnWake"])
            XCTAssertNotNil(byId["pendingWake"])
            XCTAssertEqual(byId["pmTurnWake"]?.first?.state, .registered)
        default:
            XCTFail("expected .present, got \(reading)")
        }
    }

    func testWriteThenReadKeepsRows() {
        let receipts = makeReceipts()
        _ = receipts.write(daemonId: "d1", pid: 1, startedAt: t0, rows: [
            .init(id: "pmTurnWake", state: .registered),
            .init(id: "boostSeed", state: .registered),
        ])
        let reading = receipts.read()
        switch reading {
        case .present(_, _, _, let rows):
            XCTAssertEqual(Set(rows.map(\.id)), ["pmTurnWake", "boostSeed"])
        default:
            XCTFail("expected present")
        }
    }

    // MARK: 2 — Atomic write: failed write leaves prior receipt intact

    final class ReplaceFailingFileManager: FileManager {
        override func replaceItem(
            at originalItemURL: URL,
            withItemAt newItemURL: URL,
            backupItemName: String?,
            options: FileManager.ItemReplacementOptions,
            resultingItemURL resultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
        ) throws {
            throw NSError(
                domain: "TestReplaceFailure", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "injected replaceItem failure"]
            )
        }
    }

    func testFailedWriteLeavesPriorReceiptIntact() {
        let receipts = makeReceipts()
        let firstRows: [ServeRuntimeReceipts.SchedulerRow] = [
            .init(id: "pmTurnWake", state: .registered),
            .init(id: "pendingWake", state: .registered),
        ]
        _ = receipts.write(daemonId: "first", pid: 1, startedAt: t0, rows: firstRows)

        let reading1 = receipts.read()
        guard case .present(let daemonId1, _, _, let rows1) = reading1 else {
            XCTFail("first write must be readable")
            return
        }
        XCTAssertEqual(daemonId1, "first")
        XCTAssertEqual(Set(rows1.map(\.id)), ["pmTurnWake", "pendingWake"])

        let failingFM = ReplaceFailingFileManager()
        let result2 = receipts.write(
            daemonId: "second", pid: 2, startedAt: t0,
            rows: [.init(id: "pmTurnWake", state: .registered)],
            fileManager: failingFM
        )
        switch result2 {
        case .failure:
            break
        case .success:
            XCTFail("expected write failure with failing file manager")
        }

        let reading2 = receipts.read()
        switch reading2 {
        case .present(let daemonId2, _, _, let rows2):
            XCTAssertEqual(daemonId2, "first", "prior receipt identity must be preserved after failed overwrite")
            XCTAssertEqual(Set(rows2.map(\.id)), ["pmTurnWake", "pendingWake"],
                           "prior receipt rows must be preserved after failed overwrite")
        case .absent:
            XCTFail("prior receipt must not be absent after failed overwrite")
        case .unreadable:
            XCTFail("prior receipt must not be unreadable after failed overwrite")
        }
    }

    // MARK: 3 — Absent

    func testAbsentDirectoryReturnsAbsent() {
        let receipts = makeReceipts()
        let reading = receipts.read()
        switch reading {
        case .absent:
            break
        default:
            XCTFail("expected .absent, got \(reading)")
        }
    }

    // MARK: 4 — Corrupt / unreadable

    func testCorruptFileReturnsUnreadable() {
        let receipts = makeReceipts()
        try! "not json".data(using: .utf8)!.write(to: receipts.runtimeFile)
        let reading = receipts.read()
        switch reading {
        case .unreadable(let reason):
            XCTAssertTrue(reason.contains("corrupt") || reason.contains("truncated"),
                          "expected corrupt/truncated reason, got: \(reason)")
        default:
            XCTFail("expected .unreadable, got \(reading)")
        }
    }

    func testFutureSchemaReturnsUnreadable() {
        let receipts = makeReceipts()
        _ = receipts.write(daemonId: "d", pid: 1, startedAt: t0, rows: [])
        var dict = try! JSONSerialization.jsonObject(
            with: Data(contentsOf: receipts.runtimeFile)
        ) as! [String: Any]
        dict["schemaVersion"] = 99
        try! JSONSerialization.data(withJSONObject: dict).write(to: receipts.runtimeFile)

        let reading = receipts.read()
        switch reading {
        case .unreadable(let reason):
            XCTAssertTrue(reason.contains("future schema") || reason.contains("99"),
                          "expected future schema reason, got: \(reason)")
        default:
            XCTFail("expected .unreadable for future schema, got \(reading)")
        }
    }

    func testAbsentAndUnreadableDistinguishable() {
        let receipts = makeReceipts()
        let absent = receipts.read()
        try! "not json".data(using: .utf8)!.write(to: receipts.runtimeFile)
        let unreadable = receipts.read()

        switch absent {
        case .absent: break
        default: XCTFail("absent expected, got \(absent)")
        }
        switch unreadable {
        case .unreadable: break
        default: XCTFail("unreadable expected, got \(unreadable)")
        }
        XCTAssertNotEqual(absent, unreadable, "absent and unreadable must be distinguishable")
    }

    // MARK: 5 — Optional / required scheduler id reporting

    func testOptionalSchedulerAbsentIsOmittedNotFailed() {
        let receipts = makeReceipts()
        _ = receipts.write(daemonId: "d1", pid: 1, startedAt: t0, rows: [
            .init(id: "pmTurnWake", state: .registered),
        ])
        let reading = receipts.read()
        switch reading {
        case .present(_, _, _, let rows):
            XCTAssertFalse(rows.contains(where: { $0.id == "cloudRelay" }),
                           "cloudRelay must be omitted, not present as failed")
            XCTAssertTrue(ServeRuntimeReceipts.optionalSchedulerIds.contains("cloudRelay"),
                          "cloudRelay must be in optionalSchedulerIds")
        default:
            XCTFail("expected present")
        }
    }

    func testMissingRequiredSchedulerIdsDetectable() {
        let receipts = makeReceipts()
        _ = receipts.write(daemonId: "d1", pid: 1, startedAt: t0, rows: [
            .init(id: "pmTurnWake", state: .registered),
            .init(id: "boostSeed", state: .registered),
        ])
        let reading = receipts.read()
        switch reading {
        case .present(_, _, _, let rows):
            let presentIds = Set(rows.map(\.id))
            let missing = ServeRuntimeReceipts.requiredSchedulerIds.subtracting(presentIds)
            XCTAssertFalse(missing.isEmpty,
                           "at least one required scheduler must be missing to test detectability")
            XCTAssertTrue(missing.contains("pendingWake"),
                          "pendingWake should be missing")
        default:
            XCTFail("expected present")
        }
    }

    func testRequiredIdsDoNotIncludeOptional() {
        XCTAssertFalse(
            ServeRuntimeReceipts.requiredSchedulerIds.contains("cloudRelay"),
            "cloudRelay must not be in requiredSchedulerIds"
        )
        XCTAssertTrue(
            ServeRuntimeReceipts.optionalSchedulerIds.contains("cloudRelay"),
            "cloudRelay must be in optionalSchedulerIds"
        )
    }

    // MARK: 6 — Daemon registration from real start sites

    func testSchedulerNotStartedHasNoRow() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("receipts-daemon-\(UUID().uuidString)")
        defer { removeIfPresent(root) }
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)

        let store = ServeDaemonStore(directory: coordDir)
        let receipts = ServeRuntimeReceipts(directory: coordDir)

        let scheduler = PMTurnWakeScheduler(
            runsRootDirectory: root.appendingPathComponent("Runs", isDirectory: true),
            loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true),
            configurationStore: PMTurnWakeConfigurationStore(
                fileURL: root.appendingPathComponent("pm_turn_delivery.json")
            ),
            ledgerStore: PMTurnWakeReceiptLedgerStore(
                fileURL: root.appendingPathComponent("pm_turn_wake_receipts.json")
            ),
            pollInterval: 0.01
        )

        try await ServeDaemon(
            binaryVersion: "0.1.0",
            store: store,
            receipts: receipts,
            pmTurnWakeScheduler: scheduler
        ).run(untilShutdown: {})

        let reading = receipts.read()
        switch reading {
        case .present(_, _, _, let rows):
            let ids = Set(rows.map(\.id))
            XCTAssertTrue(ids.contains("pmTurnWake"),
                          "pmTurnWake must be registered — it is always started")
            XCTAssertFalse(ids.contains("pendingWake"),
                           "pendingWake must NOT have a row without wakeDependencies")
            XCTAssertFalse(ids.contains("boostSeed"),
                           "boostSeed must NOT have a row without wakeDependencies")
            XCTAssertFalse(ids.contains("cloudRelay"),
                           "cloudRelay must NOT have a row without remoteDependencies")
        default:
            XCTFail("expected .present after daemon run, got \(reading)")
        }
    }

    func testCloudRelayOnlyRegisteredWithRemoteDependencies() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("receipts-cloud-\(UUID().uuidString)")
        defer { removeIfPresent(root) }
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        try FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)

        let store = ServeDaemonStore(directory: coordDir)
        let receipts = ServeRuntimeReceipts(directory: coordDir)

        let scheduler = PMTurnWakeScheduler(
            runsRootDirectory: root.appendingPathComponent("Runs", isDirectory: true),
            loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true),
            configurationStore: PMTurnWakeConfigurationStore(
                fileURL: root.appendingPathComponent("pm_turn_delivery.json")
            ),
            ledgerStore: PMTurnWakeReceiptLedgerStore(
                fileURL: root.appendingPathComponent("pm_turn_wake_receipts.json")
            ),
            pollInterval: 0.01
        )

        try await ServeDaemon(
            binaryVersion: "0.1.0",
            store: store,
            receipts: receipts,
            pmTurnWakeScheduler: scheduler
        ).run(untilShutdown: {})

        let reading = receipts.read()
        switch reading {
        case .present(_, _, _, let rows):
            let ids = Set(rows.map(\.id))
            XCTAssertFalse(ids.contains("cloudRelay"),
                           "cloudRelay must NOT appear without remoteDependencies")
        default:
            XCTFail("expected .present after daemon run, got \(reading)")
        }
    }

    // MARK: 7 — No test writes outside temp directory (implicit)

    func testAllPathsAreInsideTempRoot() {
        let receipts = makeReceipts()
        let runtimePath = receipts.runtimeFile.path
        XCTAssertTrue(runtimePath.hasPrefix(tempRoot.path),
                      "runtime.json must be under temp root, but is at \(runtimePath)")
    }
}

// MARK: - Helpers

private func removeIfPresent(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.removeItem(at: url)
}
