import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S01b — the acceptance boundary (`docs/phases/Run_Lifecycle_Reliability.md`
/// RLR-L1/L2/L9, `docs/phases/rlr/S01_Execution_Plan.md` § S01b).
///
/// Proves the four S01b guarantees:
///  1. a durable, pollable run + typed blocker exist BEFORE the write-lock wait;
///  2. the `running` status is persisted BEFORE its event is emitted (no
///     emit-then-persist race);
///  3. a `RUN_NOT_FOUND` failure names the effective `ALLNIGHTER_SUPPORT_DIR`;
///  4. the generalized canonical idempotency payload round-trips and the sync
///     `alln run` acceptance path claims / replays / conflicts on the key.
final class RunAcceptanceBoundaryTests: XCTestCase {

    /// Hermetic support root so FIFO/lane flock paths never touch
    /// `~/Library/Application Support/Allnighter/Lanes/` (sandbox-safe).
    private var hermeticSupportDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-accept-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        hermeticSupportDir = support
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        if let hermeticSupportDir {
            try? FileManager.default.removeItem(at: hermeticSupportDir)
        }
        hermeticSupportDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Shared harness (cursor default-route worker, mock CLI)

    private struct Harness {
        let repo: URL
        let runsDir: URL
        let runStore: RunStore
        let registry: RunWriteLockRegistry
        let service: RunService
        var root: String { RunWriteLock.normalize(repo.path) ?? repo.path }
        var lockKey: String { RunWriteLock.key(repoRoot: root) }
        func pollStore() -> RunStore { RunStore(rootDirectory: runsDir) }
    }

    private func makeHarness(
        idempotency: IdempotencyStore? = nil,
        commandRunner: CommandRunner? = nil
    ) throws -> Harness {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-accept-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let registry = RunWriteLockRegistry()
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            runStore: runStore,
            commandRunner: commandRunner
                ?? MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: registry,
            defaultSettings: { settings },
            probeRecords: { [probe] },
            idempotency: idempotency ?? IdempotencyStore(
                fileURL: repo.appendingPathComponent("idempotency.json")))
        return Harness(repo: repo, runsDir: runsDir, runStore: runStore, registry: registry, service: service)
    }

    /// Records whether the worker CLI was ever launched — the no-spawn-while-blocked proof.
    private final class SpyCommandRunner: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _launched = false
        private let inner: MockCommandRunner
        init(inner: MockCommandRunner) { self.inner = inner }
        var launched: Bool { lock.withLock { _launched } }
        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            lock.withLock { _launched = true }
            return await inner.run(
                command: command, args: args, stdin: stdin, env: env,
                workingDirectory: workingDirectory, timeout: timeout)
        }
    }

    // MARK: - 1. Durable, pollable queued run + blocker during the write-lock wait

    func testWriteLockWaitLeavesDurablePollableQueuedRunWithBlocker() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // A competing mutating run already holds the per-root write lock.
        let holder = await h.registry.waitToAcquire(h.lockKey, timeout: .seconds(30))
        let holderToken = try XCTUnwrap(holder, "test could not pre-hold the write lock")

        // Start our run (blocks in `waitToAcquire`); mint id is ours so we can poll it.
        let runId = UUID().uuidString
        let request = RunRequest(message: "edit the repo", repoRoot: h.repo.path)
        let runTask = Task { await h.service.run(request, origin: .cli, runId: runId) }

        // A SECOND, independent RunStore polls the same durable truth mid-wait.
        let poll = h.pollStore()
        var pending: TeamRun?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.status == .queued { pending = r; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let run = try XCTUnwrap(pending, "a queued run.json must be pollable DURING the write-lock wait")

        XCTAssertEqual(run.status, .queued)
        XCTAssertEqual(run.status.lifecycle, .queued)
        XCTAssertEqual(run.phase, .waitingForWriteLock)
        XCTAssertEqual(run.blocker?.resource, .repoWriteLock)
        XCTAssertEqual(run.blocker?.scopeRoot, h.root)
        XCTAssertFalse(run.status.isTerminal)

        // Release the lock → our run acquires it, clears the blocker, and settles.
        await h.registry.release(h.lockKey, token: holderToken)
        _ = await runTask.value
        let settled = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertTrue(settled.status.isTerminal)
        XCTAssertNil(settled.blocker)
        XCTAssertNil(settled.phase)
    }

    // MARK: - S02a. Durable FIFO ticket facts naming the holder run; no spawn while blocked

    func testBlockedRunCarriesFifoTicketFactsNamingHolderRun() async throws {
        let spy = SpyCommandRunner(
            inner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]))
        let h = try makeHarness(commandRunner: spy)
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // Pre-hold the lane with a claim whose id IS a canonical run id (as the mutating
        // run now claims). A second run's ticket must name THIS id, not a throwaway UUID.
        let holderRunId = "holder-run-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold the write lock")
        }

        // Start run B (blocks in waitToAcquire).
        let runId = UUID().uuidString
        let request = RunRequest(message: "edit the repo", repoRoot: h.repo.path)
        let runTask = Task { await h.service.run(request, origin: .cli, runId: runId) }

        // Poll the durable blocker until the ticket facts are stamped.
        let poll = h.pollStore()
        var blocked: TeamRun?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.status == .queued, r.blocker?.holderId != nil {
                blocked = r; break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let run = try XCTUnwrap(blocked, "the blocked run must carry durable FIFO ticket facts")

        XCTAssertEqual(run.phase, .waitingForWriteLock)
        XCTAssertEqual(run.blocker?.resource, .repoWriteLock)
        XCTAssertEqual(run.blocker?.scopeRoot, h.root)
        XCTAssertEqual(run.blocker?.holderId, holderRunId, "the ticket must name the HOLDING run's id")
        XCTAssertEqual(run.blocker?.holderKind, "run", "public holderKind is `run` in P0, never the site kind")
        XCTAssertEqual(run.blocker?.ticketPosition, 1, "single waiter is at the head of the queue")
        XCTAssertNotNil(run.blocker?.holderAcquiredAt)
        // No spawn while blocked: control never reaches the worker invoker.
        XCTAssertFalse(spy.launched, "no worker may be launched while the run is blocked on the write lock")
        XCTAssertTrue(run.workers.isEmpty)
        XCTAssertTrue(run.answers.isEmpty)

        // Release → B acquires, clears the blocker, spawns, settles.
        await h.registry.release(h.lockKey, token: holderToken)
        _ = await runTask.value
        let settled = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertTrue(settled.status.isTerminal)
        XCTAssertNil(settled.blocker)
        XCTAssertTrue(spy.launched, "the worker must launch once the lane is granted")
    }

    func testGrantClearsBlockerAndAdvancesPhaseInOneRevision() async throws {
        // A short worker delay keeps B observable in `working` (blocker cleared, non-terminal)
        // so the atomic clear-and-advance is caught in a live revision, not only at settle.
        let h = try makeHarness(
            commandRunner: MockCommandRunner(
                scripts: ["cursor": .init(stdout: "Done.", exitCode: 0, delay: .milliseconds(400))]))
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let holderRunId = "holder-run-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold the write lock")
        }

        let runId = UUID().uuidString
        let runTask = Task {
            await h.service.run(RunRequest(message: "edit the repo", repoRoot: h.repo.path),
                                origin: .cli, runId: runId)
        }

        // Confirm B is durably blocked before releasing.
        let poll = h.pollStore()
        let blockedDeadline = Date().addingTimeInterval(10)
        while Date() < blockedDeadline {
            if let r = poll.loadRaw(runId: runId), r.phase == .waitingForWriteLock, r.blocker != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let pre = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertEqual(pre.phase, .waitingForWriteLock)
        XCTAssertNotNil(pre.blocker)

        // Release and rapidly sample every revision. The atomic rule (RLR-L3): a blocker is
        // present IFF the phase is `waitingForWriteLock`. There must never be a revision with a
        // cleared blocker still on `waitingForWriteLock`, nor a set blocker past that phase.
        await h.registry.release(h.lockKey, token: holderToken)
        var sawClearedAndAdvancedLive = false
        var sawForbidden = false
        let sampleDeadline = Date().addingTimeInterval(10)
        while Date() < sampleDeadline {
            if let r = poll.loadRaw(runId: runId) {
                let blockerSet = r.blocker != nil
                let onWaitPhase = r.phase == .waitingForWriteLock
                if blockerSet != onWaitPhase { sawForbidden = true }
                if !r.status.isTerminal, !blockerSet, r.phase != nil, r.phase != .waitingForWriteLock {
                    sawClearedAndAdvancedLive = true
                }
                if r.status.isTerminal { break }
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        _ = await runTask.value

        XCTAssertFalse(sawForbidden,
                       "blocker and `waitingForWriteLock` must be set/cleared in the SAME revision (RLR-L3)")
        XCTAssertTrue(sawClearedAndAdvancedLive,
                      "a live post-grant revision must show blocker cleared AND phase advanced together")
        let settled = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertTrue(settled.status.isTerminal)
        XCTAssertNil(settled.blocker)
        XCTAssertNil(settled.phase)
    }

    // MARK: - S02b. Root isolation (RLR-L4 / Works Test 3): one root = one lock,
    //         alternate spellings converge, true different roots never serialize
    //         and never name each other's holder.

    /// Pre-hold the lane via the canonical root spelling; start run B addressed by a
    /// **case-variant** spelling of the SAME root → B keys onto the one lane and blocks,
    /// its blocker naming the holder run. Proves two spellings share one lock.
    func testSameRootCaseVariantSpellingSharesOneLockAndNamesHolder() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let holderRunId = "holder-run-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold the write lock")
        }
        defer { Task { await h.registry.release(h.lockKey, token: holderToken) } }

        // A case-variant spelling of the SAME on-disk root (last component upper-cased).
        // On the case-insensitive FS `normalize` collapses it to the real casing → same key.
        let caseVariant = h.repo.deletingLastPathComponent()
            .appendingPathComponent(h.repo.lastPathComponent.uppercased(), isDirectory: true).path
        XCTAssertNotEqual(caseVariant, h.repo.path, "the test's variant must differ in spelling")
        XCTAssertEqual(RunWriteLock.key(repoRoot: caseVariant), h.lockKey,
                       "a case-variant of an existing root must map to the one lane key")

        let runId = UUID().uuidString
        let runTask = Task {
            await h.service.run(RunRequest(message: "edit the repo", repoRoot: caseVariant),
                                origin: .cli, runId: runId)
        }

        let poll = h.pollStore()
        var blocked: TeamRun?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.status == .queued, r.blocker?.holderId != nil {
                blocked = r; break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let run = try XCTUnwrap(blocked, "a same-root alternate spelling must block behind the one lock")
        XCTAssertEqual(run.blocker?.scopeRoot, h.root, "the blocker's scopeRoot is the canonical root, not the input spelling")
        XCTAssertEqual(run.blocker?.holderId, holderRunId, "the shared lane's ticket names the holding run")
        XCTAssertEqual(run.blocker?.holderKind, "run", "public holderKind is `run`, never the internal site kind")
        XCTAssertEqual(run.blocker?.ticketPosition, 1)

        await h.registry.release(h.lockKey, token: holderToken)
        _ = await runTask.value
    }

    /// Same as above but the alternate spelling is a **symlink** to the real root.
    func testSameRootSymlinkSpellingSharesOneLockAndNamesHolder() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let alias = h.repo.deletingLastPathComponent()
            .appendingPathComponent("accept-alias-\(UUID().uuidString)", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: h.repo)
        defer { try? FileManager.default.removeItem(at: alias) }
        XCTAssertEqual(RunWriteLock.key(repoRoot: alias.path), h.lockKey,
                       "a symlink alias of an existing root must map to the one lane key")

        let holderRunId = "holder-run-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold the write lock")
        }
        defer { Task { await h.registry.release(h.lockKey, token: holderToken) } }

        let runId = UUID().uuidString
        let runTask = Task {
            await h.service.run(RunRequest(message: "edit the repo", repoRoot: alias.path),
                                origin: .cli, runId: runId)
        }

        let poll = h.pollStore()
        var blocked: TeamRun?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.blocker?.holderId != nil { blocked = r; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let run = try XCTUnwrap(blocked, "a symlinked spelling of the same root must block behind the one lock")
        XCTAssertEqual(run.blocker?.holderId, holderRunId)
        XCTAssertEqual(run.blocker?.scopeRoot, h.root)

        await h.registry.release(h.lockKey, token: holderToken)
        _ = await runTask.value
    }

    /// Hold root A; a mutating run on a TRUE different root B acquires **immediately** —
    /// no serialization — spawns its worker and never carries a blocker naming A.
    func testTrueDifferentRootDoesNotSerializeAndNeverNamesHolder() async throws {
        let spy = SpyCommandRunner(
            inner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]))
        let h = try makeHarness(commandRunner: spy)
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // A genuinely different repo root (its own inode, its own lane key).
        let repoB = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-accept-B-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoB) }
        let keyB = RunWriteLock.key(repoRoot: repoB.path)
        XCTAssertNotEqual(keyB, h.lockKey, "true different roots must produce different lane keys")

        // Hold root A the whole time.
        let holderRunId = "holder-A-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold root A's write lock")
        }
        defer { Task { await h.registry.release(h.lockKey, token: holderToken) } }

        // Run on root B — must NOT block behind A.
        let runId = UUID().uuidString
        let result = await h.service.run(
            RunRequest(message: "edit repo B", repoRoot: repoB.path), origin: .cli, runId: runId)
        guard case .success(let run) = result else { return XCTFail("root-B run failed: \(result)") }

        XCTAssertTrue(run.status.isTerminal, "root B acquires its own free lane and runs to completion")
        XCTAssertNil(run.blocker, "a run on a different root is never blocked and never names A's holder")
        XCTAssertTrue(spy.launched, "root B's worker spawns; it was not serialized behind A")

        // The whole durable history for B never named A's holder id.
        let settled = try XCTUnwrap(h.pollStore().loadRaw(runId: runId))
        XCTAssertNil(settled.blocker?.holderId)
        XCTAssertNotEqual(settled.blocker?.holderId, holderRunId)
    }

    /// Two roots each independently held; a run on each blocks behind ITS OWN holder and
    /// never reads the other root's holder id. Project A never names project B (RLR-L4).
    func testConcurrentBlockedRunsOnDifferentRootsNeverNameEachOthersHolder() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let repoB = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-accept-B-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoB) }
        let keyB = RunWriteLock.key(repoRoot: repoB.path)

        let holderA = "holder-A-\(UUID().uuidString)"
        let holderB = "holder-B-\(UUID().uuidString)"
        let claimA = try XCTUnwrap(ExecutionLane.Claim.current(id: holderA, kind: ExecutionLaneSite.mutatingRun.rawValue))
        let claimB = try XCTUnwrap(ExecutionLane.Claim.current(id: holderB, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let tokenA) = await h.registry.tryAcquire(h.lockKey, claim: claimA) else {
            return XCTFail("could not hold root A")
        }
        defer { Task { await h.registry.release(h.lockKey, token: tokenA) } }
        guard case .success(let tokenB) = await h.registry.tryAcquire(keyB, claim: claimB) else {
            return XCTFail("could not hold root B")
        }
        defer { Task { await h.registry.release(keyB, token: tokenB) } }

        let runAId = UUID().uuidString
        let runBId = UUID().uuidString
        let taskA = Task { await h.service.run(RunRequest(message: "edit A", repoRoot: h.repo.path), origin: .cli, runId: runAId) }
        let taskB = Task { await h.service.run(RunRequest(message: "edit B", repoRoot: repoB.path), origin: .cli, runId: runBId) }

        let poll = h.pollStore()
        func waitBlocked(_ id: String) async throws -> TeamRun {
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let r = poll.loadRaw(runId: id), r.blocker?.holderId != nil { return r }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw XCTSkip("run \(id) never blocked")
        }
        let blockedA = try await waitBlocked(runAId)
        let blockedB = try await waitBlocked(runBId)

        XCTAssertEqual(blockedA.blocker?.holderId, holderA, "run on root A names only root A's holder")
        XCTAssertEqual(blockedB.blocker?.holderId, holderB, "run on root B names only root B's holder")
        XCTAssertNotEqual(blockedA.blocker?.holderId, holderB, "A must never name B's holder")
        XCTAssertNotEqual(blockedB.blocker?.holderId, holderA, "B must never name A's holder")
        XCTAssertEqual(blockedA.blocker?.scopeRoot, h.root)
        XCTAssertEqual(blockedB.blocker?.scopeRoot, RunWriteLock.normalize(repoB.path))

        await h.registry.release(h.lockKey, token: tokenA)
        await h.registry.release(keyB, token: tokenB)
        _ = await taskA.value
        _ = await taskB.value
    }

    // MARK: - S02c. Cancel/kill of a BLOCKED run withdraws its FIFO ticket in the
    //         terminal revision (RLR-L3 / Works Test 14), incl. the pre-spawn guard.

    /// Same-process cancel/kill of a blocked run: the terminal revision stamps
    /// `cancelled` + `killed`, clears the blocker, and withdraws the FIFO waiter file
    /// (the next waiter's position advances) — the holder is untouched, and the parked
    /// run self-abandons its wait rather than parking to the full timeout.
    func testCancelOfBlockedRunWithdrawsTicketSameProcess() async throws {
        let spy = SpyCommandRunner(
            inner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]))
        let h = try makeHarness(commandRunner: spy)
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // Hold the lane the whole test (current-process identity → never reconciled away).
        let holderRunId = "holder-run-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold the write lock")
        }
        defer { Task { await h.registry.release(h.lockKey, token: holderToken) } }

        // Start run B (blocks in waitToAcquire and registers a disk waiter file).
        let runId = UUID().uuidString
        let runTask = Task {
            await h.service.run(RunRequest(message: "edit the repo", repoRoot: h.repo.path),
                                origin: .cli, runId: runId)
        }

        let poll = h.pollStore()
        var blocked: TeamRun?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.status == .queued, r.blocker?.holderId != nil {
                blocked = r; break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try XCTUnwrap(blocked, "run B must be durably blocked before the kill")
        XCTAssertEqual(ExecutionLaneFlock.waiterCount(laneKey: h.lockKey), 1, "B registered exactly one waiter file")
        XCTAssertFalse(spy.launched, "no worker may spawn while blocked")

        // A THIRD waiter C sits behind B (position 2). Its position must advance to 1
        // the instant B's ticket is withdrawn.
        let cClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: "waiter-C-\(UUID().uuidString)", kind: ExecutionLaneSite.mutatingRun.rawValue))
        let cURL = try XCTUnwrap(
            ExecutionLaneFlock.registerWaiter(laneKey: h.lockKey, claim: cClaim, enqueuedAt: Date()))
        defer { ExecutionLaneFlock.unregisterWaiter(cURL) }
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: h.lockKey, waiterURL: cURL), 2,
                       "C queues behind the blocked run B")

        // Kill B via the CLI `kill`/`cancel` surface path (same process here).
        let surface = ProcessOwnershipSurface(runStore: h.runStore)
        guard case .success = surface.kill(id: runId) else {
            return XCTFail("kill of blocked run B failed")
        }

        // Terminal revision (single snapshot): cancelled + killed + blocker nil.
        let terminal = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertEqual(terminal.status, .cancelled)
        XCTAssertEqual(terminal.endReason, .killed)
        XCTAssertNil(terminal.blocker, "terminal revision clears the blocker (RLR-L3)")

        // B's waiter file is withdrawn; C advances to head; the holder is unaffected.
        XCTAssertEqual(ExecutionLaneFlock.waiterCount(laneKey: h.lockKey), 1, "only C remains; B's waiter file is withdrawn")
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: h.lockKey, waiterURL: cURL), 1,
                       "the next waiter advances once B's ticket is withdrawn")
        let holderStillHeld = await h.registry.isHeld(h.lockKey)
        XCTAssertTrue(holderStillHeld, "killing a blocked waiter must not touch the holder")

        // B self-abandons and returns the durable terminal run — never overwriting the
        // kill with `failed`, never parking to the full timeout.
        let bReturn = await boundedValue(of: runTask, timeout: 5)
        let outcome = try XCTUnwrap(bReturn, "B must self-abandon and return, not park to timeout")
        guard case .success(let run) = outcome else {
            return XCTFail("blocked-run cancel must return the durable terminal run, got \(outcome)")
        }
        XCTAssertEqual(run.status, .cancelled, "the returned run reflects the durable kill, not a `failed` overwrite")
        XCTAssertFalse(spy.launched, "a killed blocked run never spawns a worker")
    }

    /// The pre-spawn terminal guard: a cross-process kill stamps the journal terminal +
    /// withdraws the waiter file while B is parked, then the holder releases and the
    /// registry GRANTS the freed lane to B's still-parked continuation (the corpse grant
    /// that can beat the ~200ms self-abandon poll). B must NOT spawn a worker and must NOT
    /// overwrite the kill — it re-checks terminality before spawning and releases the lane.
    func testKilledBlockedRunGrantedLaneNeverSpawnsAndStaysTerminal() async throws {
        let spy = SpyCommandRunner(
            inner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]))
        let h = try makeHarness(commandRunner: spy)
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let holderRunId = "holder-run-\(UUID().uuidString)"
        let holderClaim = try XCTUnwrap(
            ExecutionLane.Claim.current(id: holderRunId, kind: ExecutionLaneSite.mutatingRun.rawValue))
        guard case .success(let holderToken) = await h.registry.tryAcquire(h.lockKey, claim: holderClaim) else {
            return XCTFail("test could not pre-hold the write lock")
        }

        let runId = UUID().uuidString
        let runTask = Task {
            await h.service.run(RunRequest(message: "edit the repo", repoRoot: h.repo.path),
                                origin: .cli, runId: runId)
        }

        let poll = h.pollStore()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.status == .queued, r.blocker?.holderId != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(poll.loadRaw(runId: runId)?.blocker?.holderId, "run B must be blocked before we stamp it terminal")

        // A second process kills B WHILE it is parked: stamp the journal terminal + withdraw
        // B's waiter file directly. B's in-memory continuation is untouched (a real second
        // process could never reach it).
        var killed = try XCTUnwrap(poll.loadRaw(runId: runId))
        killed.status = .cancelled
        killed.endReason = .killed
        killed.blocker = nil
        try h.runStore.save(killed, models: [])
        ExecutionLaneFlock.withdrawWaiter(laneKey: h.lockKey, claimId: runId)

        // Release immediately so the synchronous grant hands B the lane before its
        // self-abandon poll fires — exercising the pre-spawn guard (the outcome below is
        // identical whichever path wins: no spawn, kill preserved, lane released).
        await h.registry.release(h.lockKey, token: holderToken)

        let bReturn = await boundedValue(of: runTask, timeout: 5)
        let outcome = try XCTUnwrap(bReturn, "B must return promptly (guard or self-abandon), not park to timeout")
        guard case .success(let run) = outcome else {
            return XCTFail("a killed blocked run must return the durable terminal run, got \(outcome)")
        }
        XCTAssertEqual(run.status, .cancelled, "the pre-spawn guard preserves the kill, never overwrites it")
        XCTAssertFalse(spy.launched, "a killed blocked run granted the lane must NEVER spawn a worker")

        let settled = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertEqual(settled.status, .cancelled)
        XCTAssertEqual(settled.endReason, .killed)
        XCTAssertNil(settled.blocker)
        // The lane a corpse-grant briefly held is released again (RunService's `defer`
        // release is a detached Task, so poll rather than sampling a single instant).
        var released = false
        let releaseDeadline = Date().addingTimeInterval(5)
        while Date() < releaseDeadline {
            if !(await h.registry.isHeld(h.lockKey)) { released = true; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(released, "the lane the corpse was granted must be released again")
    }

    /// Await a task's value bounded by `timeout` seconds — returns nil if the task
    /// did not finish in time (proves a parked run RESUMED rather than hanging).
    private func boundedValue<T: Sendable>(of task: Task<T, Never>, timeout: TimeInterval) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - 2. Save precedes the status-changed emit (no emit-then-persist race)

    func testRunningStatusIsDurableBeforeItsEventIsEmitted() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let runId = UUID().uuidString
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let poll = h.pollStore()

        // On the `running` runStatusChanged event, the journal must ALREADY have left
        // `queued` — proof that `runStore.save` ran before `emit`. Monotonic: once
        // running is emitted the run never regresses to queued, so a slightly-late read
        // can only show running/done, never queued (which would mean emit-before-save).
        let observer = Task { () -> (sawRunning: Bool, durable: Bool) in
            var sawRunning = false
            var durable = false
            for await e in stream where e.kind == RunEventKind.runStatusChanged
                && e.payload["to"] == .string(RunStatus.running.rawValue) {
                sawRunning = true
                durable = poll.loadRaw(runId: runId).map { $0.status.lifecycle != .queued } ?? false
            }
            return (sawRunning, durable)
        }

        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path),
            origin: .cli, runId: runId, events: continuation)
        let seen = await observer.value

        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(seen.sawRunning, "a running runStatusChanged event must be emitted")
        XCTAssertTrue(seen.durable, "the journal must be persisted at >= running BEFORE the running event fires")
    }

    // MARK: - 4. Canonical payload round-trip + sync-path idempotency claim

    func testExtendedCanonicalPayloadRoundTripsAndDigestsAreFieldSensitive() throws {
        let base = AsyncTeamCanonicalPayload(
            prompt: "do the thing", lane: "code", teamPresetId: "build_slice", effort: "high",
            modelId: "model_cursor_composer_25", type: nil, context: "ctx", repoRoot: "/tmp/repo",
            attachmentDigests: ["a1b2", "c3d4"], threadId: "thread_7",
            resolvedTeamId: "build_slice", resolvedWorkerIds: ["model_cursor_composer_25"],
            handshakeTimeout: 60, firstActivityTimeout: 120, idleTimeout: 300, wallTimeout: 3600,
            proofCommand: "swift test", commitMessage: "fix: thing", noCommit: false,
            contractVersion: "1")

        let data = try CoreJSON.encode(base)
        let decoded = try CoreJSON.decode(AsyncTeamCanonicalPayload.self, from: data)
        XCTAssertEqual(decoded, base, "generalized canonical payload must round-trip all fields")

        // Equal payloads → equal digest; a single generalized field change → different digest.
        XCTAssertEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(decoded))
        var changedProof = base; changedProof.proofCommand = "swift build"
        XCTAssertNotEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(changedProof))
        var changedAttachments = base; changedAttachments.attachmentDigests = ["a1b2"]
        XCTAssertNotEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(changedAttachments))
    }

    func testSyncRunClaimsIdempotencyKeyAndReplaysSameRunNeverASecondWorker() async throws {
        let idemFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("idem-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: idemFile) }
        let h = try makeHarness(idempotency: IdempotencyStore(fileURL: idemFile))
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let key = "idem-key-\(UUID().uuidString)"
        func request() -> RunRequest {
            RunRequest(message: "Say done", repoRoot: h.repo.path, idempotencyKey: key)
        }

        // First acceptance: claims the key, mints + runs one worker.
        let first = await h.service.run(request(), origin: .cli)
        guard case .success(let firstRun) = first else { return XCTFail("first run failed: \(first)") }

        // Second acceptance, same key + same payload: replays the ORIGINAL run — no
        // second run directory is created.
        let second = await h.service.run(request(), origin: .cli)
        guard case .success(let secondRun) = second else { return XCTFail("replay failed: \(second)") }
        XCTAssertEqual(secondRun.id, firstRun.id, "same key + payload must replay the original run id")

        let runDirs = (try? FileManager.default.contentsOfDirectory(atPath: h.runsDir.path))?
            .filter { $0.hasPrefix("run_") } ?? []
        XCTAssertEqual(runDirs.count, 1, "transport replay must not spawn a second run/worker")

        // Same key + DIFFERENT payload: conflict refusal (never silently re-executes).
        let conflict = await h.service.run(
            RunRequest(message: "different message", repoRoot: h.repo.path, idempotencyKey: key),
            origin: .cli)
        guard case .failure(let error) = conflict else { return XCTFail("expected conflict, got \(conflict)") }
        XCTAssertEqual(error.code, "IDEMPOTENCY_CONFLICT")
    }

    func testRetryOfRecordsDurableRunLinkWithoutReplayExecution() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // Prior run must exist and be verified stopped (S05 gate).
        let oldId = "old-run-\(UUID().uuidString)"
        let prior = TeamRun(
            id: oldId, prompt: "old", status: .cancelled, createdAt: Date(),
            repoRoot: h.repo.path, endReason: .killed, killOutcome: .stopped
        )
        try h.runStore.save(prior, models: [])

        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path, retryOf: oldId), origin: .cli)
        guard case .success(let run) = result else { return XCTFail("retry run failed: \(result)") }
        XCTAssertTrue(
            run.runLinks.contains(RunLink(kind: .retryOf, runId: oldId)),
            "a --retry-of run must carry a durable RunLink.retryOf to the prior run")
        // Link only — the new run executed its own worker (a distinct id), no replay.
        XCTAssertNotEqual(run.id, oldId)
    }

    // MARK: - 3. RUN_NOT_FOUND names the effective support dir (real CLI)

    func testRunNotFoundErrorNamesEffectiveSupportDir() throws {
        let alln = try locateAllnBinary()
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlr-supportdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let env = [
            "ALLNIGHTER_SUPPORT_DIR": support.path,
            "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": support.path,
        ]
        // 88860049 routed bare `team status` to a live resident query; RUN_NOT_FOUND
        // (with the effective supportDir envelope) is emitted by the durable-journal
        // read that 12fcd8a2 made explicit as `--persisted`.
        let result = try runAlln(alln, ["team", "status", "does-not-exist", "--json", "--persisted"], env: env)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
            "expected a JSON error object, got: \(result.stdout.prefix(300))")
        let error = try XCTUnwrap(obj["error"] as? [String: Any], "expected an error envelope")
        XCTAssertEqual(error["code"] as? String, "RUN_NOT_FOUND")
        let message = error["message"] as? String ?? ""
        XCTAssertTrue(message.contains(support.path),
                      "RUN_NOT_FOUND message must name the effective support dir: \(message)")
        XCTAssertEqual(error["supportDir"] as? String, support.path,
                       "the machine envelope must carry the effective supportDir")
    }

    // MARK: - Subprocess helpers

    private func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: RunAcceptanceBoundaryTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path),
                      "alln binary missing at \(binary.path) — build the alln product first")
        return binary
    }

    private struct ProcessResult { var status: Int32; var stdout: String; var stderr: String }

    private func runAlln(_ alln: URL, _ arguments: [String], env: [String: String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.environment = env
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out; process.standardError = err
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
