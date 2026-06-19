import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S01 ProjectStore Works Tests: add/list/archive, duplicate-root detection
/// by the normalization key, observed git metadata vs folder kind, observed
/// rootState (missing blocks mutating runs), and cross-instance persistence.
final class ProjectStoreTests: XCTestCase {
    private var tmp: URL!
    private var store: ProjectStore!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-prjstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = ProjectStore(rootDirectory: tmp.appendingPathComponent("store"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures

    @discardableResult
    private func makeGitRepo(_ name: String, withRemote: Bool = false) throws -> URL {
        let dir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        runGit(["init", "-q"], cwd: dir)
        runGit(["config", "user.email", "t@t.dev"], cwd: dir)
        runGit(["config", "user.name", "Test"], cwd: dir)
        runGit(["config", "commit.gpgsign", "false"], cwd: dir)
        try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "init"], cwd: dir)
        if withRemote { runGit(["remote", "add", "origin", "https://example.com/x.git"], cwd: dir) }
        return dir
    }

    private func makeFolder(_ name: String) throws -> URL {
        let dir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - Tests

    func testAddObservesGitFolderAndDedupes() throws {
        let repoA = try makeGitRepo("repoA", withRemote: true)
        let repoB = try makeGitRepo("repoB")
        let folderC = try makeFolder("folderC")

        let a = try store.add(path: repoA.path)
        let b = try store.add(path: repoB.path)
        let c = try store.add(path: folderC.path)

        XCTAssertEqual(try store.activeProjects().count, 3)
        XCTAssertTrue(a.id.hasPrefix("prj_"))

        // Git observed (branch/head present after a commit; remote when configured).
        XCTAssertEqual(a.kind, .gitRepo)
        XCTAssertNotNil(a.gitBranch)
        XCTAssertNotNil(a.gitHead)
        XCTAssertEqual(a.gitRemoteURL, "https://example.com/x.git")
        XCTAssertEqual(b.kind, .gitRepo)
        XCTAssertNil(b.gitRemoteURL)            // no remote configured
        XCTAssertEqual(c.kind, .folder)         // plain folder
        XCTAssertNil(c.gitHead)

        // Duplicate detection by normalized root key — exact and non-normalized variant.
        XCTAssertEqual(try store.add(path: repoA.path).id, a.id)
        XCTAssertEqual(try store.add(path: repoA.path + "/.").id, a.id)
        XCTAssertEqual(try store.activeProjects().count, 3)   // still 3
    }

    func testMissingRootChangesStateAndBlocksMutatingRun() throws {
        let repo = try makeGitRepo("repoX")
        let p = try store.add(path: repo.path)
        XCTAssertEqual(p.rootState, .available)
        XCTAssertTrue(p.allowsMutatingRun)

        try FileManager.default.removeItem(at: repo)
        let refreshed = try XCTUnwrap(store.refreshObservation(id: p.id))
        XCTAssertEqual(refreshed.rootState, .missing)
        XCTAssertFalse(refreshed.allowsMutatingRun)
    }

    func testArchiveHidesFromActiveButKeepsRecord() throws {
        let repo = try makeGitRepo("repoArc")
        let p = try store.add(path: repo.path)
        _ = try store.archive(id: p.id)

        XCTAssertEqual(try store.activeProjects().count, 0)   // hidden from active rail
        XCTAssertEqual(try store.list().count, 1)             // record kept, not deleted
        XCTAssertEqual(try store.load(id: p.id)?.archived, true)

        // Dedup only applies to active Projects, so re-adding the same path while
        // the old one is archived starts a fresh active Project.
        let p2 = try store.add(path: repo.path)
        XCTAssertNotEqual(p2.id, p.id)
        XCTAssertEqual(try store.activeProjects().count, 1)
    }

    func testGetResolvesByIdThenUnambiguousName() throws {
        let repo = try makeGitRepo("repoN")
        let p = try store.add(path: repo.path, name: "My Project")
        XCTAssertEqual(try store.get(p.id)?.id, p.id)
        XCTAssertEqual(try store.get("My Project")?.id, p.id)
        XCTAssertNil(try store.get("nope"))
    }

    func testPersistsAcrossStoreInstances() throws {
        let repo = try makeGitRepo("repoP")
        let p = try store.add(path: repo.path)
        let reopened = ProjectStore(rootDirectory: store.rootDirectory)
        XCTAssertEqual(try reopened.load(id: p.id)?.id, p.id)
        XCTAssertEqual(try reopened.activeProjects().count, 1)
    }
}
