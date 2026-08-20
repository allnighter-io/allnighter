import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class StuckRunDisclosureLiveTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stuck-landed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "one".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    func testLiveShowRecommendsKillWhenSilentHolderLandedCommits() throws {
        let repo = try makeGitRepo()
        let baseline = try XCTUnwrap(GitObserver().observe(rootPath: repo.path).head)
        try "two".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: repo)
        runGit(["commit", "-q", "-m", "landed"], cwd: repo)

        let now = Date()
        let silent = now.addingTimeInterval(
            -(StreamLiveness.waitHintSeconds * StreamLiveness.warningMultiplier + 5))
        let runs = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        var holder = TeamRun(
            id: "holder", prompt: "do work", status: .running, phase: .working,
            createdAt: silent, mutating: true, repoRoot: repo.path, lastActivityAt: silent
        )
        holder.baselineHead = baseline
        try runs.save(holder, models: [])

        var waiter = TeamRun(
            id: "waiter", prompt: "next", status: .queued, phase: .waitingForWriteLock,
            createdAt: now, mutating: true, repoRoot: repo.path
        )
        waiter.blocker = RunBlocker(
            resource: .repoWriteLock, scopeRoot: repo.path, holderId: "holder", holderKind: "run"
        )
        try runs.save(waiter, models: [])

        let holderHit = try XCTUnwrap(
            StuckRunDisclosureLive.evaluate(run: holder, store: runs, now: now))
        XCTAssertEqual(holderHit.stopRunId, "holder")
        XCTAssertEqual(holderHit.repoActivity.attribution, "notProven")

        let waiterHit = try XCTUnwrap(
            StuckRunDisclosureLive.evaluate(run: waiter, store: runs, now: now))
        XCTAssertEqual(waiterHit.stopRunId, "holder")
        XCTAssertNotEqual(waiterHit.stopRunId, "waiter")
    }
}
