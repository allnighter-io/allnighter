import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S03 Works Test: legacy threads with `workingDir` migrate to Projects via
/// the deterministic binding rule — repo roots get a Project (subdirs of the same
/// repo bind to it, not a new one), the old path is preserved as a receipt, and
/// threads with no reliable root are left Unassigned (blocked from runs).
/// Migration is idempotent.
final class ThreadProjectMigratorTests: XCTestCase {
    private var tmp: URL!
    private var threadStore: ThreadStore!
    private var projectStore: ProjectStore!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-thmig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
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

    func testMigratesToRepoRootsAndLeavesAmbiguousUnassigned() throws {
        let repoA = try makeGitRepo("repoA")
        let repoB = try makeGitRepo("repoB")
        let subA = repoA.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)
        let folderC = tmp.appendingPathComponent("folderC")
        try FileManager.default.createDirectory(at: folderC, withIntermediateDirectories: true)

        _ = try threadStore.create(id: "t1", title: "T1", now: Date(), workingDir: repoA.path)
        _ = try threadStore.create(id: "t2", title: "T2", now: Date(), workingDir: subA.path)    // subdir of repoA
        _ = try threadStore.create(id: "t3", title: "T3", now: Date(), workingDir: repoB.path)
        _ = try threadStore.create(id: "t4", title: "T4", now: Date(), workingDir: folderC.path) // non-repo
        _ = try threadStore.create(id: "t5", title: "T5", now: Date(), workingDir: nil)           // no root

        let report = try ThreadProjectMigrator.migrate(threadStore: threadStore, projectStore: projectStore)

        XCTAssertEqual(report.createdProjects, 2)   // repoA + repoB (subdir reuses repoA)
        XCTAssertEqual(report.bound, 3)             // t1, t2, t3
        XCTAssertEqual(report.unassigned, 2)        // t4 (folder), t5 (no root)

        let t1 = try XCTUnwrap(threadStore.get("t1"))
        let t2 = try XCTUnwrap(threadStore.get("t2"))
        XCTAssertNotNil(t1.projectId)
        XCTAssertEqual(t1.projectId, t2.projectId)              // same repo → same Project
        XCTAssertEqual(t1.localRootPathSnapshot, repoA.path)    // receipt preserved
        XCTAssertFalse(try XCTUnwrap(threadStore.get("t4")).isProjectAssigned)
        XCTAssertFalse(try XCTUnwrap(threadStore.get("t5")).isProjectAssigned)
        XCTAssertEqual(try projectStore.activeProjects().count, 2)
    }

    func testMigrationIsIdempotent() throws {
        let repo = try makeGitRepo("repo")
        _ = try threadStore.create(id: "t1", title: "T", now: Date(), workingDir: repo.path)

        let r1 = try ThreadProjectMigrator.migrate(threadStore: threadStore, projectStore: projectStore)
        XCTAssertEqual(r1.bound, 1)
        XCTAssertEqual(r1.createdProjects, 1)

        let r2 = try ThreadProjectMigrator.migrate(threadStore: threadStore, projectStore: projectStore)
        XCTAssertEqual(r2.bound, 0)
        XCTAssertEqual(r2.alreadyBound, 1)
        XCTAssertEqual(r2.createdProjects, 0)       // no duplicate Project
        XCTAssertEqual(try projectStore.activeProjects().count, 1)
    }
}
