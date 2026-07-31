import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PMTurnWakeSchedulerTests: XCTestCase {
    func testScansRunAndRelayTurnsStreamsFullJSONAndDedupesReceipts() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runs = root.appendingPathComponent("Runs", isDirectory: true)
        let relays = root.appendingPathComponent("Loops", isDirectory: true)
        let turns = PMTurnStore(runsRootDirectory: runs, loopsRootDirectory: relays)
        let run = makeTurn(kind: .run, subjectId: "run_one", sequence: 1)
        let relay = makeTurn(kind: .relay, subjectId: "relay_one", sequence: 2)
        try turns.save(run)
        try turns.save(relay)

        let configuration = PMTurnWakeConfigurationStore(
            fileURL: root.appendingPathComponent("config.json"))
        try configuration.save(.init(pmTurnWake: .init(command: ["/receiver"], retryMaxSeconds: 30)))
        let ledger = PMTurnWakeReceiptLedgerStore(fileURL: root.appendingPathComponent("ledger.json"))
        let invocations = WakeInvocationRecorder()
        let scheduler = PMTurnWakeScheduler(
            runsRootDirectory: runs,
            loopsRootDirectory: relays,
            configurationStore: configuration,
            ledgerStore: ledger,
            invoke: { command, stdin in
                invocations.record(command: command, stdin: stdin)
                return .init(succeeded: true)
            },
            now: { Date(timeIntervalSinceReferenceDate: 10) }
        )

        scheduler.tick()
        scheduler.tick()

        XCTAssertEqual(invocations.calls.count, 2)
        XCTAssertEqual(Set(invocations.calls.map(\.command)), Set([["/receiver"]]))
        let received = try invocations.calls
            .map { try CoreJSON.decode(PMTurnJSON.self, from: $0.stdin) }
            .sorted { $0.subjectId < $1.subjectId }
        XCTAssertEqual(received, [relay, run])
        XCTAssertNotNil(ledger.delivery(for: run))
        XCTAssertEqual(ledger.delivery(for: run)?.status, "delivered")
    }

    func testFailureRetriesThenProjectsFailureAfterRetryWindow() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runs = root.appendingPathComponent("Runs", isDirectory: true)
        let turn = makeTurn(kind: .run, subjectId: "run_fail", sequence: 1)
        try PMTurnStore(runsRootDirectory: runs).save(turn)

        let configuration = PMTurnWakeConfigurationStore(
            fileURL: root.appendingPathComponent("config.json"))
        try configuration.save(.init(pmTurnWake: .init(command: ["/receiver"], retryMaxSeconds: 0)))
        let ledger = PMTurnWakeReceiptLedgerStore(fileURL: root.appendingPathComponent("ledger.json"))
        let scheduler = PMTurnWakeScheduler(
            runsRootDirectory: runs,
            loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true),
            configurationStore: configuration,
            ledgerStore: ledger,
            invoke: { _, _ in .init(succeeded: false, message: "receiver unavailable") },
            now: { Date(timeIntervalSinceReferenceDate: 20) }
        )

        scheduler.tick()

        let delivery = try XCTUnwrap(ledger.delivery(for: turn))
        XCTAssertEqual(delivery.status, "failed")
        XCTAssertEqual(delivery.errorCode, "PM_TURN_WAKE_FAILED")
        XCTAssertEqual(delivery.errorMessage, "receiver unavailable")
        XCTAssertEqual(delivery.attempts, 1)
    }

    func testStatusProjectionIncludesWakeFailure() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let turns = PMTurnStore(runsRootDirectory: root)
        let turn = makeTurn(kind: .run, subjectId: "run_status", sequence: 3)
        try turns.save(turn)
        let ledgerStore = PMTurnWakeReceiptLedgerStore(fileURL: root.appendingPathComponent("ledger.json"))
        let key = PMTurnWakeReceiptLedger.key(kind: .run, subjectId: turn.subjectId, sequence: turn.sequence)
        try ledgerStore.save(.init(entries: [key: .init(
            kind: .run, subjectId: turn.subjectId, sequence: turn.sequence, attempts: 2,
            firstAttemptAt: Date(timeIntervalSinceReferenceDate: 1),
            lastAttemptAt: Date(timeIntervalSinceReferenceDate: 2), errorMessage: "bad receiver"
        )]))

        let projection = PMTurnStatusProjection.load(
            kind: .run, subjectId: turn.subjectId, atPMBoundary: true,
            store: turns, wakeLedgerStore: ledgerStore)

        XCTAssertEqual(projection.pmTurn, turn)
        XCTAssertEqual(projection.pmTurnDelivery?.status, "failed")
        XCTAssertEqual(projection.pmTurnDelivery?.errorCode, "PM_TURN_WAKE_FAILED")
    }

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pm-turn-wake-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTurn(kind: PMTurnJSON.Kind, subjectId: String, sequence: Int) -> PMTurnJSON {
        .init(
            kind: kind, subjectId: subjectId, sequence: sequence,
            createdAt: Date(timeIntervalSinceReferenceDate: 1), reason: "done",
            lifecycleStatus: "done", report: "full report", nextCommands: ["alln show \(subjectId)"]
        )
    }
}

private final class WakeInvocationRecorder: @unchecked Sendable {
    struct Call: Sendable {
        let command: [String]
        let stdin: Data
    }

    private let lock = NSLock()
    private(set) var calls: [Call] = []

    func record(command: [String], stdin: Data) {
        lock.lock()
        calls.append(.init(command: command, stdin: stdin))
        lock.unlock()
    }
}
