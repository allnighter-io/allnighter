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
