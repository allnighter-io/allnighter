import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// FR6 — bare mutating `alln run` dispatch carries the provenance trailer ask once.
final class RunProvenanceTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-provenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @discardableResult
    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    func testBareMutatingRunDispatchIncludesCommitTrailerAskExactlyOnce() async throws {
        let repo = try makeGitRepo()
        let capture = PromptCapturingCommandRunner()
        let model = Model(
            id: "model_grok", displayName: "Grok Build", modelLabel: "grok-build",
            driverId: "grok", role: .both)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: capture,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .flagship, allowHealthySubstitutions: true,
                    tiers: TierMembership(flagship: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )
        let result = await service.run(
            RunRequest(
                message: "Make a small change",
                repoRoot: repo.path,
                presetId: "build_slice",
                workerId: "model_grok",
                lane: .code),
            origin: .cli, runId: "bare-run-trailer")
        guard case .success = result else { return XCTFail("bare mutating run failed: \(result)") }
        let prompt = try XCTUnwrap(capture.lastPrompt())
        let trailer = ProvenanceConvention.commitTrailerAsk(displayName: "Grok Build")
        XCTAssertTrue(prompt.contains(trailer), "RunService.runExecution must append the trailer ask for bare mutating runs")
        XCTAssertEqual(prompt.components(separatedBy: trailer).count - 1, 1)
    }
}
