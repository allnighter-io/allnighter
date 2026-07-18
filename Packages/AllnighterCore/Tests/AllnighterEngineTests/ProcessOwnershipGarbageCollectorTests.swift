import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ProcessOwnershipGarbageCollectorTests: XCTestCase {
    private struct Tree {
        var root: URL
        var runs: RunStore
        var relays: RelayStateStore
        var threads: ThreadStore

        var collector: ProcessOwnershipGarbageCollector {
            ProcessOwnershipGarbageCollector(
                runStore: runs,
                relayStore: relays,
                threadStore: threads,
                retentionCount: 0
            )
        }
    }

    private func tree() throws -> Tree {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ownership-gc-\(UUID().uuidString)", isDirectory: true)
        let runsRoot = root.appendingPathComponent("Runs", isDirectory: true)
        let relaysRoot = root.appendingPathComponent("Relays", isDirectory: true)
        let threadsRoot = root.appendingPathComponent("Threads", isDirectory: true)
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relaysRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: threadsRoot, withIntermediateDirectories: true)
        return Tree(
            root: root,
            runs: RunStore(rootDirectory: runsRoot),
            relays: RelayStateStore(rootDirectory: relaysRoot),
            threads: ThreadStore(rootDirectory: threadsRoot)
        )
    }

    private func run(id: String, status: RunStatus, createdAt: Date) -> TeamRun {
        TeamRun(id: id, prompt: "test", status: status, createdAt: createdAt)
    }

    private func exists(_ runId: String, in store: RunStore) -> Bool {
        FileManager.default.fileExists(
            atPath: store.rootDirectory.appendingPathComponent("run_\(runId)").path
        )
    }

    func testOldTerminalDeadRunIsPruned() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        try tree.runs.save(run(id: "old", status: .complete, createdAt: .distantPast), models: [])

        let result = tree.collector.collect()

        XCTAssertEqual(result.pruned.map(\.id), ["old"])
        XCTAssertFalse(exists("old", in: tree.runs))
    }

    func testIdentityAliveTerminalRunIsNeverPruned() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        try tree.runs.save(run(id: "alive", status: .complete, createdAt: .distantPast), models: [])
        let directory = try tree.runs.runDirectory(forRunId: "alive")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .detachedRunner))
        try ProcessOwnership.writeOwnerIdentity(identity, in: directory)

        let result = tree.collector.collect()

        XCTAssertEqual(result.keptAlive.map(\.id), ["alive"])
        XCTAssertTrue(exists("alive", in: tree.runs))
    }

    func testNonTerminalDeadRunIsNeverPruned() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        try tree.runs.save(run(id: "running", status: .fanningOut, createdAt: .distantPast), models: [])
        let directory = try tree.runs.runDirectory(forRunId: "running")
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_100_901, pgid: 9_901, startTimeTicks: 1, kind: .detachedRunner),
            in: directory
        )

        let result = tree.collector.collect()

        XCTAssertEqual(result.keptNonTerminal.map(\.id), ["running"])
        XCTAssertTrue(exists("running", in: tree.runs))
    }

    func testNewestTerminalRunIsKeptWithinRetention() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let old = Date(timeIntervalSince1970: 1)
        let recent = Date(timeIntervalSince1970: 2)
        try tree.runs.save(run(id: "old", status: .failed, createdAt: old), models: [])
        try tree.runs.save(run(id: "recent", status: .complete, createdAt: recent), models: [])
        let collector = ProcessOwnershipGarbageCollector(
            runStore: tree.runs,
            relayStore: tree.relays,
            threadStore: tree.threads,
            retentionCount: 1
        )

        let result = collector.collect()

        XCTAssertEqual(result.pruned.map(\.id), ["old"])
        XCTAssertEqual(result.keptWithinRetention.map(\.id), ["recent"])
        XCTAssertTrue(exists("recent", in: tree.runs))
    }

    func testThreadReferencedTerminalRunKeepsDurableRunTruth() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        try tree.runs.save(run(id: "threaded", status: .complete, createdAt: .distantPast), models: [])
        try tree.runs.save(run(id: "artifact-threaded", status: .complete, createdAt: .distantPast), models: [])
        var linkedRun = run(id: "linked", status: .complete, createdAt: .distantPast)
        linkedRun.threadId = "thread-1"
        try tree.runs.save(linkedRun, models: [])
        let now = Date()
        let directTurn = ThreadTurn(
            id: "turn-1",
            threadId: "thread-1",
            kind: .teamRun,
            status: .done,
            createdAt: now,
            author: .worker,
            runId: "threaded"
        )
        let artifactTurn = ThreadTurn(
            id: "turn-2",
            threadId: "thread-1",
            kind: .userDecision,
            status: .done,
            createdAt: now,
            author: .user,
            artifactRefs: [.init(kind: .plan, runId: "artifact-threaded")]
        )
        try tree.threads.saveForImport(WorkThread(
            id: "thread-1",
            title: "Referenced run",
            createdAt: now,
            updatedAt: now,
            turns: [directTurn, artifactTurn]
        ))

        let result = tree.collector.collect()

        XCTAssertEqual(
            result.keptThreadReferenced.map(\.id),
            ["artifact-threaded", "linked", "threaded"]
        )
        XCTAssertNotNil(tree.runs.loadRaw(runId: "threaded"))
        XCTAssertNotNil(tree.runs.loadRaw(runId: "artifact-threaded"))
        XCTAssertNotNil(tree.runs.loadRaw(runId: "linked"))
    }

    func testTerminalRelayPrunesButResumableRelayStaysNonTerminal() throws {
        let tree = try tree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let done = RelayState(
            id: "relay-done",
            projectRoot: "/repo",
            docPath: "docs/spec.md",
            pmWorkerId: "pm",
            devWorkerId: "dev",
            status: .done,
            createdAt: .distantPast
        )
        let escalated = RelayState(
            id: "relay-escalated",
            projectRoot: "/repo",
            docPath: "docs/spec.md",
            pmWorkerId: "pm",
            devWorkerId: "dev",
            status: .escalated,
            createdAt: .distantPast
        )
        try tree.relays.save(done)
        try tree.relays.save(escalated)

        let result = tree.collector.collect()

        XCTAssertEqual(result.pruned.map(\.id), ["relay-done"])
        XCTAssertEqual(result.keptNonTerminal.map(\.id), ["relay-escalated"])
        XCTAssertNil(tree.relays.load(id: "relay-done"))
        XCTAssertNotNil(tree.relays.load(id: "relay-escalated"))
    }
}
