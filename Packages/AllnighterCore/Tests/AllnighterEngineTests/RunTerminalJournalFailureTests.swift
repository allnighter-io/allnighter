import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S02: the authoritative terminal result persistence is never swallowed. When
/// the run journal cannot be written at terminal settlement, the run fails visibly
/// with the stable RUN_JOURNAL_UNAVAILABLE code — it does not report success over a
/// lost journal.
final class RunTerminalJournalFailureTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-journal-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// A RunStore whose root is a regular FILE — every `createDirectory` under it
    /// throws, so a save can never succeed.
    private func unwritableRunStore() throws -> RunStore {
        let blocked = tmp.appendingPathComponent("runs-is-a-file")
        try "not a directory".write(to: blocked, atomically: true, encoding: .utf8)
        return RunStore(rootDirectory: blocked)
    }

    func testTerminalResearchJournalFailureSurfacesRunJournalUnavailable() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let team = TeamPreset(
            id: "research_journal", displayName: "Research", lane: .code, outputKind: .plan,
            mutating: false,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer",
                                         purpose: .answer, preferredModelId: "model_opus")],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        let service = RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            teams: [team],
            runStore: try unwritableRunStore(),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "# Answer\nok", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .flagship, allowHealthySubstitutions: true,
                                     tiers: TierMembership(flagship: ["model_opus"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })

        let result = await service.run(
            RunRequest(message: "research only", repoRoot: repo.path, presetId: "research_journal"),
            origin: .cli, runId: "journal-fail")

        guard case .failure(let error) = result else {
            return XCTFail("a lost terminal journal must surface as failure, got: \(result)")
        }
        XCTAssertEqual(error.code, "RUN_JOURNAL_UNAVAILABLE")
    }

    /// Symmetric mutating-team coverage for the authoritative terminal write in
    /// `RunService.runExecution` (RunService.swift:1809-1813). A `mutating == true`
    /// team resolves to one worker, executes, and reaches the terminal
    /// `try runStore.save(run, ...)`; when that save cannot be written the run must
    /// fail visibly with RUN_JOURNAL_UNAVAILABLE — it must not report success over a
    /// lost journal, exactly like the research path above (CR-S02 audit follow-up).
    func testTerminalExecutionJournalFailureSurfacesRunJournalUnavailable() async throws {
        let repo = tmp.appendingPathComponent("exec-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let team = TeamPreset(
            id: "execution_journal", displayName: "Execution", lane: .code, outputKind: .plan,
            mutating: true, executionSourceId: "claude_code",
            workerSpecs: [TeamWorkerSpec(id: "e1", skillId: "first_principles_builder",
                                         purpose: .answer, preferredModelId: "model_opus")],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        let service = RunService(
            models: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                           driverId: "claude_code", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            teams: [team],
            runStore: try unwritableRunStore(),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "# Done\nedited", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .flagship, allowHealthySubstitutions: true,
                                     tiers: TierMembership(flagship: ["model_opus"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })

        let result = await service.run(
            RunRequest(message: "make the edit", repoRoot: repo.path, presetId: "execution_journal"),
            origin: .cli, runId: "exec-journal-fail")

        guard case .failure(let error) = result else {
            return XCTFail("a lost terminal journal must surface as failure on the execution path, got: \(result)")
        }
        XCTAssertEqual(error.code, "RUN_JOURNAL_UNAVAILABLE")
    }
}
