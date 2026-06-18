import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S06 Works Test (Engine layer): worker/proof/attachment roots derive from
/// the selected Project root; dirty files in another Project do not block this
/// one; dirty files overlapping the proposal scope block until acknowledged; a
/// missing root means no mutating dispatch. Real git repos, read-only observation.
final class ProjectExecutionResolverTests: XCTestCase {
    private var tmp: URL!
    private var store: ProjectStore!
    private let resolver = ProjectExecutionResolver()
    private let git = GitObserver()

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-projexec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
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

    private func writeFile(_ rel: String, in repo: URL, _ contents: String = "y") throws {
        let url = repo.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testRootsDeriveFromProjectRoot() throws {
        let repoA = try makeGitRepo("repoA")
        let pA = try store.add(path: repoA.path)

        let scope = resolver.resolve(project: pA)
        XCTAssertEqual(scope.rootState, .available)
        XCTAssertTrue(scope.isMutatingDispatchAllowed)
        XCTAssertEqual(scope.workerCwd, pA.localRootPath)
        XCTAssertEqual(scope.proofCwd, pA.localRootPath)
        XCTAssertEqual(scope.attachmentMirrorRoot, pA.localRootPath)
    }

    func testDirtInOtherProjectDoesNotBlock() throws {
        let repoA = try makeGitRepo("repoA")
        let repoB = try makeGitRepo("repoB")
        let pA = try store.add(path: repoA.path)
        _ = try store.add(path: repoB.path)

        try writeFile("src/Engine/Run.swift", in: repoB)   // repoB is dirty inside a "src/Engine" path

        // Project A asks about the same-looking scope; repoB dirt is irrelevant to A.
        let g = resolver.dispatchGate(project: pA, likelyFilesOrAreas: ["src/Engine/"])
        XCTAssertEqual(g, .allowed(warnings: []))
        XCTAssertEqual(git.dirtyFiles(rootPath: repoA.path), [])   // A really is clean
    }

    func testScopeOverlapBlocksUntilAcknowledged() throws {
        let repoA = try makeGitRepo("repoA")
        let pA = try store.add(path: repoA.path)
        try writeFile("src/Engine/Run.swift", in: repoA)   // untracked, overlaps scope
        try writeFile("docs/Notes.md", in: repoA)          // untracked, outside scope

        let blocked = resolver.dispatchGate(project: pA, likelyFilesOrAreas: ["src/Engine/"])
        guard case let .blockedDirtyScopeOverlap(files) = blocked else {
            return XCTFail("expected overlap block, got \(blocked)")
        }
        XCTAssertEqual(files, ["src/Engine/Run.swift"])

        let acked = resolver.dispatchGate(project: pA, likelyFilesOrAreas: ["src/Engine/"], dirtyAcknowledged: true)
        XCTAssertTrue(acked.allowsDispatch)
    }

    func testMissingRootBlocksDispatch() throws {
        let repoA = try makeGitRepo("repoA")
        let pA = try store.add(path: repoA.path)
        try FileManager.default.removeItem(at: repoA)   // root disappears after registration

        let scope = resolver.resolve(project: pA)
        XCTAssertEqual(scope.rootState, .missing)
        XCTAssertFalse(scope.isMutatingDispatchAllowed)
        XCTAssertNil(scope.workerCwd)
        XCTAssertEqual(resolver.dispatchGate(project: pA, likelyFilesOrAreas: []), .blockedNoProjectRoot)
    }

    func testDirtyFilesAreRootRelative() throws {
        let repoA = try makeGitRepo("repoA")
        try writeFile("a/b.txt", in: repoA)
        try "changed".write(to: repoA.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let dirty = Set(git.dirtyFiles(rootPath: repoA.path))
        XCTAssertTrue(dirty.contains("a/b.txt"))
        XCTAssertTrue(dirty.contains("README.md"))
        XCTAssertFalse(dirty.contains(where: { $0.hasPrefix("/") }))   // root-relative, not absolute
    }
}
