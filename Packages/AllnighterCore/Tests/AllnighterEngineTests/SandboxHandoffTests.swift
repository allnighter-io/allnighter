import XCTest
import AllnighterCore
@testable import AllnighterCLI
@testable import AllnighterEngine

/// The sandbox hand-off: a caller that cannot start vendor CLIs drops a request,
/// a host outside the sandbox runs it through the SAME RunService, and the result
/// lands in the ordinary run journal the caller polls.
/// A clock that advances a fixed step per read, so wait policy is asserted in
/// simulated time instead of real sleeping.
private final class TickingClock: @unchecked Sendable {
    private let base: Date
    private let step: TimeInterval
    private var reads = 0
    init(base: Date, step: TimeInterval) { self.base = base; self.step = step }
    func now() -> Date {
        defer { reads += 1 }
        return base.addingTimeInterval(step * Double(reads))
    }
}

/// Counts polls across the concurrently-executing wait loop.
private final class PollCounter: @unchecked Sendable {
    private var count = 0
    func next() -> Int { count += 1; return count }
    var value: Int { count }
}

/// Collects the caller-facing notes so a test can assert what the user was told.
private final class NoteSink: @unchecked Sendable {
    private var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
    var text: String { lines.joined() }
}

final class SandboxHandoffTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func spool() -> SandboxHandoffSpool {
        SandboxHandoffSpool(directory: tmp.appendingPathComponent("Handoff", isDirectory: true))
    }

    private static func makeService(runStore: RunStore) -> RunService {
        RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "Handed off.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_opus"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    func testRequestDroppedInTheMailboxIsRunAndReadableFromTheRunJournal() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()

        // Inside the sandbox: drop the request with the run id the caller will poll.
        let runId = "handoff-run-1"
        try box.enqueue(.init(runId: runId, message: "do the thing", repoRoot: repo.path,
                              workerId: "model_opus"))
        XCTAssertEqual(try box.unclaimed().count, 1)

        // Outside the sandbox: run it.
        let started = await SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore), owner: "test").drainOnce()

        XCTAssertEqual(started, [runId])
        XCTAssertTrue(try box.unclaimed().isEmpty, "a finished request leaves the mailbox")

        // Back inside the sandbox: the answer is in the ordinary journal.
        let run: TeamRun = try XCTUnwrap(runStore.load(runId: runId))
        XCTAssertEqual(run.status, .complete)
        XCTAssertEqual(RunWriteLock.normalize(run.repoRoot ?? ""), RunWriteLock.normalize(repo.path))
    }

    /// Two hosts may watch the same mailbox; a request must run exactly once.
    /// The bug this packet exists for: a request the host claims but cannot start
    /// used to vanish — no journal, no error — leaving the caller to time out and
    /// be told, falsely, that nothing had picked it up. A refusal is an answer.
    func testARefusedRequestStillLeavesAReadableTerminalRun() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        HandoffLog.fileURL = tmp.appendingPathComponent("handoff.log", isDirectory: false)
        defer { HandoffLog.fileURL = nil }

        // A worker id no bench can resolve: RunService refuses BEFORE minting a run,
        // which is the exact class that used to evaporate.
        let runId = "handoff-refused-1"
        try box.enqueue(.init(runId: runId, message: "do the thing", repoRoot: repo.path,
                              workerId: "model_does_not_exist"))

        let settled = await SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore),
            runStore: runStore, owner: "test").drainOnce()

        XCTAssertEqual(settled, [runId], "a refusal is still a settled request")
        XCTAssertTrue(try box.unclaimed().isEmpty, "a refused request leaves the mailbox")

        let run: TeamRun = try XCTUnwrap(
            runStore.load(runId: runId), "the caller polls this id — it must exist")
        XCTAssertEqual(run.status, .failed)
        XCTAssertTrue(run.status.isTerminal, "a waiting caller only stops on a terminal status")
        XCTAssertFalse(run.warnings.isEmpty, "the refusal must carry its reason, not just a status")
        XCTAssertTrue(
            run.warnings.contains { $0.contains("model_does_not_exist") },
            "the reason must name the actual problem, got: \(run.warnings)")

        let log = try String(contentsOf: XCTUnwrap(HandoffLog.fileURL), encoding: .utf8)
        XCTAssertTrue(log.contains("claimed run=\(runId)"), "the host must record the claim")
        XCTAssertTrue(log.contains("refused run=\(runId)"), "the host must record the refusal")
    }

    // MARK: - Liveness check (`alln doctor handoff`)

    /// A ping must never reach `RunService`: the whole point is a verdict that costs
    /// no seat and no quota. The mock here would answer "Handed off." if a worker ran,
    /// so an empty answer set is the proof that none did.
    func testAPingIsSettledWithoutStartingAnyWorker() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        HandoffLog.fileURL = tmp.appendingPathComponent("handoff.log", isDirectory: false)
        defer { HandoffLog.fileURL = nil }

        let runId = "handoff-ping-1"
        try box.enqueue(.init(runId: runId, message: "handoff liveness check",
                              repoRoot: "/tmp/x", kind: .ping))

        let settled = await SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore),
            runStore: runStore, owner: "test").drainOnce()

        XCTAssertEqual(settled, [runId])
        let run: TeamRun = try XCTUnwrap(runStore.load(runId: runId))
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(run.workerAnswers.isEmpty, "a ping must not start a worker")
        XCTAssertTrue(run.warnings.contains { $0.contains("HANDOFF_HOST_ALIVE") })

        let log = try String(contentsOf: XCTUnwrap(HandoffLog.fileURL), encoding: .utf8)
        XCTAssertTrue(log.contains("kind=ping"), "the log must distinguish a ping from real work")
    }

    func testDoctorReportsHostNotRunningWhenNothingDrainsTheMailbox() async {
        let doctor = HandoffDoctor(
            spool: spool(),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true)),
            waitSeconds: 0.3, pollSeconds: 0.05)

        let report = await doctor.check(contractVersion: "test", repoRoot: "/tmp/x")

        XCTAssertEqual(report.verdict, .hostNotRunning)
        XCTAssertFalse(report.isHealthy)
        XCTAssertNil(report.claimedBy)
    }

    func testDoctorReportsHealthyWhenAHostAnswersThePing() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let runner = SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore),
            runStore: runStore, owner: "test-host", pollSeconds: 0.05)

        let draining = Task.detached { await runner.run { Task.isCancelled } }
        defer { draining.cancel() }

        let report = await HandoffDoctor(
            spool: box, runStore: runStore, waitSeconds: 5, pollSeconds: 0.05
        ).check(contractVersion: "test", repoRoot: "/tmp/x")

        XCTAssertEqual(report.verdict, .healthy, "detail was: \(report.detail)")
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.claimedBy, "test-host", "a healthy verdict must name who answered")
    }

    // MARK: - The wait (S2): no work deadline, and no guessing

    /// The bound this replaces gave up at 180s and then blamed a closed app. A run
    /// that takes longer than any fixed deadline must still come back.
    func testAWaitOutlivesTheOldOneHundredEightySecondDeadline() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let request = try box.enqueue(.init(runId: "handoff-slow", message: "m", repoRoot: "/tmp/x"))
        _ = try box.claim(id: request.id, by: "slow-host")

        // A clock that has already run far past the retired deadline, so the test
        // asserts the policy rather than sleeping through it.
        let base = Date()
        let ticks = TickingClock(base: base, step: 60)
        let settleAfter = 5   // ≈300 simulated seconds — beyond the old 180s bound
        let polls = PollCounter()
        let store = runStore
        let noted = NoteSink()

        let finished = await SandboxHandoff.waitForHandoff(
            runId: "handoff-slow", requestId: request.id, spool: box, runStore: runStore,
            clock: {
                if polls.next() == settleAfter {
                    _ = try? store.save(
                        TeamRun(id: "handoff-slow", prompt: "m", status: .complete,
                                createdAt: base, endReason: .completed),
                        models: [])
                }
                return ticks.now()
            },
            note: { noted.append($0) })

        XCTAssertEqual(finished?.id, "handoff-slow",
                       "a run past the old deadline must still be returned")
        XCTAssertTrue(noted.text.contains("still running"), "a long wait must report progress")
        XCTAssertFalse(noted.text.contains("isn't open"), "never blame a host that claimed the work")
    }

    /// The specific lie: nothing had claimed the request, and the caller said the
    /// app was closed without looking. Now it looks — and only then says so.
    func testAnUnclaimedRequestIsReportedAsNothingListening() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let request = try box.enqueue(.init(runId: "handoff-orphan", message: "m", repoRoot: "/tmp/x"))
        let ticks = TickingClock(base: Date(), step: 10)
        let noted = NoteSink()

        let finished = await SandboxHandoff.waitForHandoff(
            runId: "handoff-orphan", requestId: request.id, spool: box, runStore: runStore,
            clock: { ticks.now() }, note: { noted.append($0) })

        XCTAssertNil(finished)
        XCTAssertTrue(noted.text.contains("Nothing picked this up"))
        XCTAssertTrue(noted.text.contains("alln run resume handoff-orphan"),
                      "the caller must be told how to collect it later")
    }

    /// Claimed and then silent is a different problem from nobody listening, and
    /// must never be reported as "Allnighter isn't open".
    func testAClaimedButStalledRequestIsNotBlamedOnAClosedApp() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let request = try box.enqueue(.init(runId: "handoff-stalled", message: "m", repoRoot: "/tmp/x"))
        _ = try box.claim(id: request.id, by: "stuck-host")
        let ticks = TickingClock(base: Date(), step: 600)   // blow the stall backstop fast
        let noted = NoteSink()

        let finished = await SandboxHandoff.waitForHandoff(
            runId: "handoff-stalled", requestId: request.id, spool: box, runStore: runStore,
            clock: { ticks.now() }, note: { noted.append($0) })

        XCTAssertNil(finished)
        XCTAssertTrue(noted.text.contains("without finishing it"))
        XCTAssertFalse(noted.text.contains("Nothing picked this up"),
                       "a claimed request was picked up — say so")
    }

    // MARK: - Staleness (S5)

    /// The inferred cause of the original incident: the host built its RunService
    /// once at launch and held it forever, so an app open all day kept the roster it
    /// read at startup and refused work after the roster changed on disk. The
    /// service must be rebuilt per claimed request, not snapshotted.
    func testTheHostBuildsAFreshRunServiceForEveryRequest() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let builds = PollCounter()
        let runner = SandboxHandoffRunner(
            spool: box,
            makeRunService: {
                _ = builds.next()
                return Self.makeService(runStore: runStore)
            },
            runStore: runStore, owner: "test")

        try box.enqueue(.init(runId: "handoff-a", message: "m", repoRoot: "/tmp/x",
                              workerId: "model_opus"))
        await runner.drainOnce()
        try box.enqueue(.init(runId: "handoff-b", message: "m", repoRoot: "/tmp/x",
                              workerId: "model_opus"))
        await runner.drainOnce()

        XCTAssertEqual(builds.value, 2,
                       "a held service goes stale — build one per request, not per host")
    }

    /// …and idle polling must not pay for it.
    func testAnIdleHostBuildsNoRunServiceAtAll() async {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let builds = PollCounter()
        let runner = SandboxHandoffRunner(
            spool: spool(),
            makeRunService: {
                _ = builds.next()
                return Self.makeService(runStore: runStore)
            },
            runStore: runStore, owner: "test")

        await runner.drainOnce()
        await runner.drainOnce()

        XCTAssertEqual(builds.value, 0, "an empty mailbox must cost nothing")
    }

    // MARK: - Claim safety (S6)

    private static func slowService(runStore: RunStore, seconds: Double) -> RunService {
        RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: [
                "claude": .init(stdout: "Slow answer.", exitCode: 0,
                                delay: .milliseconds(Int(seconds * 1000)))
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_opus"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    /// A long run must not stop the host claiming later requests. When the drain
    /// awaited its own work, a six-seat review blocked the liveness ping behind it,
    /// so `alln doctor handoff` reported "nothing is listening" about a host that
    /// was visibly busy — a diagnostic lying about the thing it exists to check.
    func testALongRunDoesNotStarveALaterPing() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let runner = SandboxHandoffRunner(
            spool: box,
            makeRunService: { Self.slowService(runStore: runStore, seconds: 3) },
            runStore: runStore, owner: "test-host", pollSeconds: 0.05)

        // A REAL directory: an unresolvable root makes RunService refuse instantly,
        // which would make this test pass without ever exercising a slow run.
        let repo = tmp.appendingPathComponent("slow-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try box.enqueue(.init(runId: "handoff-slow-work", message: "m", repoRoot: repo.path,
                              workerId: "model_opus"))
        let loop = Task.detached { await runner.run { Task.isCancelled } }
        defer { loop.cancel() }

        // Arrives while the slow run is still in flight.
        try await Task.sleep(for: .milliseconds(300))
        try box.enqueue(.init(runId: "handoff-late-ping", message: "ping",
                              repoRoot: "/tmp/x", kind: .ping))

        var pinged = false
        for _ in 0..<40 where !pinged {
            if runStore.load(runId: "handoff-late-ping")?.status.isTerminal == true { pinged = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(pinged, "the ping must be answered while the slow run is still going")
        // Not merely "not complete": a run that FAILED fast would satisfy that
        // vacuously and the test would prove nothing about starvation.
        let slow = runStore.load(runId: "handoff-slow-work")
        XCTAssertNotNil(slow, "the slow run must have been claimed and started")
        XCTAssertFalse(slow?.status.isTerminal ?? true,
                       "the slow run must still be IN FLIGHT when the ping is answered, "
                       + "otherwise this test proves nothing; got \(String(describing: slow?.status))")
    }

    /// A claim held by a process that has since died is not a claim. Nothing else
    /// releases these, so without reclaim the request is stranded forever and its
    /// caller is told, wrongly, that nothing ever picked the work up.
    func testAClaimHeldByADeadHostIsReclaimed() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let request = try box.enqueue(.init(runId: "handoff-orphaned", message: "m",
                                            repoRoot: "/tmp/x", workerId: "model_opus"))
        // A pid that cannot be alive, with a start time that cannot match.
        _ = try box.claim(id: request.id, by: "dead-host", pid: 2_000_000, startTimeTicks: 1)
        XCTAssertTrue(try box.unclaimed().isEmpty, "precondition: it is claimed")

        let settled = await SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore),
            runStore: runStore, owner: "live-host").drainOnce()

        XCTAssertEqual(settled, ["handoff-orphaned"], "a dead host's claim must be taken over")
        XCTAssertNotNil(runStore.load(runId: "handoff-orphaned"))
    }

    /// …but a claim held by a LIVE host must never be stolen.
    func testAClaimHeldByALiveHostIsLeftAlone() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let request = try box.enqueue(.init(runId: "handoff-held", message: "m", repoRoot: "/tmp/x"))
        let me = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        _ = try box.claim(id: request.id, by: "other-live-host",
                          pid: me.pid, startTimeTicks: me.startTimeTicks)

        let settled = await SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore),
            runStore: runStore, owner: "live-host").drainOnce()

        XCTAssertTrue(settled.isEmpty, "a live host's work must not be double-run")
        XCTAssertEqual(box.request(id: request.id)?.claimedBy, "other-live-host")
    }

    func testAClaimRecordsTheClaimingProcessIdentity() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))
        let box = spool()
        let request = try box.enqueue(.init(runId: "handoff-identity", message: "m",
                                            repoRoot: "/tmp/x", kind: .ping))
        // Claim without executing, by running a drain that only claims.
        let runner = SandboxHandoffRunner(
            spool: box, runService: Self.makeService(runStore: runStore),
            runStore: runStore, owner: "identity-host")
        _ = await runner.drainOnce()
        _ = request

        // The request is gone once settled, so identity is asserted on a fresh claim.
        let second = try box.enqueue(.init(runId: "handoff-identity-2", message: "m",
                                           repoRoot: "/tmp/x"))
        let me = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        let claimed = try XCTUnwrap(try box.claim(
            id: second.id, by: "identity-host", pid: me.pid, startTimeTicks: me.startTimeTicks))
        XCTAssertEqual(claimed.claimantPid, me.pid)
        XCTAssertEqual(claimed.claimantStartTimeTicks, me.startTimeTicks)
    }

    /// The founder-facing failure: the app was killed mid-review. The run stayed at
    /// `fanning_out` forever, the caller waited with no notification, and the answer
    /// never came. A run whose owner is gone must settle, and the waiter must say so.
    func testAWaiterSettlesARunWhoseOwnerDied() async throws {
        let runsRoot = tmp.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsRoot)
        let box = spool()
        let runId = "handoff-owner-died"

        // A non-terminal run owned by a pid that cannot be alive — what the app
        // leaves behind when it is killed part-way through a team run.
        _ = try runStore.save(
            TeamRun(id: runId, prompt: "review", status: .fanningOut, createdAt: Date()),
            models: [])
        let directory = runsRoot.appendingPathComponent("run_\(runId)", isDirectory: true)
        try Data("""
        {"kind":"inProcess","pid":2000000,"startTimeTicks":1}
        """.utf8).write(to: directory.appendingPathComponent("owner.json"))

        let ticks = TickingClock(base: Date(), step: 1)
        let noted = NoteSink()
        let finished = await SandboxHandoff.waitForHandoff(
            runId: runId, requestId: nil, spool: box, runStore: runStore,
            clock: { ticks.now() }, note: { noted.append($0) })

        XCTAssertEqual(finished?.status, .interrupted,
                       "a run whose owner is gone must settle, not hang the caller")
        XCTAssertEqual(finished?.endReason, .reconciledOrphan)
        XCTAssertTrue(noted.text.contains("stopped before finishing this run"),
                      "the caller must be TOLD, not just left waiting")
    }

    // MARK: - Mailbox robustness

    /// A request written before `kind` existed must still run, as ordinary work.
    func testARequestWithNoKindDecodesAsRun() throws {
        let box = spool()
        try FileManager.default.createDirectory(at: box.directory, withIntermediateDirectories: true)
        let legacy = """
        {"id":"legacy-1","runId":"handoff-legacy","message":"m","repoRoot":"/tmp/x",\
        "createdAt":"2026-07-24T00:00:00Z"}
        """
        try Data(legacy.utf8).write(to: box.directory.appendingPathComponent("legacy-1.json"))

        let waiting = try box.unclaimed()
        XCTAssertEqual(waiting.count, 1)
        XCTAssertEqual(waiting.first?.kind, .run, "a kind-less request is ordinary work, not a ping")
    }

    /// One unreadable file used to throw out of `unclaimed()` and make the whole
    /// mailbox look empty — starving every valid request behind it.
    func testOneCorruptRequestDoesNotHideTheRest() throws {
        let box = spool()
        try box.enqueue(.init(runId: "handoff-good", message: "m", repoRoot: "/tmp/x"))
        try Data("{ this is not json".utf8)
            .write(to: box.directory.appendingPathComponent("corrupt.json"))

        let waiting = try box.unclaimed()

        XCTAssertEqual(waiting.map(\.runId), ["handoff-good"],
                       "a poison file must not hide a valid request")
    }

    func testARequestIsClaimedExactlyOnce() throws {
        let box = spool()
        let request = try box.enqueue(.init(runId: "r1", message: "m", repoRoot: "/tmp/x"))

        XCTAssertNotNil(try box.claim(id: request.id, by: "host-a"))
        XCTAssertNil(try box.claim(id: request.id, by: "host-b"),
                     "a second host must not take a claimed request")
        XCTAssertTrue(try box.unclaimed().isEmpty)
    }

    func testEmptyMailboxIsANoOp() async {
        let started = await SandboxHandoffRunner(
            spool: spool(),
            runService: Self.makeService(runStore: RunStore(rootDirectory: tmp.appendingPathComponent("r2"))),
            owner: "test").drainOnce()
        XCTAssertTrue(started.isEmpty)
    }
}
