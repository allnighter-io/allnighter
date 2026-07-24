import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PN-S01: `PanelState` + `PanelStateStore` — round-trip, parked-survives-reconcile,
/// running-with-dead-owner reconciles to a settled partial round
/// (`docs/phases/Pilot_Panel.md`).
final class PanelStateStoreTests: XCTestCase {

    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("panel-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func samplePanel(
        id: String = "panel_test",
        status: PanelState.Status = .awaitingPM,
        rounds: [PanelRound] = []
    ) -> PanelState {
        PanelState(
            id: id,
            projectRoot: "/tmp/proj",
            projectId: "proj_1",
            targetPath: "docs/phases/X.md",
            teamId: "code_spec_review",
            seats: [
                PanelSeat(workerId: "model_opus", lens: "adversary", lensInstruction: "Find holes."),
                PanelSeat(workerId: "model_sonnet", lens: "simplicity"),
            ],
            status: status,
            maxRounds: 5,
            rounds: rounds,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: nil
        )
    }

    // MARK: - Round-trip

    func testRoundTripSaveLoad() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        let finding = Finding(
            claim: "Scope is too wide",
            severity: .high,
            evidence: "line 40",
            proposedChange: "Cut v1 boundary"
        )
        let round = PanelRound(
            roundNumber: 1,
            targetHash: PanelState.contentHash(of: Data("hello".utf8)),
            brief: "Scrutinize this target",
            briefSource: .builtin,
            seatResults: [
                SeatResult(
                    workerId: "model_opus",
                    lens: "adversary",
                    status: .done,
                    findings: [finding],
                    noMaterialFindings: false,
                    report: "Found one hole.\n\n```json\n{}\n```",
                    runId: "run_1"
                ),
                SeatResult(
                    workerId: "model_sonnet",
                    lens: "simplicity",
                    status: .done,
                    findings: [],
                    noMaterialFindings: true,
                    reason: "Target is already minimal",
                    report: "Nothing material."
                ),
            ],
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let panel = samplePanel(rounds: [round])
        try store.save(panel)

        let loaded = store.load(id: panel.id)
        XCTAssertEqual(loaded, panel)
        XCTAssertEqual(loaded?.rounds.first?.seatResults.count, 2)
        XCTAssertEqual(loaded?.rounds.first?.seatResults.first?.findings?.first?.severity, .high)
        XCTAssertTrue(loaded?.rounds.first?.seatResults[1].noMaterialFindings == true)
    }

    func testContentHashIsSHA256OfBytes() {
        let data = Data("panel-target".utf8)
        let hash = PanelState.contentHash(of: data)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(hash, PanelState.contentHash(of: data), "deterministic")
        XCTAssertNotEqual(hash, PanelState.contentHash(of: Data("other".utf8)))
    }

    func testListNewestFirst() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        var older = samplePanel(id: "panel_old")
        older.createdAt = Date(timeIntervalSince1970: 100)
        var newer = samplePanel(id: "panel_new")
        newer.createdAt = Date(timeIntervalSince1970: 200)
        try store.save(older)
        try store.save(newer)

        let listed = store.list()
        XCTAssertEqual(listed.map(\.id), ["panel_new", "panel_old"])
    }

    // MARK: - owner.pid / parked

    func testAwaitingPMDoesNotWriteOwnerPid() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        try store.save(samplePanel(status: .awaitingPM))
        let ownerURL = root.appendingPathComponent("panel_test/owner.pid")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerURL.path),
                       "awaitingPM is parked/unowned — no owner.pid")
    }

    func testRunningWritesOwnerPidAndClearingOnPark() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        try store.save(samplePanel(status: .running))
        let ownerURL = root.appendingPathComponent("panel_test/owner.pid")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerURL.path))
        let raw = try String(contentsOf: ownerURL, encoding: .utf8)
        XCTAssertEqual(Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                       ProcessInfo.processInfo.processIdentifier)

        try store.save(samplePanel(status: .awaitingPM))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerURL.path),
                       "parking clears owner.pid")
    }

    // MARK: - Reconcile

    func testParkedSurvivesReconcile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        let parked = samplePanel(status: .awaitingPM)
        try store.save(parked)
        // Even with a stale owner.pid on disk (should not exist, but force one),
        // awaitingPM must never reconcile.
        let ownerURL = root.appendingPathComponent("panel_test/owner.pid")
        try Data("999999999".utf8).write(to: ownerURL)

        let after = store.reconcileIfOrphaned(parked)
        XCTAssertEqual(after.status, .awaitingPM)
        XCTAssertNil(after.note)
        XCTAssertEqual(store.load(id: parked.id)?.status, .awaitingPM)
    }

    func testRunningWithDeadOwnerReconcilesToSettledPartialRound() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        let openRound = PanelRound(
            roundNumber: 1,
            targetHash: "abc",
            brief: "Spec review",
            briefSource: .builtin,
            seatResults: [
                SeatResult(
                    workerId: "model_opus",
                    lens: "adversary",
                    status: .done,
                    findings: [
                        Finding(claim: "got here", severity: .low, evidence: "e")
                    ],
                    report: "partial arrival"
                ),
                // Seat never finished — empty report while still marked done means
                // dispatch was cut short; reconcile promotes it to timedOut.
                SeatResult(
                    workerId: "model_sonnet",
                    lens: "simplicity",
                    status: .done,
                    report: ""
                ),
            ],
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            finishedAt: nil
        )
        let running = samplePanel(id: "panel_orphan", status: .running, rounds: [openRound])
        try store.save(running)

        // Overwrite owner.pid with a dead pid so isOwnerDead returns true.
        // (pid 1 is launchd on macOS and stays alive — use an impossibly high pid.)
        let ownerURL = root.appendingPathComponent("panel_orphan/owner.pid")
        try Data("999999999".utf8).write(to: ownerURL)
        XCTAssertTrue(store.isOwnerDead(id: "panel_orphan"))

        let fixedNow = Date(timeIntervalSince1970: 1_700_000_999)
        let reconciled = store.reconcileIfOrphaned(running, now: { fixedNow })

        XCTAssertEqual(reconciled.status, .awaitingPM)
        XCTAssertEqual(reconciled.note, PanelState.orphanReconciledNote)
        XCTAssertEqual(reconciled.rounds.count, 1)
        XCTAssertEqual(reconciled.rounds[0].finishedAt, fixedNow)
        XCTAssertEqual(reconciled.rounds[0].seatResults[0].status, .done)
        XCTAssertEqual(reconciled.rounds[0].seatResults[0].report, "partial arrival")
        XCTAssertEqual(reconciled.rounds[0].seatResults[1].status, .timedOut)

        let reloaded = store.load(id: "panel_orphan")
        XCTAssertEqual(reloaded?.status, .awaitingPM)
        XCTAssertEqual(reloaded?.rounds[0].finishedAt, fixedNow)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ownerURL.path),
            "parked save clears owner.pid"
        )
    }

    func testLiveRunningOwnerDoesNotReconcile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)

        let running = samplePanel(status: .running)
        try store.save(running) // writes this process's live pid
        XCTAssertFalse(store.isOwnerDead(id: running.id))

        let after = store.reconcileIfOrphaned(running)
        XCTAssertEqual(after.status, .running)
        XCTAssertNil(after.note)
    }

    func testAllEmptySeatsSettleEvenWhenOwnerIsStillLive() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PanelStateStore(rootDirectory: root)
        let openRound = PanelRound(
            roundNumber: 1,
            targetHash: "abc",
            brief: "Spec review",
            briefSource: .builtin,
            seatResults: [
                SeatResult(workerId: "model_opus", lens: "adversary", status: .empty, report: ""),
                SeatResult(workerId: "model_sonnet", lens: "simplicity", status: .empty, report: ""),
            ],
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let running = samplePanel(id: "panel_empty", status: .running, rounds: [openRound])
        try store.save(running) // owner.pid names this live test process
        XCTAssertFalse(store.isOwnerDead(id: running.id))

        let fixedNow = Date(timeIntervalSince1970: 1_700_000_999)
        let settled = store.settleIfAllSeatsTerminal(running, now: { fixedNow })

        XCTAssertEqual(settled.status, .awaitingPM)
        XCTAssertEqual(settled.note, PanelStateStore.terminalSeatReconciledNote)
        XCTAssertEqual(settled.rounds[0].finishedAt, fixedNow)
        XCTAssertTrue(settled.rounds[0].seatResults.allSatisfy { $0.status == .failed })
        XCTAssertTrue(settled.rounds[0].seatResults.allSatisfy {
            $0.reason == "worker exited without a report; check source readiness and rerun this seat"
        })
    }

    func testMakeIdPrefix() {
        let id = PanelState.makeId()
        XCTAssertTrue(id.hasPrefix("panel_"))
        XCTAssertGreaterThan(id.count, "panel_".count)
    }
}
