import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S04 Works Test: Pending items backfill `projectId` — from a bound thread
/// first (after PRJ-S03), else from the working-dir receipt via ProjectBinding,
/// else left Unassigned (blocked from running). Idempotent.
final class PendingProjectMigratorTests: XCTestCase {
    private var tmp: URL!
    private var pendingStore: PendingStore!
    private var threadStore: ThreadStore!
    private var projectStore: ProjectStore!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-pendmig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        pendingStore = PendingStore(rootDirectory: tmp.appendingPathComponent("pending"))
        threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        projectStore = ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
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
    private func makeGitRepo(_ name: String) throws -> URL {
        let dir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "x".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir); runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    @discardableResult
    private func seedPending(_ id: String, threadId: String? = nil, workingDir: String? = nil) throws -> PendingItem {
        let item = PendingItem(
            id: id, threadId: threadId, title: id, kind: .workerChat, status: .pending,
            createdAt: Date(), updatedAt: Date(), prompt: "do \(id)",
            target: PendingTarget(workerIds: ["claude"]), policy: PendingPolicy(),
            safety: PendingSafety(workingDir: workingDir))
        try pendingStore.save(item)
        return item
    }

    func testMigratesViaThreadThenWorkingDirElseUnassigned() throws {
        let repoA = try makeGitRepo("repoA")
        let repoB = try makeGitRepo("repoB")

        // A thread already bound to a Project (as PRJ-S03 would leave it).
        let pA = try projectStore.add(path: repoA.path)
        _ = try threadStore.create(id: "th1", title: "T", now: Date(), workingDir: repoA.path)
        _ = try threadStore.bindProject(threadId: "th1", projectId: pA.id, localRootPathSnapshot: repoA.path)

        _ = try seedPending("p1", threadId: "th1")                 // inherits thread's Project
        _ = try seedPending("p2", workingDir: repoB.path)          // resolves via working-dir -> new Project
        _ = try seedPending("p3", workingDir: nil)                 // no root -> Unassigned

        let report = try PendingProjectMigrator.migrate(pendingStore: pendingStore, threadStore: threadStore, projectStore: projectStore)

        XCTAssertEqual(report.bound, 2)            // p1 (thread), p2 (workingDir)
        XCTAssertEqual(report.unassigned, 1)       // p3
        XCTAssertEqual(report.createdProjects, 1)  // repoB (repoA already existed)

        XCTAssertEqual(try pendingStore.load(id: "p1")?.projectId, pA.id)
        XCTAssertNotNil(try pendingStore.load(id: "p2")?.projectId)
        XCTAssertFalse(try XCTUnwrap(pendingStore.load(id: "p3")).isProjectAssigned)   // blocked from running
    }

    func testIdempotent() throws {
        let repo = try makeGitRepo("repo")
        _ = try seedPending("p1", workingDir: repo.path)
        let r1 = try PendingProjectMigrator.migrate(pendingStore: pendingStore, threadStore: threadStore, projectStore: projectStore)
        XCTAssertEqual(r1.bound, 1)
        let r2 = try PendingProjectMigrator.migrate(pendingStore: pendingStore, threadStore: threadStore, projectStore: projectStore)
        XCTAssertEqual(r2.bound, 0)
        XCTAssertEqual(r2.alreadyBound, 1)
        XCTAssertEqual(r2.createdProjects, 0)
    }
}
