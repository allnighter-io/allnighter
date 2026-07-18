import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// PO-S03 seam tests — FIFO ticket shape, ordering, identity-dead release,
/// build-lane scope (panel never takes the lane). Reuses the ExecutionLane /
/// RunWriteLock key + registry patterns (one system).
final class ExecutionLaneTests: XCTestCase {

    // MARK: - Key identity with RunWriteLock (no second system)

    func testKeyMatchesRunWriteLock() {
        XCTAssertEqual(
            ExecutionLane.key(repoRoot: "/tmp/repo"),
            RunWriteLock.key(repoRoot: "/tmp/repo")
        )
        XCTAssertEqual(
            ExecutionLane.key(workingDirectory: "/tmp/repo/"),
            RunWriteLock.key(repoRoot: "/tmp/repo/")
        )
        XCTAssertEqual(
            ExecutionLane.key(repoRoot: nil),
            RunWriteLock.key(repoRoot: nil)
        )
    }

    func testEquivalentDirectoriesShareALane() {
        let a = ExecutionLane.key(workingDirectory: "/Users/me/repo")
        let b = ExecutionLane.key(workingDirectory: "/Users/me/repo/")
        XCTAssertEqual(a, b)
    }

    // MARK: - Ticket shape

    func testBusyTryAcquireReturnsTicketShape() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-ticket-\(UUID().uuidString)")
        // Live identity so reconcile does not free the holder mid-test.
        let holderIdentity = try XCTUnwrap(
            ProcessOwnership.OwnerIdentity.current(kind: .inProcess)
        )
        let holderClaim = ExecutionLane.Claim(
            id: "relay_holder", kind: ExecutionLaneSite.relayDevTurn.rawValue, identity: holderIdentity
        )
        // Peer claim (same process, same site kind) must NOT re-enter — FIFO ticket.
        let waiterClaim = ExecutionLane.Claim(
            id: "relay_waiter", kind: ExecutionLaneSite.relayDevTurn.rawValue, identity: holderIdentity
        )

        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = await reg.tryAcquire(key, claim: holderClaim, now: t0)
        guard case .success(let token) = first else {
            return XCTFail("holder should acquire")
        }

        let t1 = Date(timeIntervalSince1970: 1_012.5)
        let second = await reg.tryAcquire(key, claim: waiterClaim, now: t1)
        guard case .failure(let ticket) = second else {
            return XCTFail("waiter should get a FIFO ticket, not the lane")
        }

        XCTAssertEqual(ticket.position, 1)
        XCTAssertEqual(ticket.holder.id, "relay_holder")
        XCTAssertEqual(ticket.holder.kind, ExecutionLaneSite.relayDevTurn.rawValue)
        XCTAssertEqual(ticket.holder.identity.pid, holderIdentity.pid)
        XCTAssertEqual(ticket.holder.identity.startTimeTicks, holderIdentity.startTimeTicks)
        XCTAssertEqual(ticket.heldSinceSeconds, 12.5, accuracy: 0.001)

        await reg.release(key, token: token)
    }

    // MARK: - FIFO ordering

    func testTwoBlockedWaitersGetPositions1And2AndAcquireInOrder() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-fifo-\(UUID().uuidString)")
        // One live process: peer claim kinds must not re-enter (ticket + FIFO).
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        let holder = await reg.tryAcquire(
            key,
            claim: .make(id: "H", kind: "relayDevTurn", identity: identity),
            now: Date()
        )
        guard case .success(let holderToken) = holder else {
            return XCTFail("holder must acquire")
        }

        let tickets = TicketBox()
        let order = OrderRecorder()

        let w1 = Task {
            let token = await reg.waitToAcquire(
                key,
                claim: .make(id: "W1", kind: "relayDevTurn", identity: identity),
                timeout: .seconds(5),
                onTicket: { ticket in tickets.append(ticket) }
            )
            if let token {
                await order.record(1)
                await reg.release(key, token: token)
            }
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        let w2 = Task {
            let token = await reg.waitToAcquire(
                key,
                claim: .make(id: "W2", kind: "pilotDevTurn", identity: identity),
                timeout: .seconds(5),
                onTicket: { ticket in tickets.append(ticket) }
            )
            if let token {
                await order.record(2)
                await reg.release(key, token: token)
            }
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        let seen = tickets.snapshot()
        XCTAssertGreaterThanOrEqual(seen.count, 2, "both waiters should surface a ticket")
        XCTAssertEqual(seen[0].position, 1)
        XCTAssertEqual(seen[0].holder.id, "H")
        XCTAssertEqual(seen[1].position, 2)
        XCTAssertEqual(seen[1].holder.id, "H")

        let emptyWhileHeld = await order.isEmpty
        XCTAssertTrue(emptyWhileHeld, "waiters must not run while the lane is held")

        await reg.release(key, token: holderToken)
        await w1.value
        await w2.value

        let finalOrder = await order.values
        XCTAssertEqual(finalOrder, [1, 2], "FIFO: first waiter runs before second")
    }

    // MARK: - Identity-dead holder → immediate release

    func testIdentityDeadHolderReleasesImmediatelyWithReconciledOrphan() async {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-dead-\(UUID().uuidString)")
        // Unlikely-to-be-alive pid with non-matching start time → identity dead.
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_000_001, pgid: 2_000_001, startTimeTicks: 1, kind: .detachedRunner
        )
        XCTAssertFalse(ProcessOwnership.isIdentityAlive(dead))

        let acquired = await reg.tryAcquire(
            key,
            claim: .make(id: "dead-holder", kind: "relayDevTurn", identity: dead),
            now: Date()
        )
        guard case .success = acquired else {
            return XCTFail("dead identity can still *claim* until reconcile")
        }
        let heldAfterDeadClaim = await reg.isHeld(key)
        XCTAssertTrue(heldAfterDeadClaim)

        let live = ProcessOwnership.OwnerIdentity(
            pid: ProcessInfo.processInfo.processIdentifier,
            pgid: nil,
            startTimeTicks: ProcessOwnership.processStartTimeTicks(
                ProcessInfo.processInfo.processIdentifier
            ) ?? 1,
            kind: .inProcess
        )
        let next = await reg.tryAcquire(
            key,
            claim: .make(id: "successor", kind: "relayDevTurn", identity: live),
            now: Date()
        )
        guard case .success(let token) = next else {
            return XCTFail("identity-dead holder must release immediately on next acquire")
        }
        let endReason = await reg.lastReleaseEndReason(for: key)
        XCTAssertEqual(endReason, "reconciledOrphan")
        await reg.release(key, token: token, endReason: "completed")
        let heldAfterRelease = await reg.isHeld(key)
        XCTAssertFalse(heldAfterRelease)
    }

    func testReconcileAloneReleasesDeadHolder() async {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-reconcile-\(UUID().uuidString)")
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_000_002, pgid: nil, startTimeTicks: 99, kind: .inProcess
        )
        _ = await reg.tryAcquire(
            key,
            claim: .make(id: "orphan", kind: "harnessProof", identity: dead),
            now: Date()
        )
        let released = await reg.reconcile(key)
        XCTAssertTrue(released)
        let held = await reg.isHeld(key)
        XCTAssertFalse(held)
        let endReason = await reg.lastReleaseEndReason(for: key)
        XCTAssertEqual(endReason, "reconciledOrphan")
    }

    // MARK: - Build-lane scope / panel takes no lane

    func testBuildLaneScopeClassification() {
        XCTAssertTrue(ExecutionLaneClassification.mustAcquire(.relayDevTurn))
        XCTAssertTrue(ExecutionLaneClassification.mustAcquire(.pilotDevTurn))
        XCTAssertTrue(ExecutionLaneClassification.mustAcquire(.harnessProof))
        XCTAssertTrue(ExecutionLaneClassification.mustAcquire(.mutatingRun))
        XCTAssertFalse(ExecutionLaneClassification.mustAcquire(.panelSeat))
        XCTAssertFalse(ExecutionLaneClassification.mustAcquire(.answerRun))
        XCTAssertEqual(ExecutionLaneClassification.scope(for: .panelSeat), .nonBuild)
        XCTAssertEqual(ExecutionLaneClassification.scope(for: .relayDevTurn), .build)
    }

    func testPanelPathTakesNoLane() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/panel-lane-\(UUID().uuidString)")

        // Simulate a panel round: classification says non-build → never acquire.
        XCTAssertFalse(ExecutionLaneClassification.mustAcquire(.panelSeat))
        let heldBefore = await reg.isHeld(key)
        XCTAssertFalse(heldBefore, "panel must not hold the lane before work")

        // A concurrent build-class holder can still take the lane while a panel
        // would be running — panels never contend for it.
        let live = try XCTUnwrap(
            ExecutionLane.Claim.current(id: "build", kind: ExecutionLaneSite.relayDevTurn.rawValue)
        )
        let token = await reg.tryAcquire(key, claim: live, now: Date())
        guard case .success(let t) = token else {
            return XCTFail("build claim should acquire")
        }
        // Panel "path" still does not call acquire — lane state unchanged by panel.
        let heldByBuild = await reg.isHeld(key)
        XCTAssertTrue(heldByBuild)
        XCTAssertFalse(
            ExecutionLaneClassification.mustAcquire(.panelSeat),
            "panel site remains non-build even while the lane is held by a build site"
        )
        await reg.release(key, token: t)
    }

    // MARK: - Reentrancy (outer relay + inner RunService)

    func testSameProcessReentrantAcquire() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-reenter-\(UUID().uuidString)")
        let claim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: "outer", kind: "relayDevTurn")
        )
        // Nested mutating/harness under relay is the product re-entry path.
        let inner = ExecutionLane.Claim(
            id: "inner", kind: ExecutionLaneSite.mutatingRun.rawValue, identity: claim.identity
        )

        guard case .success(let t1) = await reg.tryAcquire(key, claim: claim, now: Date()) else {
            return XCTFail("outer acquire")
        }
        guard case .success(let t2) = await reg.tryAcquire(key, claim: inner, now: Date()) else {
            return XCTFail("nested mutating under relay must re-enter")
        }
        XCTAssertEqual(t1, t2)
        await reg.release(key, token: t2)
        let heldAfterNested = await reg.isHeld(key)
        XCTAssertTrue(heldAfterNested, "outer hold remains after nested release")
        await reg.release(key, token: t1)
        let heldAfterOuter = await reg.isHeld(key)
        XCTAssertFalse(heldAfterOuter)
    }

    // MARK: - PO-F2: waitToAcquire timeout reliability

    /// Under held-lane contention, `waitToAcquire` must resume within a bounded
    /// skew of its timeout and stamp `laneBusy` deterministically (the flaky
    /// path from S04 — hang/late resume under load).
    func testWaitTimeoutResumesWithinSkewAndStampsLaneBusy() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-timeout-skew-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        guard case .success(let holderToken) = await reg.tryAcquire(
            key,
            claim: .make(id: "holder", kind: "relayDevTurn", identity: identity),
            now: Date()
        ) else {
            return XCTFail("holder must acquire")
        }
        defer { Task { await reg.release(key, token: holderToken) } }

        // Spawn several concurrent waiters to load the actor + timeout hop.
        let timeout: Duration = .milliseconds(120)
        let skew: Duration = .milliseconds(350)
        let contenders = 6
        var tasks: [Task<(Duration, ExecutionLane.Token?, String?), Never>] = []
        tasks.reserveCapacity(contenders)
        for i in 0..<contenders {
            let idx = i
            tasks.append(Task {
                let clock = ContinuousClock()
                let start = clock.now
                let token = await reg.waitToAcquire(
                    key,
                    claim: .make(id: "waiter-\(idx)", kind: "relayDevTurn", identity: identity),
                    timeout: timeout
                )
                let elapsed = start.duration(to: clock.now)
                let reason = await reg.lastWaitEndReason(for: key)
                return (elapsed, token, reason)
            })
        }

        var results: [(Duration, ExecutionLane.Token?, String?)] = []
        for t in tasks {
            results.append(await t.value)
        }

        for (elapsed, token, reason) in results {
            XCTAssertNil(token, "waiter must time out while holder keeps the lane")
            // Resume after timeout, not earlier than ~timeout (minus tiny scheduling),
            // and not later than timeout + skew under load.
            XCTAssertGreaterThanOrEqual(
                elapsed, .milliseconds(80),
                "resumed too early (\(elapsed)) — timeout must actually wait"
            )
            XCTAssertLessThanOrEqual(
                elapsed, timeout + skew,
                "resumed too late (\(elapsed)) — timeout+skew bound is \(timeout + skew)"
            )
            XCTAssertEqual(reason, "laneBusy", "timeout path must stamp laneBusy, not infer nil")
        }
        let stamped = await reg.lastWaitEndReason(for: key)
        XCTAssertEqual(stamped, "laneBusy")
        let stillHeld = await reg.isHeld(key)
        XCTAssertTrue(stillHeld, "holder must keep the lane after waiters expire")
    }

    func testWaitTimeoutStampsLaneBusyEvenForSingleWaiter() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/lane-timeout-stamp-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        guard case .success(let holderToken) = await reg.tryAcquire(
            key,
            claim: .make(id: "holder", kind: "relayDevTurn", identity: identity),
            now: Date()
        ) else {
            return XCTFail("holder must acquire")
        }

        let clock = ContinuousClock()
        let start = clock.now
        let token = await reg.waitToAcquire(
            key,
            claim: .make(id: "solo", kind: "pilotDevTurn", identity: identity),
            timeout: .milliseconds(80)
        )
        let elapsed = start.duration(to: clock.now)
        XCTAssertNil(token)
        let stamped = await reg.lastWaitEndReason(for: key)
        XCTAssertEqual(stamped, "laneBusy")
        XCTAssertLessThanOrEqual(elapsed, .milliseconds(400), "solo wait timeout must be prompt")
        await reg.release(key, token: holderToken)
    }

    // MARK: - Legacy RunWriteLockRegistry façade

    func testRunWriteLockRegistryIsExecutionLaneRegistry() async {
        let reg = RunWriteLockRegistry()
        let key = RunWriteLock.key(repoRoot: "/tmp/facade-\(UUID().uuidString)")
        let first = await reg.acquire(key)
        let second = await reg.acquire(key)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        await reg.release(key, token: first!)
        let third = await reg.acquire(key)
        XCTAssertNotNil(third)
    }

    // MARK: - PO-S03b: cross-process flock + waiter rank

    /// Real two-process seam: child /bin/sh holds the lane flock + writes holder
    /// metadata; parent tryAcquire fails with a ticket naming that holder; kill
    /// the child and the kernel releases the flock so acquire succeeds immediately.
    func testCrossProcessFlockBlocksThenKernelReleaseAllowsAcquire() async throws {
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s03b-xproc-\(UUID().uuidString)")
        let laneDir = ExecutionLaneFlock.directory(forLaneKey: key)
        let lockPath = ExecutionLaneFlock.lockURL(forLaneKey: key).path
        let holderPath = ExecutionLaneFlock.holderURL(forLaneKey: key).path
        try FileManager.default.createDirectory(at: laneDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: laneDir) }

        // Child: flock(LOCK_EX), write holder.json, sleep until killed.
        // Python is the portable way to flock from /bin/sh on macOS (no flock(1)).
        let holderJSON = """
        {"acquiredAt":"2020-01-01T00:00:00Z","id":"child_holder","identity":{"kind":"inProcess","pid":999001,"startTimeTicks":42},"kind":"relayDevTurn"}
        """
        // Escape for embedding in single-quoted shell / python argv.
        let escapedHolder = holderJSON.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        python3 -c '
        import fcntl, os, time, sys
        lock_path = sys.argv[1]
        holder_path = sys.argv[2]
        holder_json = sys.argv[3]
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with open(holder_path, "w") as f:
            f.write(holder_json)
        sys.stdout.write("HELD\\n")
        sys.stdout.flush()
        time.sleep(120)
        ' '\(lockPath)' '\(holderPath)' '\(escapedHolder)'
        """

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", script]
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = Pipe()
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
        }

        // Wait until child reports it holds the flock (or timeout).
        let ready = pipe.fileHandleForReading
        var sawHeld = false
        let deadline = Date().addingTimeInterval(5)
        var buf = Data()
        while Date() < deadline, !sawHeld {
            let chunk = ready.availableData
            if !chunk.isEmpty {
                buf.append(chunk)
                if String(data: buf, encoding: .utf8)?.contains("HELD") == true {
                    sawHeld = true
                    break
                }
            } else {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        XCTAssertTrue(sawHeld, "child must flock and signal HELD")
        XCTAssertTrue(child.isRunning)

        let reg = ExecutionLaneRegistry()
        let live = try XCTUnwrap(
            ProcessOwnership.OwnerIdentity.current(kind: .inProcess)
        )
        let blocked = await reg.tryAcquire(
            key,
            claim: .make(id: "parent_waiter", kind: "relayDevTurn", identity: live),
            now: Date()
        )
        guard case .failure(let ticket) = blocked else {
            return XCTFail("parent must be blocked by child flock with a ticket")
        }
        XCTAssertEqual(ticket.holder.id, "child_holder")
        XCTAssertEqual(ticket.holder.kind, "relayDevTurn")
        XCTAssertEqual(ticket.holder.identity.pid, 999_001)
        XCTAssertEqual(ticket.holder.identity.startTimeTicks, 42)
        XCTAssertGreaterThanOrEqual(ticket.position, 1)

        // Kill child → kernel releases flock; parent must acquire immediately.
        child.terminate()
        child.waitUntilExit()
        // Brief settle for process death / fd close.
        try await Task.sleep(nanoseconds: 50_000_000)

        let after = await reg.tryAcquire(
            key,
            claim: .make(id: "parent_after", kind: "relayDevTurn", identity: live),
            now: Date()
        )
        guard case .success(let token) = after else {
            return XCTFail("after child death, flock must free and acquire must succeed")
        }
        await reg.release(key, token: token)
    }

    /// Waiter position = rank by timestamped filenames in waiters/.
    func testWaiterPositionRanksTwoTimestampedFiles() throws {
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s03b-waiters-\(UUID().uuidString)")
        let laneDir = ExecutionLaneFlock.directory(forLaneKey: key)
        defer { try? FileManager.default.removeItem(at: laneDir) }

        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)

        let w1 = try XCTUnwrap(
            ExecutionLaneFlock.registerWaiter(
                laneKey: key,
                claim: .make(id: "W1", kind: "relayDevTurn", identity: identity),
                enqueuedAt: t0
            )
        )
        let w2 = try XCTUnwrap(
            ExecutionLaneFlock.registerWaiter(
                laneKey: key,
                claim: .make(id: "W2", kind: "pilotDevTurn", identity: identity),
                enqueuedAt: t1
            )
        )
        defer {
            ExecutionLaneFlock.unregisterWaiter(w1)
            ExecutionLaneFlock.unregisterWaiter(w2)
        }

        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: key, waiterURL: w1), 1)
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: key, waiterURL: w2), 2)
        XCTAssertEqual(ExecutionLaneFlock.waiterCount(laneKey: key), 2)
        XCTAssertEqual(ExecutionLaneFlock.wouldBePosition(laneKey: key), 3)

        ExecutionLaneFlock.unregisterWaiter(w1)
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: key, waiterURL: w2), 1)
        XCTAssertEqual(ExecutionLaneFlock.waiterCount(laneKey: key), 1)
    }

    // MARK: - PO-F9: O_CLOEXEC + meta-lock exclusivity

    /// Parent holds the build flock, then releases. A spawned child must be able
    /// to acquire the same flock immediately — proving the parent's fd was not
    /// inherited (O_CLOEXEC). Without CLOEXEC the child's inherited fd would
    /// keep the kernel lock alive after the parent handle released.
    func testOCloexecSpawnedChildDoesNotKeepFlockAliveAfterParentRelease() throws {
        let key = ExecutionLane.key(repoRoot: "/tmp/po-f9-cloexec-\(UUID().uuidString)")
        let laneDir = ExecutionLaneFlock.directory(forLaneKey: key)
        let lockPath = ExecutionLaneFlock.lockURL(forLaneKey: key).path
        defer { try? FileManager.default.removeItem(at: laneDir) }

        let handle = try XCTUnwrap(
            ExecutionLaneFlock.tryAcquireExclusive(laneKey: key),
            "parent must acquire the build flock"
        )

        // Child: after a short wait (parent releases), try LOCK_EX|LOCK_NB.
        // Exit 0 = acquired (CLOEXEC worked); exit 2 = still busy (fd inherited).
        let script = """
        python3 -c '
        import fcntl, os, sys, time
        lock_path = sys.argv[1]
        time.sleep(0.15)
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            sys.exit(0)
        except BlockingIOError:
            sys.exit(2)
        ' '\(lockPath)'
        """
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", script]
        child.standardOutput = Pipe()
        child.standardError = Pipe()
        try child.run()

        // Release after child has started so inheritance would already have happened.
        Thread.sleep(forTimeInterval: 0.05)
        handle.release()
        child.waitUntilExit()

        XCTAssertEqual(
            child.terminationStatus, 0,
            "child must acquire after parent release — flock fd must not be inherited (O_CLOEXEC)"
        )
    }

    /// Two same-process threads upserting distinct holders under meta lock must
    /// both land — the in-process mutex prevents lost updates from refcount
    /// sharing on meta.lock (PO-F9 `#2`).
    func testMetaLockConcurrentUpsertHolderBothLand() throws {
        let key = ExecutionLane.key(repoRoot: "/tmp/po-f9-meta-\(UUID().uuidString)")
        let laneDir = ExecutionLaneFlock.directory(forLaneKey: key)
        defer { try? FileManager.default.removeItem(at: laneDir) }

        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        let barrier = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        var results: [Bool] = [false, false]
        let resultsLock = NSLock()

        for i in 0..<2 {
            let idx = i
            DispatchQueue.global(qos: .userInitiated).async {
                _ = barrier.wait(timeout: .now() + 2)
                let meta = ExecutionLaneFlock.HolderMetadata(
                    identity: identity,
                    kind: "relayDevTurn",
                    id: "holder-\(idx)",
                    acquiredAt: Date(),
                    writeScope: ["docs/\(idx)/"],
                    needsBuildLane: false
                )
                let ok = ExecutionLaneFlock.upsertHolder(laneKey: key, metadata: meta)
                resultsLock.lock()
                results[idx] = ok
                resultsLock.unlock()
                done.signal()
            }
        }

        // Release both threads together so they contend on meta RMW.
        barrier.signal()
        barrier.signal()
        _ = done.wait(timeout: .now() + 5)
        _ = done.wait(timeout: .now() + 5)

        XCTAssertTrue(results[0], "thread 0 upsert must succeed")
        XCTAssertTrue(results[1], "thread 1 upsert must succeed")
        let holders = ExecutionLaneFlock.readHolders(laneKey: key)
        let ids = Set(holders.map(\.id))
        XCTAssertEqual(ids, Set(["holder-0", "holder-1"]), "both upserts must land — no lost update")
    }

    func testSanitizedDirectoryNameDoesNotCollideV1PrefixWithRawKey() {
        let v1 = ExecutionLaneFlock.sanitizedDirectoryName(for: "v1:abc")
        let raw = ExecutionLaneFlock.sanitizedDirectoryName(for: "abc")
        XCTAssertNotEqual(v1, raw, "v1:abc must not sanitize to the same path as raw abc")
        XCTAssertEqual(v1, "abc")
        XCTAssertTrue(raw.hasPrefix("k_"), "raw keys get escape-proof k_ prefix")
    }
}

// MARK: - Helpers

private actor OrderRecorder {
    private(set) var values: [Int] = []
    var isEmpty: Bool { values.isEmpty }
    func record(_ n: Int) { values.append(n) }
}

/// Sync ticket capture for `@Sendable` `onTicket` callbacks (not actor-isolated).
private final class TicketBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ExecutionLaneTicket] = []
    func append(_ t: ExecutionLaneTicket) {
        lock.lock(); values.append(t); lock.unlock()
    }
    func snapshot() -> [ExecutionLaneTicket] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
