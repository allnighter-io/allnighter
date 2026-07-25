import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// The sandbox hand-off: a caller that cannot start vendor CLIs drops a request,
/// a host outside the sandbox runs it through the SAME RunService, and the result
/// lands in the ordinary run journal the caller polls.
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

    private func makeService(runStore: RunStore) -> RunService {
        RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "Handed off.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .flagship, allowHealthySubstitutions: true,
                                     tiers: TierMembership(flagship: ["model_opus"]))
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
            spool: box, runService: makeService(runStore: runStore), owner: "test").drainOnce()

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
            spool: box, runService: makeService(runStore: runStore),
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
            runService: makeService(runStore: RunStore(rootDirectory: tmp.appendingPathComponent("r2"))),
            owner: "test").drainOnce()
        XCTAssertTrue(started.isEmpty)
    }
}
