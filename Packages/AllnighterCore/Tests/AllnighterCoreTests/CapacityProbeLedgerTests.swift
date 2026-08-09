import XCTest
@testable import AllnighterCore

/// Orphan guard for probe children.
///
/// Origin: 103 orphaned vendor CLI processes, oldest six days, load average
/// 12.75 — which broke capacity by starving the probes, silently, for days.
final class CapacityProbeLedgerTests: XCTestCase {

    private var tempRoot: URL!
    private var ledger: CapacityProbeLedger!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        ledger = CapacityProbeLedger(
            fileURL: tempRoot.appendingPathComponent("children.json"))
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        tempRoot = nil
        ledger = nil
        try super.tearDownWithError()
    }

    private func entry(
        child: Int32, pgid: Int32? = nil, owner: Int32 = 500, ticks: UInt64 = 111
    ) -> CapacityProbeLedger.Entry {
        .init(childPID: child, childPGID: pgid ?? child, ownerPID: owner,
              ownerStartTicks: ticks, source: "grok", spawnedAt: t0)
    }

    // MARK: - Verdicts — the part that must never be wrong

    /// A live owner means its probe is presumably still running. Reaping here
    /// would kill a probe mid-flight.
    func testLiveOwnerIsLeftAlone() {
        XCTAssertEqual(
            CapacityProbeLedger.verdict(
                for: entry(child: 900),
                ownerIsAlive: { _, _ in true },
                childIsAlive: { _ in true }),
            .keep)
    }

    /// Owner gone, child gone: nothing to kill, just stop tracking.
    func testDeadOwnerAndDeadChildIsForgotten() {
        XCTAssertEqual(
            CapacityProbeLedger.verdict(
                for: entry(child: 901),
                ownerIsAlive: { _, _ in false },
                childIsAlive: { _ in false }),
            .forget)
    }

    /// The case that cost six days: our owner died, its child did not.
    func testDeadOwnerWithLiveChildIsReaped() {
        XCTAssertEqual(
            CapacityProbeLedger.verdict(
                for: entry(child: 902, pgid: 902),
                ownerIsAlive: { _, _ in false },
                childIsAlive: { _ in true }),
            .reap(pgid: 902))
    }

    /// pgid 0 means "my own process group" and 1 is init. Signalling either
    /// would be catastrophic, so a malformed entry is dropped rather than acted
    /// on — this is the one place a bug could take down the user's session.
    func testMalformedProcessGroupIsNeverSignalled() {
        for pgid in Int32(0)...Int32(1) {
            XCTAssertEqual(
                CapacityProbeLedger.verdict(
                    for: entry(child: 903, pgid: pgid),
                    ownerIsAlive: { _, _ in false },
                    childIsAlive: { _ in true }),
                .forget,
                "pgid \(pgid) must never be signalled")
        }
    }

    /// A pid alone is not an identity. If the recorded owner pid was recycled by
    /// an unrelated process, the owner is GONE and its children are orphans —
    /// the start-time check is what distinguishes that from a live owner.
    func testRecycledOwnerPidCountsAsDead() {
        var sawTicks: UInt64?
        _ = CapacityProbeLedger.verdict(
            for: entry(child: 904, owner: 700, ticks: 999),
            ownerIsAlive: { _, ticks in sawTicks = ticks; return false },
            childIsAlive: { _ in true })
        XCTAssertEqual(sawTicks, 999, "the start time must reach the liveness check")
    }

    // MARK: - Sweep

    func testSweepReapsOnlyOrphansAndPrunesTheLedger() {
        ledger.record(entry(child: 100, owner: 1))   // live owner
        ledger.record(entry(child: 200, owner: 2))   // dead owner, live child
        ledger.record(entry(child: 300, owner: 2))   // dead owner, dead child
        XCTAssertEqual(ledger.load().count, 3)

        var killed: [Int32] = []
        let reaped = ledger.sweep(
            ownerIsAlive: { pid, _ in pid == 1 },
            childIsAlive: { pid in pid != 300 },
            kill: { killed.append($0) })

        XCTAssertEqual(reaped, 1)
        XCTAssertEqual(killed, [200], "only the orphan may be signalled")
        XCTAssertEqual(ledger.load().map(\.childPID), [100],
                       "the live entry survives; both dead-owner entries are pruned")
    }

    func testSweepOnAnEmptyLedgerDoesNothing() {
        var killed: [Int32] = []
        XCTAssertEqual(
            ledger.sweep(ownerIsAlive: { _, _ in false },
                         childIsAlive: { _ in true },
                         kill: { killed.append($0) }),
            0)
        XCTAssertTrue(killed.isEmpty)
    }

    // MARK: - Storage

    func testRecordIsIdempotentPerChild() {
        ledger.record(entry(child: 400))
        ledger.record(entry(child: 400))
        XCTAssertEqual(ledger.load().count, 1, "re-recording a child must not duplicate it")
    }

    func testForgetRemovesOnlyThatChild() {
        ledger.record(entry(child: 500))
        ledger.record(entry(child: 501))
        ledger.forget(childPID: 500)
        XCTAssertEqual(ledger.load().map(\.childPID), [501])
    }

    func testCorruptLedgerReadsAsEmptyRatherThanCrashing() throws {
        try Data("not json".utf8).write(to: ledger.fileURL)
        XCTAssertTrue(ledger.load().isEmpty)
    }

    // MARK: - Real process identity

    /// The identity check has to work against a real process, not just fixtures.
    func testCurrentProcessIsAliveAndIdentityMatches() {
        let owner = CapacityProbeLedger.currentOwner()
        XCTAssertGreaterThan(owner.pid, 0)
        XCTAssertGreaterThan(owner.startTicks, 0, "start time must be readable")
        XCTAssertTrue(CapacityProbeLedger.processIsAlive(owner.pid, owner.startTicks))
        XCTAssertFalse(
            CapacityProbeLedger.processIsAlive(owner.pid, owner.startTicks &+ 1),
            "a mismatched start time must read as dead — that is the pid-reuse guard")
    }
}
