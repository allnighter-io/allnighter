import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S02 proof wall: the registered canonical repository root is the one truth —
/// resolved root == worker CWD == reported root == registered root — and no
/// alternate-root field exists in the request/result schema.
final class CanonicalRepoRootInvariantTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-canon-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    /// Records the working directory every spawn is handed.
    private final class CWDRecorder: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var dirs: [String?] = []
        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            record(workingDirectory)
            return CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        }
        private func record(_ dir: String?) { lock.lock(); dirs.append(dir); lock.unlock() }
        func recorded() -> [String?] { lock.lock(); defer { lock.unlock() }; return dirs }
    }

    private func makeService(recorder: CWDRecorder) -> RunService {
        RunService(
            models: [Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                           driverId: "grok", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: recorder,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    func testWorkerCWDAndReportedRootEqualRegisteredRoot() async throws {
        // A registered root spelled non-canonically (trailing slash) must still
        // resolve, spawn, and report the ONE normalized canonical root.
        let registered = tmp.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: registered, withIntermediateDirectories: true)
        let canonical = RunWriteLock.normalize(registered.path) ?? registered.path

        let recorder = CWDRecorder()
        let result = await makeService(recorder: recorder).run(
            RunRequest(message: "do work", repoRoot: registered.path + "/", workerId: "model_grok"),
            origin: .cli, runId: "canon-root")

        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }

        // Agent CWD == canonical registered root.
        let cwds = recorder.recorded().compactMap { $0 }
        XCTAssertFalse(cwds.isEmpty, "the worker must have spawned")
        for cwd in cwds {
            XCTAssertEqual(RunWriteLock.normalize(cwd), canonical,
                           "every worker spawns with cwd == the canonical registered root")
        }
        // Reported root == canonical registered root.
        XCTAssertEqual(RunWriteLock.normalize(run.repoRoot ?? ""), canonical)
    }

    /// The request/result schema exposes exactly one canonical root field (`repoRoot`)
    /// and none of the forbidden alternate-root spellings.
    func testNoAlternateRootFieldInRequestOrResultSchema() {
        let forbidden: Set<String> = [
            "projectMirrorRoot", "alternateRepositoryRoot", "isolatedProjectRoot",
            "projectCloneRoot", "mirrorRoot", "cloneRoot",
        ]
        let requestLabels = Set(Mirror(reflecting:
            RunRequest(message: "m", repoRoot: "/tmp/x")).children.compactMap { $0.label })
        XCTAssertTrue(requestLabels.contains("repoRoot"), "RunRequest must carry the canonical repoRoot")
        XCTAssertTrue(requestLabels.isDisjoint(with: forbidden),
                      "RunRequest must not carry any alternate-root field: \(requestLabels.intersection(forbidden))")

        let run = TeamRun(id: "r", prompt: "p", status: .complete, createdAt: Date(),
                          mutating: false, repoRoot: "/tmp/x")
        let runLabels = Set(Mirror(reflecting: run).children.compactMap { $0.label })
        XCTAssertTrue(runLabels.contains("repoRoot"))
        XCTAssertTrue(runLabels.isDisjoint(with: forbidden),
                      "TeamRun must not carry any alternate-root field: \(runLabels.intersection(forbidden))")
    }
}
