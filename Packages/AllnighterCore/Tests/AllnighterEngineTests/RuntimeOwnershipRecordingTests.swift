import XCTest
import Darwin
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S04a seam tests: worker OS identity is recorded as `runtimeOwnership`
/// keyed by worker id at spawn (the same `spawnProcessGroupLeader` primitive both
/// the cold foreground `alln run` and the async `alln team start` paths drive),
/// the coordinator stays a separate owner, and identity-alive is zombie-aware
/// (RLR-L5). No kill behaviour is exercised here — that is S04b.
final class RuntimeOwnershipRecordingTests: XCTestCase {

    private var runDir: URL!

    override func setUpWithError() throws {
        runDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rlr-s04a-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: nil)
        try? FileManager.default.removeItem(at: runDir)
    }

    // MARK: - Recording keyed by worker id (mechanism shared by both cold paths)

    func testWorkerOwnerFileWrittenAtSpawnKeyedByWorkerIdWithAllFourFields() throws {
        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: runDir)

        let spawned = try ProcessOwnership.$currentWorkerId.withValue("r1") {
            try ProcessOwnership.spawnProcessGroupLeader(
                executablePath: "/bin/sleep", arguments: ["120"],
                workingDirectory: nil, kind: .devTurn)
        }
        defer { killLeader(spawned.pid) }

        // Durable receipt lands at workers/<safeStem(workerId)>.owner.json.
        let ownerURL = ProcessOwnership.workerOwnerURL(workerId: "r1", in: runDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerURL.path),
                      "worker runtimeOwnership receipt must be written at spawn")

        // readWorkerOwners round-trips the four identity fields keyed by worker id.
        let owners = ProcessOwnership.readWorkerOwners(inRunDirectory: runDir)
        XCTAssertEqual(owners.count, 1)
        let owner = try XCTUnwrap(owners.first)
        XCTAssertEqual(owner.workerId, "r1")
        XCTAssertEqual(owner.identity.pid, spawned.pid)                       // pid
        XCTAssertEqual(owner.identity.pgid, spawned.pid)                      // pgid == pid (group leader)
        XCTAssertEqual(owner.identity.startTimeTicks,                         // startTimeTicks
                       ProcessOwnership.processStartTimeTicks(spawned.pid))
        XCTAssertEqual(owner.identity.kind, .devTurn)                         // kind
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(owner.identity))
    }

    func testCoordinatorOwnerIsASeparateFileFromWorkerReceipts() throws {
        // Coordinator recorded at the run-dir-root owner.json (the "separate owner").
        let coordinator = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        try ProcessOwnership.writeOwnerIdentity(coordinator, in: runDir)

        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: runDir)
        let spawned = try ProcessOwnership.$currentWorkerId.withValue("r1") {
            try ProcessOwnership.spawnProcessGroupLeader(
                executablePath: "/bin/sleep", arguments: ["120"],
                workingDirectory: nil, kind: .devTurn)
        }
        defer { killLeader(spawned.pid) }

        let rootOwner = ProcessOwnership.ownerURL(in: runDir)
        let workerOwner = ProcessOwnership.workerOwnerURL(workerId: "r1", in: runDir)
        XCTAssertNotEqual(rootOwner.path, workerOwner.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootOwner.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workerOwner.path))

        // The coordinator (in-process) is NEVER a worker receipt.
        let coordRead = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir))
        XCTAssertEqual(coordRead.kind, .inProcess)
        XCTAssertNil(coordRead.pgid, "in-process coordinator is never PG-killable")
        XCTAssertEqual(ProcessOwnership.readWorkerOwners(inRunDirectory: runDir).map(\.workerId), ["r1"])
    }

    func testNoWorkerIdInScopeRecordsNothing() throws {
        // Context set, but no currentWorkerId task-local → no receipt (warm /
        // non-worker spawns record nothing; the exclusion seam for free).
        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: runDir)
        let spawned = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/bin/sleep", arguments: ["120"],
            workingDirectory: nil, kind: .devTurn)
        defer { killLeader(spawned.pid) }
        XCTAssertTrue(ProcessOwnership.readWorkerOwners(inRunDirectory: runDir).isEmpty)
    }

    // MARK: - Post-swap: worker is its OWN group leader (not setpgid-detached)

    func testRecordedWorkerIsProcessGroupLeaderAndGroupReachable() throws {
        // The async worker base runner is now ProcessGroupCommandRunner: the worker
        // is its own group leader (pgid == pid, atomic at spawn) and its children
        // share that pgid — i.e. the recorded tree is genuinely addressable, unlike
        // the old SubprocessCommandRunner setpgid detachment.
        ProcessOwnership.RuntimeOwnershipContext.shared.set(runDirectory: runDir)
        // A shell that forks a child sleep: the child inherits the leader's pgid.
        let spawned = try ProcessOwnership.$currentWorkerId.withValue("r1") {
            try ProcessOwnership.spawnProcessGroupLeader(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 121 & wait"],
                workingDirectory: nil, kind: .devTurn)
        }
        defer { killLeader(spawned.pid) }

        let owner = try XCTUnwrap(ProcessOwnership.readWorkerOwners(inRunDirectory: runDir).first)
        let pgid = try XCTUnwrap(owner.identity.pgid)
        XCTAssertEqual(pgid, spawned.pid, "recorded worker pgid must equal its own pid")

        // The recorded group is non-empty and contains the leader — group-reachable.
        var members: [Int32] = []
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            members = ProcessOwnership.processGroupMemberPids(pgid)
            if members.contains(spawned.pid) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(members.contains(spawned.pid),
                      "recorded worker group must be reachable (members: \(members))")
        XCTAssertFalse(ProcessOwnership.isProcessGroupEmpty(pgid))
    }

    // MARK: - Zombie-aware identity-alive (RLR-L5, Gap A)

    func testReapedButUnwaitedChildReadsNotAlive() throws {
        // A child that exits and is never waited becomes a <defunct> zombie:
        // kill(pid,0) succeeds and its start time still matches, but it is not
        // doing work — RLR-L5 identity-alive must exclude it.
        let spawned = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/usr/bin/true", arguments: [],
            workingDirectory: nil, kind: .devTurn)

        // Wait for the child to exit into the zombie state (never waitpid it).
        var isZombie = false
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if ProcessOwnership.processIsZombie(spawned.pid) { isZombie = true; break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(isZombie, "child must reach the zombie state")

        XCTAssertTrue(ProcessOwnership.processAlive(spawned.pid),
                      "kill(pid,0) still succeeds on a zombie (why the naive check lied)")
        XCTAssertEqual(ProcessOwnership.processStartTimeTicks(spawned.pid),
                       spawned.identity.startTimeTicks,
                       "start time still matches on a zombie")
        XCTAssertFalse(ProcessOwnership.isIdentityAlive(spawned.identity),
                       "zombie-aware identity-alive must read a <defunct> child as NOT alive")

        // Reap so the fixture leaves no zombie behind.
        var status: Int32 = 0
        _ = waitpid(spawned.pid, &status, 0)
    }

    func testLiveMatchingPidReadsAliveAndRecycledReadsDead() throws {
        let spawned = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/bin/sleep", arguments: ["120"],
            workingDirectory: nil, kind: .devTurn)
        defer { killLeader(spawned.pid) }

        XCTAssertTrue(ProcessOwnership.isIdentityAlive(spawned.identity),
                      "a live pid with matching start time is alive")

        // Same live pid, wrong start time = a recycled-pid identity → dead.
        let recycled = ProcessOwnership.OwnerIdentity(
            pid: spawned.pid, pgid: spawned.pid,
            startTimeTicks: spawned.identity.startTimeTicks &+ 999_999, kind: .devTurn)
        XCTAssertFalse(ProcessOwnership.isIdentityAlive(recycled),
                       "a mismatched start time (recycled pid) reads dead")
    }

    // MARK: - Helpers

    private func killLeader(_ pid: Int32) {
        _ = kill(-pid, SIGKILL)
        _ = kill(pid, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
    }
}
