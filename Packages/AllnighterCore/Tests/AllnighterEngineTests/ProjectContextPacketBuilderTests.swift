import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S02 Works Test: a packet is compact and source-labeled; it never hides a
/// failed proof, dirty tree, missing root, or blocked worker; worker readiness is
/// summarized; the packet has an id (receipt); and regenerating after a commit
/// reports the new git head.
final class ProjectContextPacketBuilderTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-pkt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @discardableResult
    private func initRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "v1".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir); runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private func project(at dir: URL) -> Project {
        let n = RootNormalization.normalize(dir.path)
        return Project(id: "prj_1", displayName: "Repo", localRootPath: n.displayPath,
                       normalizedRootPath: n.key, kind: .gitRepo, createdAt: Date(), lastOpenedAt: Date(),
                       docsEntrypoints: ["AGENTS.md"], proofCommands: ["swift test"], managerThreadId: "thr_mgr")
    }

    func testPacketIsSourceLabeledAndHidesNothing() throws {
        let repo = try initRepo()
        try "dirty".write(to: repo.appendingPathComponent("scratch.txt"), atomically: true, encoding: .utf8) // dirty tree
        let p = project(at: repo)
        let readiness = [
            ProjectWorkerReadiness(projectId: p.id, sourceId: "codex", workerId: "codex", status: .ready, checkedAt: Date(), probeKind: .silent),
            ProjectWorkerReadiness(projectId: p.id, sourceId: "grok", status: .authRequired, checkedAt: Date(), probeKind: .silent)
        ]
        let packet = ProjectContextPacketBuilder.build(
            project: p, workerReadiness: readiness,
            recentThreadSummaries: ["thr_1: where are we"],
            pendingItems: ["pend_1"], openProposals: ["prop_1"],
            lastProofResults: ["swift test: FAILED (2 failures)"])

        XCTAssertTrue(packet.id.hasPrefix("pkt_"))                       // receipt id
        XCTAssertEqual(packet.projectId, "prj_1")
        XCTAssertNotNil(packet.git.head)                                 // git observed
        XCTAssertNotNil(packet.git.dirtySummary)                        // dirty visible
        XCTAssertFalse(packet.git.recentCommits.isEmpty)
        XCTAssertEqual(packet.docs.entrypoints, ["AGENTS.md"])
        XCTAssertEqual(packet.proof.commands, ["swift test"])
        XCTAssertEqual(packet.workers.readyWorkerIds, ["codex"])
        XCTAssertEqual(packet.workers.blockedWorkerSummaries, ["grok: authRequired"])
        // Never hide: dirty tree, blocked worker, and failed proof all surface as warnings.
        XCTAssertTrue(packet.warnings.contains { $0.contains("dirty tree") })
        XCTAssertTrue(packet.warnings.contains { $0.contains("grok") })
        XCTAssertTrue(packet.warnings.contains { $0.lowercased().contains("fail") })
    }

    func testRegeneratingAfterCommitReportsNewHead() throws {
        let repo = try initRepo()
        let p = project(at: repo)
        let head1 = ProjectContextPacketBuilder.build(project: p).git.head
        // New commit changes HEAD.
        try "v2".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["commit", "-q", "-am", "c2"], cwd: repo)
        let head2 = ProjectContextPacketBuilder.build(project: p).git.head
        XCTAssertNotNil(head1); XCTAssertNotNil(head2)
        XCTAssertNotEqual(head1, head2)                                  // regeneration reflects current HEAD
    }

    func testMissingRootSurfacesAsWarning() throws {
        let repo = try initRepo()
        let p = project(at: repo)
        try FileManager.default.removeItem(at: repo)
        let packet = ProjectContextPacketBuilder.build(project: p)
        XCTAssertEqual(packet.root.rootState, .missing)
        XCTAssertTrue(packet.warnings.contains { $0.contains("root missing") })
    }

    func testPacketIsCompactlyCapped() {
        let n = RootNormalization.normalize(tmp.path)
        let p = Project(id: "prj_2", displayName: "X", localRootPath: n.displayPath, normalizedRootPath: n.key,
                        kind: .folder, createdAt: Date(), lastOpenedAt: Date())
        let many = (0..<50).map { "item\($0)" }
        let packet = ProjectContextPacketBuilder.build(project: p, pendingItems: many, maxList: 10)
        XCTAssertEqual(packet.work.pendingItems.count, 10)              // compact
    }
}
