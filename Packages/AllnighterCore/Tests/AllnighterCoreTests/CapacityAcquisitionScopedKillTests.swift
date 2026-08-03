import XCTest
@testable import AllnighterCore

/// CWB-S00a: acquisition-scoped probe kill.
///
/// Product law: a strip/acquire timeout must reap only its own generation's
/// PTYs — never another in-flight acquire's (timer must never cross-kill an
/// explicit Refresh). Deterministic: fake executors register fake PIDs into
/// injectable scopes; no live vendor CLIs, no real process kills.
final class CapacityAcquisitionScopedKillTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    /// Records terminated PIDs; lets a fake executor block until its own kill.
    private final class KillRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _killed: [pid_t] = []
        var killed: [pid_t] {
            lock.lock(); defer { lock.unlock() }
            return _killed
        }

        func record(_ pid: pid_t) {
            lock.lock(); _killed.append(pid); lock.unlock()
        }

        func waitForKill(of pid: pid_t, timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                lock.lock()
                let hit = _killed.contains(pid)
                lock.unlock()
                if hit { return true }
                Thread.sleep(forTimeInterval: 0.01)
            }
            lock.lock(); defer { lock.unlock() }
            return _killed.contains(pid)
        }
    }

    /// Fake probe: registers its fake PID into the request's scope, then blocks
    /// either until that PID is terminated (timed-out acquire) or until the
    /// test releases it (healthy concurrent acquire).
    private final class BlockingScopeExecutor: CapacityProbeExecuting, @unchecked Sendable {
        enum Mode {
            case untilKilled(KillRecorder)
            case untilReleased(DispatchSemaphore)
        }

        let fakePID: pid_t
        let mode: Mode
        private let lock = NSLock()
        private var _executed = false
        var executed: Bool {
            lock.lock(); defer { lock.unlock() }
            return _executed
        }

        init(fakePID: pid_t, mode: Mode) {
            self.fakePID = fakePID
            self.mode = mode
        }

        func waitUntilExecuted(timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if executed { return true }
                Thread.sleep(forTimeInterval: 0.01)
            }
            return executed
        }

        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            lock.lock(); _executed = true; lock.unlock()
            request.scope?.track(fakePID)
            switch mode {
            case .untilKilled(let recorder):
                _ = recorder.waitForKill(of: fakePID, timeout: 15)
            case .untilReleased(let semaphore):
                _ = semaphore.wait(timeout: .now() + 15)
            }
            return [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    // MARK: - Scope unit behavior

    func testScopeTerminateKillsOnlyItsOwnTrackedPIDs() {
        let recorder = KillRecorder()
        let scopeA = CapacityProbeScope { pid in recorder.record(pid) }
        let scopeB = CapacityProbeScope { pid in recorder.record(pid) }
        scopeA.track(1_111_111)
        scopeA.track(1_111_112)
        scopeB.track(2_222_222)

        scopeA.terminate()

        XCTAssertEqual(
            Set(recorder.killed), [1_111_111, 1_111_112],
            "terminate must kill exactly this scope's tracked groups"
        )
        XCTAssertEqual(
            scopeB.trackedPIDs, [2_222_222],
            "scope B's child must stay tracked and alive"
        )

        // Idempotent: drained set → second terminate is a no-op.
        scopeA.terminate()
        XCTAssertEqual(recorder.killed.count, 2)
    }

    func testScopeUntrackRemovesFinishedChildFromKillSet() {
        let recorder = KillRecorder()
        let scope = CapacityProbeScope { pid in recorder.record(pid) }
        scope.track(3_333_333)
        scope.untrack(3_333_333)
        scope.terminate()
        XCTAssertTrue(recorder.killed.isEmpty, "a reaped child must not be killed twice")
    }

    // MARK: - Concurrent acquires: timeout of A never reaps B

    func testConcurrentAcquireTimeoutTerminatesOnlyOwnScope() {
        let pidA: pid_t = 1_500_000_001
        let pidB: pid_t = 1_500_000_002
        let recorderA = KillRecorder()
        let recorderB = KillRecorder()
        let scopeA = CapacityProbeScope { pid in recorderA.record(pid) }
        let scopeB = CapacityProbeScope { pid in recorderB.record(pid) }
        let bRelease = DispatchSemaphore(value: 0)
        let bFinished = DispatchSemaphore(value: 0)

        let execA = BlockingScopeExecutor(fakePID: pidA, mode: .untilKilled(recorderA))
        let execB = BlockingScopeExecutor(fakePID: pidB, mode: .untilReleased(bRelease))

        // Acquire B starts first and stays in flight across A's whole lifetime.
        // B gets a long budget so its own group timeout never fires — the only
        // way B's scope could die is a cross-kill from A.
        let now = self.now
        var windowsB: [CapacityWindow] = []
        DispatchQueue.global(qos: .userInitiated).async {
            windowsB = CapacityAcquisition.windows(
                now: now,
                refresh: true,
                refreshSource: "kimi",
                probeExecutor: execB,
                probeTimeout: 30,
                probeScope: scopeB
            )
            bFinished.signal()
        }
        XCTAssertTrue(execB.waitUntilExecuted(timeout: 5), "B's probe must be in flight")
        XCTAssertTrue(scopeB.trackedPIDs.contains(pidB))

        // Acquire A times out (short probe budget, blocking executor) → scoped kill.
        let windowsA = CapacityAcquisition.windows(
            now: now,
            refresh: true,
            refreshSource: "kimi",
            probeExecutor: execA,
            probeTimeout: 0.5,
            probeScope: scopeA
        )

        XCTAssertEqual(recorderA.killed, [pidA], "A's timeout must kill A's child")
        XCTAssertTrue(
            recorderB.killed.isEmpty,
            "A's timeout must never cross-kill B's child; killed=\(recorderB.killed)"
        )
        XCTAssertTrue(
            scopeB.trackedPIDs.contains(pidB),
            "B's child must still be tracked — B was never terminated"
        )
        XCTAssertNotNil(
            windowsA.first { $0.source == "kimi" }?.unknownReason,
            "timed-out acquire still fails closed"
        )

        // Let B finish normally; its scope is never terminated.
        bRelease.signal()
        XCTAssertEqual(bFinished.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(recorderB.killed.isEmpty)
        XCTAssertEqual(windowsB.first { $0.source == "kimi" }?.sourceTier, .tuiProbe)
    }

    /// Without an injected scope the acquire creates its own — a group timeout
    /// terminates that private scope (fake PID kill is a harmless ESRCH) and the
    /// wave still fails closed without hanging on the blocked executor.
    func testDefaultScopeIsPrivatePerAcquire() {
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let execA = BlockingScopeExecutor(fakePID: 1_600_000_001, mode: .untilReleased(release))
        defer { release.signal() } // unblock the lingering fake probe

        let now = self.now
        var windowsA: [CapacityWindow] = []
        DispatchQueue.global(qos: .userInitiated).async {
            windowsA = CapacityAcquisition.windows(
                now: now,
                refresh: true,
                refreshSource: "kimi",
                probeExecutor: execA,
                probeTimeout: 0.5
            )
            done.signal()
        }

        XCTAssertTrue(execA.waitUntilExecuted(timeout: 5))
        XCTAssertEqual(done.wait(timeout: .now() + 20), .success, "timeout path must return")
        XCTAssertNotNil(windowsA.first { $0.source == "kimi" }?.unknownReason)
    }
}
