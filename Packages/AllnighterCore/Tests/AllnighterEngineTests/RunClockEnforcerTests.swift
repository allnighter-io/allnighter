import XCTest
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// RLR-S05 — four clocks (L8) fire → `timedOut` + kill tree, and CLI flag parse.
final class RunClockEnforcerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ProcessOwnership.terminateSignalHook = nil
    }
    override func tearDown() {
        ProcessOwnership.terminateSignalHook = nil
        super.tearDown()
    }

    private func tempStore() throws -> (support: URL, runs: RunStore) {
        let support = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("run-clock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (support, RunStore(rootDirectory: support.appendingPathComponent("Runs", isDirectory: true)))
    }

    private func liveSelfWorker() throws -> ProcessOwnership.OwnerIdentity {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        return .init(pid: pid, pgid: pid, startTimeTicks: ticks, kind: .devTurn)
    }

    // MARK: - Evaluate

    func testEvaluatePrefersEarliestDeadline() {
        let created = Date(timeIntervalSince1970: 1_000)
        let budgets = RunClockBudgets(
            handshakeTimeoutSeconds: 60,
            firstActivityTimeoutSeconds: 120,
            idleTimeoutSeconds: 30,
            wallTimeoutSeconds: 3600
        )
        // Idle overdue first.
        let fired = RunClockEnforcer.evaluate(
            budgets: budgets,
            createdAt: created,
            lastActivityAt: created.addingTimeInterval(10),
            now: created.addingTimeInterval(50),
            lifecycle: .running,
            phase: .working,
            idleBudgetSeconds: 30
        )
        XCTAssertEqual(fired, .idle)
    }

    func testEvaluateWallOverIdleWhenWallEarlier() {
        let created = Date(timeIntervalSince1970: 1_000)
        let budgets = RunClockBudgets(
            handshakeTimeoutSeconds: 60,
            firstActivityTimeoutSeconds: 120,
            idleTimeoutSeconds: 9_000,
            wallTimeoutSeconds: 100
        )
        let fired = RunClockEnforcer.evaluate(
            budgets: budgets,
            createdAt: created,
            lastActivityAt: created.addingTimeInterval(10),
            now: created.addingTimeInterval(101),
            lifecycle: .running,
            phase: .working
        )
        XCTAssertEqual(fired, .wall)
    }

    // MARK: - Fire (operator-vs-clock asymmetry)

    func testFireStampsTimedOutTerminalEvenWhenWorkerStillAlive() throws {
        let (support, runs) = try tempStore()
        defer { try? FileManager.default.removeItem(at: support) }

        let r = TeamRun(
            id: "clk-fire-1", prompt: "p", status: .running, phase: .working,
            createdAt: Date(), repoRoot: "/tmp/repo",
            clockBudgets: RunClockBudgets()
        )
        try runs.save(r, models: [])
        let dir = try runs.runDirectory(forRunId: "clk-fire-1")
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "r1", record: try liveSelfWorker().asRecord()),
            in: dir
        )

        // Suppress real TERM so this process stays identity-alive → partial.
        ProcessOwnership.terminateSignalHook = { _ in }

        let fired = try XCTUnwrap(
            RunClockEnforcer.fire(clock: .idle, runDirectory: dir, runStore: runs)
        )
        XCTAssertEqual(fired.outcome, .partial)
        XCTAssertEqual(fired.survivors, ["r1"])
        XCTAssertEqual(fired.clock, .idle)

        let after = try XCTUnwrap(runs.loadRaw(runId: "clk-fire-1"))
        XCTAssertEqual(after.status, .timedOut)
        XCTAssertEqual(after.endReason, .timedOut)
        XCTAssertEqual(after.killOutcome, .partial)
        XCTAssertTrue(after.status.isTerminal)
        XCTAssertEqual(after.status.lifecycle, .timedOut)

        // Contradiction surface must derive from retained live receipts.
        let surface = ProcessOwnershipSurface(runStore: runs)
        let row = try XCTUnwrap(surface.list().processes.first { $0.id == "clk-fire-1" })
        XCTAssertEqual(row.contradiction, RunContradiction.terminalWithLiveOwnership.rawValue)
        XCTAssertEqual(row.killOutcome, KillOutcome.partial.rawValue)
    }

    func testFireStoppedWhenRecordedWorkerDead() throws {
        let (support, runs) = try tempStore()
        defer { try? FileManager.default.removeItem(at: support) }

        let r = TeamRun(
            id: "clk-fire-2", prompt: "p", status: .running, phase: .working,
            createdAt: Date(), repoRoot: "/tmp/repo"
        )
        try runs.save(r, models: [])
        let dir = try runs.runDirectory(forRunId: "clk-fire-2")
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_100_199, pgid: 9_301, startTimeTicks: 1, kind: .devTurn)
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "r1", record: dead.asRecord()), in: dir)

        ProcessOwnership.terminateSignalHook = { _ in }
        let fired = try XCTUnwrap(
            RunClockEnforcer.fire(clock: .wall, runDirectory: dir, runStore: runs)
        )
        XCTAssertEqual(fired.outcome, .stopped)
        let after = try XCTUnwrap(runs.loadRaw(runId: "clk-fire-2"))
        XCTAssertEqual(after.status, .timedOut)
        XCTAssertEqual(after.endReason, .timedOut)
        XCTAssertEqual(after.killOutcome, .stopped)
        XCTAssertNil(
            ProcessOwnershipSurface(runStore: runs).list().processes
                .first { $0.id == "clk-fire-2" }?.contradiction
        )
    }

    // MARK: - CLI parse

    func testParseHandshakeAndWallTimeoutFlags() {
        let ok = RunCLI.parsePositiveTimeoutSeconds("60", flag: "--handshake-timeout")
        XCTAssertEqual(ok.value, 60)
        XCTAssertNil(ok.error)

        let wall = RunCLI.parsePositiveTimeoutSeconds("3600", flag: "--wall-timeout")
        XCTAssertEqual(wall.value, 3600)

        for raw in ["0", "-1", "abc"] {
            let bad = RunCLI.parsePositiveTimeoutSeconds(raw, flag: "--handshake-timeout")
            XCTAssertNil(bad.value, raw)
            XCTAssertNotNil(bad.error, raw)
            XCTAssertTrue(bad.error?.contains("--handshake-timeout") == true, bad.error ?? raw)
        }

        let omitted = RunCLI.parsePositiveTimeoutSeconds(nil, flag: "--wall-timeout")
        XCTAssertNil(omitted.value)
        XCTAssertNil(omitted.error)
    }

    func testClockBudgetsResolvedDefaults() {
        let d = RunClockBudgets.resolved()
        XCTAssertEqual(d.handshakeTimeoutSeconds, RunClockDefaults.handshakeTimeoutSeconds)
        XCTAssertEqual(d.firstActivityTimeoutSeconds, RunClockDefaults.firstActivityTimeoutSeconds)
        XCTAssertEqual(d.wallTimeoutSeconds, RunClockDefaults.wallTimeoutSeconds)
        XCTAssertNil(d.idleTimeoutSeconds)
        XCTAssertTrue(RunClockDefaults.allFinite)
    }
}
