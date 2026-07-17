import XCTest
import Darwin
import AllnighterCore
@testable import AllnighterEngine

/// PO-F1 — watchdog consumes progress, not silence.
/// Pure classifier seams + live ProcessGroupCommandRunner works tests.
final class ProcessOwnershipProgressStallTests: XCTestCase {

    override func tearDown() {
        ProcessOwnership.TurnOwnerDirectory.shared.set(nil)
        ProcessOwnership.terminateSignalHook = nil
        super.tearDown()
    }

    // MARK: - Pure classifier (identity + progress + budget → verdict)

    func testClassifierProgressingWhenIdentityAliveAndProgressFresh() {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let last = Date(timeIntervalSince1970: 1_700_000_050) // 50s ago
        let verdict = ProcessOwnership.classifyProgressStall(
            identityAlive: true,
            lastProgressAt: last,
            now: now,
            stallBudgetSeconds: 60
        )
        XCTAssertEqual(verdict, .progressing)
    }

    func testClassifierProgressingAtExactBudgetBoundary() {
        // within budget means age <= budget → progressing (age > budget → stalled)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let last = Date(timeIntervalSince1970: 1_700_000_040) // exactly 60s ago
        let verdict = ProcessOwnership.classifyProgressStall(
            identityAlive: true,
            lastProgressAt: last,
            now: now,
            stallBudgetSeconds: 60
        )
        XCTAssertEqual(verdict, .progressing, "age == budget is still within budget")
    }

    func testClassifierStalledWhenProgressFrozenPastBudget() {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let last = Date(timeIntervalSince1970: 1_700_000_000) // 100s ago
        let verdict = ProcessOwnership.classifyProgressStall(
            identityAlive: true,
            lastProgressAt: last,
            now: now,
            stallBudgetSeconds: 60
        )
        XCTAssertEqual(verdict, .stalled)
    }

    func testClassifierStalledWhenNoProgressRecordedButIdentityAlive() {
        let verdict = ProcessOwnership.classifyProgressStall(
            identityAlive: true,
            lastProgressAt: nil,
            now: Date(),
            stallBudgetSeconds: 30
        )
        XCTAssertEqual(verdict, .stalled)
    }

    func testClassifierIdentityDeadRegardlessOfProgress() {
        let now = Date()
        let fresh = now
        let frozen = now.addingTimeInterval(-1_000)
        XCTAssertEqual(
            ProcessOwnership.classifyProgressStall(
                identityAlive: false, lastProgressAt: fresh, now: now, stallBudgetSeconds: 60
            ),
            .identityDead
        )
        XCTAssertEqual(
            ProcessOwnership.classifyProgressStall(
                identityAlive: false, lastProgressAt: frozen, now: now, stallBudgetSeconds: 60
            ),
            .identityDead
        )
        XCTAssertEqual(
            ProcessOwnership.classifyProgressStall(
                identityAlive: false, lastProgressAt: nil, now: now, stallBudgetSeconds: 60
            ),
            .identityDead
        )
    }

    func testStallBudgetSecondsKeepsPriorFloorOfOneSecond() {
        XCTAssertEqual(ProcessGroupCommandRunner.stallBudgetSeconds(from: .seconds(120)), 120)
        XCTAssertEqual(ProcessGroupCommandRunner.stallBudgetSeconds(from: .seconds(1)), 1)
        // Sub-second Durations still floor to 1s (prior idle-timeout math unchanged).
        XCTAssertEqual(ProcessGroupCommandRunner.stallBudgetSeconds(from: .milliseconds(400)), 1)
    }

    // MARK: - Works test: silent stdout + touching progress → never reaped

    func testSilentWorkerTouchingProgressIsNeverReapedAt2xBudget() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-f1-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        // Stall budget = 1s (the old silence threshold for this call).
        // Run silent for 2× budget while externally touching progress.
        let stallBudget: Duration = .seconds(1)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(30), maxBufferedBytes: 1_000_000)
        )

        try ProcessOwnership.recordProgress(in: dir, phase: "preflight")

        let streamTask = Task {
            var terminal: CommandEvent?
            do {
                for try await event in runner.runStreaming(
                    command: "/bin/sleep",
                    args: ["10"],
                    stdin: nil,
                    env: [:],
                    workingDirectory: nil,
                    timeout: stallBudget
                ) {
                    switch event {
                    case .completed, .timedOut, .cancelled, .failed, .bufferOverflow:
                        terminal = event
                    default:
                        break
                    }
                }
            } catch {
                // Cancellation from cleanup is fine.
            }
            return terminal
        }

        // Touch progress on the main test task for 2× stall budget (no stdout).
        let observeUntil = Date().addingTimeInterval(2.2)
        while Date() < observeUntil {
            try ProcessOwnership.recordProgress(in: dir, phase: "child_activity")
            try await Task.sleep(for: .milliseconds(100))
        }

        let owner = try XCTUnwrap(
            ProcessOwnership.readTurnOwner(in: dir),
            "turn owner should still be recorded"
        )
        // Watchdog uses memory + mtime (sub-second); encoded lastProgressAt is
        // whole-second ISO-8601 and is only a coarse status signal.
        let hbURL = ProcessOwnership.heartbeatURL(in: dir)
        let mtime = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: hbURL.path)[.modificationDate] as? Date
        )
        XCTAssertLessThan(
            Date().timeIntervalSince(mtime), 0.75,
            "progress heartbeat mtime must still look fresh at 2× budget"
        )
        XCTAssertTrue(
            ProcessOwnership.processAlive(owner.pid),
            "silent-but-progressing worker must not be reaped at 2× stall budget (pid \(owner.pid))"
        )
        XCTAssertTrue(
            ProcessOwnership.isIdentityAlive(owner),
            "identity-alive + progressing turn must not be reaped at 2× stall budget"
        )

        // Cleanup: cancel stream + kill group so we don't leave a sleep(10).
        streamTask.cancel()
        ProcessOwnership.terminateSignalHook = nil
        _ = ProcessOwnership.terminateOwnerIdentityIfSafe(owner)
        var status: Int32 = 0
        _ = waitpid(owner.pid, &status, 0)
        let terminal = await streamTask.value
        if case .timedOut? = terminal {
            XCTFail("must not emit timedOut while progress was being touched; got \(String(describing: terminal))")
        }
    }

    // MARK: - Works test: progress frozen → reaped (timeout → stall endReason path)

    func testFrozenProgressIsReapedWithTimeout() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-f1-frozen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        let stallBudget: Duration = .seconds(1)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(30), maxBufferedBytes: 1_000_000)
        )

        let start = Date()
        var terminal: CommandEvent?
        do {
            for try await event in runner.runStreaming(
                command: "/bin/sleep",
                args: ["30"],
                stdin: nil,
                env: [:],
                workingDirectory: nil,
                timeout: stallBudget
            ) {
                switch event {
                case .completed, .timedOut, .cancelled, .failed, .bufferOverflow:
                    terminal = event
                default:
                    break
                }
            }
        } catch {
            XCTFail("stream threw: \(error)")
        }

        let elapsed = Date().timeIntervalSince(start)
        guard case .timedOut? = terminal else {
            return XCTFail("expected timedOut when progress freezes past budget, got \(String(describing: terminal))")
        }
        XCTAssertLessThan(elapsed, 8, "frozen progress must be reaped near the stall budget, not the full sleep")
        XCTAssertGreaterThanOrEqual(elapsed, 0.8, "must wait roughly the stall budget before reaping")

        // Relay maps timedOut → .stalled → endReason stalled (see RelayTurnClassifier +
        // existing ProcessOwnershipTurnKillTests.testDevTurnStalledBudgetStampsEndReason).
        let outcome = WorkerRunOutcome(status: .timedOut, errorKind: .timedOut, errorReason: "progress stalled")
        XCTAssertEqual(RelayTurnClassifier.classify(.init(outcome: outcome)), .stalled)
    }

    // MARK: - Spawn records durable progress into the turn directory

    func testSpawnRecordsProgressHeartbeatInTurnDirectory() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-f1-spawn-hb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(10), maxBufferedBytes: 1_000_000)
        )
        let result = await runner.run(
            command: "/bin/echo",
            args: ["hi"],
            stdin: nil,
            env: [:],
            workingDirectory: nil,
            timeout: .seconds(5)
        )
        XCTAssertEqual(result.exitCode, 0)
        let hb = try XCTUnwrap(ProcessOwnership.readProgressHeartbeat(in: dir))
        XCTAssertGreaterThanOrEqual(hb.sequence, 1, "spawn/output/exit must bump progress sequence")
        XCTAssertFalse(hb.phase.isEmpty)
    }
}
