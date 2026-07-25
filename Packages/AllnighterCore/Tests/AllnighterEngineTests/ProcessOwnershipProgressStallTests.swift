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
        ProcessOwnership.processGroupActivitySampleHook = nil
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

    // MARK: - Process-group activity sampler (IDLE-HF-S02)

    func testProcessGroupActivityDetectedOnNewChildPid() {
        let previous = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [100],
            cpuMicrosecondsByPid: [100: 5_000]
        )
        let current = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [100, 101],
            cpuMicrosecondsByPid: [100: 5_000, 101: 0]
        )
        XCTAssertTrue(ProcessOwnership.processGroupActivityDetected(since: previous, current: current))
    }

    func testProcessGroupActivityDetectedOnCPUGrowth() {
        let previous = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [100],
            cpuMicrosecondsByPid: [100: 5_000]
        )
        let current = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [100],
            cpuMicrosecondsByPid: [100: 9_000]
        )
        XCTAssertTrue(ProcessOwnership.processGroupActivityDetected(since: previous, current: current))
    }

    func testProcessGroupActivityNotDetectedOnFirstSample() {
        let current = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [100],
            cpuMicrosecondsByPid: [100: 9_000]
        )
        XCTAssertFalse(ProcessOwnership.processGroupActivityDetected(since: nil, current: current))
    }

    func testProcessGroupActivityNotDetectedWhenFrozen() {
        let snap = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [100],
            cpuMicrosecondsByPid: [100: 5_000]
        )
        XCTAssertFalse(ProcessOwnership.processGroupActivityDetected(since: snap, current: snap))
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

    // MARK: - Works test: pgid CPU/child activity without stdout → progress fresh

    func testSilentWorkerWithPgidActivityIsNotStalledPastIdleBudget() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idle-hf-s02-pgid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        let stallBudget: Duration = .seconds(1)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(30), maxBufferedBytes: 1_000_000)
        )

        let streamTask = Task {
            var terminal: CommandEvent?
            do {
                for try await event in runner.runStreaming(
                    command: "/bin/sh",
                    args: ["-c", "sleep 30 & while true; do :; done"],
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

        try await Task.sleep(for: .seconds(2.2))

        let owner = try XCTUnwrap(ProcessOwnership.readTurnOwner(in: dir))
        XCTAssertTrue(ProcessOwnership.processAlive(owner.pid))
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(owner))

        let hb = try XCTUnwrap(ProcessOwnership.readProgressHeartbeat(in: dir))
        XCTAssertEqual(hb.phase, "pgid_activity", "CPU under recorded pgid must reset progress")
        // Watchdog uses memory + mtime (sub-second); encoded lastProgressAt is
        // whole-second ISO-8601 and is only a coarse status signal.
        let hbURL = ProcessOwnership.heartbeatURL(in: dir)
        let mtime = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: hbURL.path)[.modificationDate] as? Date
        )
        XCTAssertLessThan(
            Date().timeIntervalSince(mtime), 0.75,
            "pgid activity must keep progress fresh past the idle stall budget"
        )
        XCTAssertEqual(
            ProcessOwnership.classifyProgressStall(
                identityAlive: true,
                lastProgressAt: mtime,
                stallBudgetSeconds: 1
            ),
            .progressing
        )

        streamTask.cancel()
        _ = ProcessOwnership.terminateOwnerIdentityIfSafe(owner)
        var status: Int32 = 0
        _ = waitpid(owner.pid, &status, 0)
        let terminal = await streamTask.value
        if case .timedOut? = terminal {
            XCTFail("pgid-busy silent worker must not idle-reap; got \(String(describing: terminal))")
        }
    }

    // MARK: - Works test: repo cwd writes are NOT progress (IDLE-HF-S02 guard)

    func testRepoCwdWritesDoNotResetIdleProgress() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idle-hf-s02-cwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let repo = dir.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        // Freeze pgid sampling so brief spawn CPU cannot sticky-label the heartbeat
        // `pgid_activity`. This isolates the real guard: there is no repo/cwd fs watch.
        let frozen = ProcessOwnership.ProcessGroupActivitySnapshot(
            memberPids: [42],
            cpuMicrosecondsByPid: [42: 1_000]
        )
        ProcessOwnership.processGroupActivitySampleHook = { _ in frozen }
        defer { ProcessOwnership.processGroupActivitySampleHook = nil }

        let stallBudget: Duration = .seconds(1)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: .seconds(20), maxBufferedBytes: 1_000_000)
        )

        let streamTask = Task {
            var terminal: CommandEvent?
            do {
                for try await event in runner.runStreaming(
                    command: "/bin/sleep",
                    args: ["20"],
                    stdin: nil,
                    env: [:],
                    workingDirectory: repo.path,
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

        // Let the spawn heartbeat land, then capture a baseline before cwd noise.
        try await Task.sleep(for: .milliseconds(300))
        let baseline = try XCTUnwrap(ProcessOwnership.readProgressHeartbeat(in: dir))
        XCTAssertNotEqual(baseline.phase, "pgid_activity")
        let hbURL = ProcessOwnership.heartbeatURL(in: dir)
        let baselineMtime = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: hbURL.path)[.modificationDate] as? Date
        )

        // Parallel repo writes must NOT count as attributable progress — only pgid/stream/recordProgress do.
        let noiseUntil = Date().addingTimeInterval(2.2)
        while Date() < noiseUntil {
            let noise = repo.appendingPathComponent("noise-\(UUID().uuidString).txt")
            try "unattributable".write(to: noise, atomically: true, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(100))
        }

        let owner = try XCTUnwrap(ProcessOwnership.readTurnOwner(in: dir))
        let hb = try XCTUnwrap(ProcessOwnership.readProgressHeartbeat(in: dir))
        XCTAssertNotEqual(hb.phase, "pgid_activity", "cwd noise must not masquerade as pgid progress")
        let afterMtime = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: hbURL.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(
            afterMtime.timeIntervalSince1970,
            baselineMtime.timeIntervalSince1970,
            accuracy: 0.05,
            "cwd writes must not refresh progress heartbeat"
        )
        XCTAssertEqual(
            ProcessOwnership.classifyProgressStall(
                identityAlive: ProcessOwnership.isIdentityAlive(owner),
                lastProgressAt: afterMtime,
                stallBudgetSeconds: 1
            ),
            .stalled,
            "frozen owner + cwd writes only → still stalled past idle budget"
        )

        streamTask.cancel()
        _ = ProcessOwnership.terminateOwnerIdentityIfSafe(owner)
        var status: Int32 = 0
        _ = waitpid(owner.pid, &status, 0)
        _ = await streamTask.value
    }

    // MARK: - Works test: progress frozen → reaped (timeout → stall endReason path)

    func testFrozenProgressIsReapedAtWallNotIdle() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-f1-frozen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        let stallBudget: Duration = .seconds(1)
        let wallBudget: Duration = .seconds(4)
        let runner = ProcessGroupCommandRunner(
            budget: SubprocessBudget(totalDuration: wallBudget, maxBufferedBytes: 1_000_000)
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
            return XCTFail(
                "identity-alive frozen progress must be reaped at wall, not idle; got \(String(describing: terminal))"
            )
        }
        XCTAssertGreaterThan(elapsed, 2.5, "must survive past the idle stall budget")
        XCTAssertLessThan(elapsed, 10, "must reap near the wall backstop, not the full sleep")
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
