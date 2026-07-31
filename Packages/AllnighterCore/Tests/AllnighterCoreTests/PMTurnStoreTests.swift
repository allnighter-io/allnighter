import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class PMTurnStoreTests: XCTestCase {
    private var root: URL!
    private var store: PMTurnStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pm-turn-store-\(UUID().uuidString)", isDirectory: true)
        store = PMTurnStore(
            runsRootDirectory: root.appendingPathComponent("Runs", isDirectory: true),
            loopsRootDirectory: root.appendingPathComponent("Loops", isDirectory: true)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        store = nil
        root = nil
    }

    func testWriteReadRoundTripForRunAndRelay() throws {
        let run = makeTurn(kind: .run, subjectId: "run_abc", sequence: 1)
        let relay = makeTurn(kind: .relay, subjectId: "relay_abc", sequence: 1, round: 2, pmMode: "caller")

        let runURL = try store.save(run)
        let relayURL = try store.save(relay)

        XCTAssertEqual(try store.load(kind: .run, subjectId: "run_abc"), run)
        XCTAssertEqual(try store.load(kind: .relay, subjectId: "relay_abc"), relay)
        XCTAssertEqual(runURL.lastPathComponent, "pm-turn.json")
        XCTAssertEqual(relayURL.lastPathComponent, "pm-turn.json")
        XCTAssertTrue(runURL.path.contains("/Runs/run_run_abc/"))
        XCTAssertTrue(relayURL.path.contains("/Loops/relay_abc/"))
    }

    func testNextSequenceAdvancesAndRejectsRegression() throws {
        XCTAssertEqual(try store.nextSequence(for: .run, subjectId: "run_abc"), 1)

        let first = makeTurn(kind: .run, subjectId: "run_abc", sequence: 1)
        try store.save(first)

        XCTAssertEqual(try store.nextSequence(for: .run, subjectId: "run_abc"), 2)
        XCTAssertNoThrow(try store.save(first))
        var regression = makeTurn(kind: .run, subjectId: "run_abc", sequence: 1)
        regression.report = "A different report"
        XCTAssertThrowsError(try store.save(regression)) { error in
            XCTAssertEqual(error as? PMTurnStore.StoreError, .nonMonotonicSequence(existing: 1, attempted: 1))
        }

        try store.save(makeTurn(kind: .run, subjectId: "run_abc", sequence: 2))
        XCTAssertEqual(try store.nextSequence(for: .run, subjectId: "run_abc"), 3)
    }

    func testMissingFileLoadsNil() throws {
        XCTAssertNil(try store.load(kind: .relay, subjectId: "relay_missing"))
    }

    private func makeTurn(
        kind: PMTurnJSON.Kind,
        subjectId: String,
        sequence: Int,
        round: Int? = nil,
        pmMode: String? = nil
    ) -> PMTurnJSON {
        PMTurnJSON(
            kind: kind,
            subjectId: subjectId,
            sequence: sequence,
            round: round,
            createdAt: Date(timeIntervalSince1970: 1_753_824_840),
            reason: kind == .run ? "done" : "awaitingPM",
            lifecycleStatus: kind == .run ? "done" : "awaitingPM",
            report: "Worker report",
            workerRunId: "worker_abc",
            workRecovery: .object(["workState": .string("clean")]),
            nextCommands: ["alln show \(subjectId) --json"],
            notes: [],
            pmMode: pmMode
        )
    }
}
