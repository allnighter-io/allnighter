import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// LOOP-TWIN: each free twin must leave durable loop state byte-identical and
/// start no worker. Assert against the store itself — never against the dry-run
/// JSON's own claims.
final class LoopDryRunNoMutationTests: XCTestCase {
    private var tmp: URL!
    private var loopStore: LoopStateStore!
    private var runStore: RunStore!
    private var projectStore: ProjectStore!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-loop-dry-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        loopStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        projectStore = ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Durable snapshots (truth owners)

    /// Byte identity of every file under the loop folder (relay.json, owner.pid, …).
    private func snapshotLoopDir(id: String) throws -> [String: Data] {
        let dir = loopStore.rootDirectory.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [:] }
        var out: [String: Data] = [:]
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        for url in files {
            out[url.lastPathComponent] = try Data(contentsOf: url)
        }
        return out
    }

    private func snapshotRunStore() throws -> [String: Data] {
        let root = runStore.rootDirectory
        guard FileManager.default.fileExists(atPath: root.path) else { return [:] }
        var out: [String: Data] = [:]
        let entries = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )
        for entry in entries {
            if entry.hasDirectoryPath {
                let nested = try FileManager.default.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil
                )
                for f in nested {
                    out["\(entry.lastPathComponent)/\(f.lastPathComponent)"] = try Data(contentsOf: f)
                }
            } else {
                out[entry.lastPathComponent] = try Data(contentsOf: entry)
            }
        }
        return out
    }

    private func assertDurableUnchanged(
        loopId: String,
        beforeLoop: [String: Data],
        beforeRuns: [String: Data],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let afterLoop = try snapshotLoopDir(id: loopId)
        XCTAssertEqual(
            afterLoop, beforeLoop,
            "dry-run mutated durable loop files (rounds/status/occupant/updatedAt/owner)",
            file: file, line: line
        )
        let afterRuns = try snapshotRunStore()
        XCTAssertEqual(
            afterRuns, beforeRuns,
            "dry-run wrote a run (worker start) into the run store",
            file: file, line: line
        )
        // Loaded model fields must also match (catches silent re-encode drift).
        if let beforeData = beforeLoop["relay.json"],
           let afterData = afterLoop["relay.json"] {
            let before = try CoreJSON.decode(LoopState.self, from: beforeData)
            let after = try CoreJSON.decode(LoopState.self, from: afterData)
            XCTAssertEqual(before.status, after.status, file: file, line: line)
            XCTAssertEqual(before.pmModelId, after.pmModelId, file: file, line: line)
            XCTAssertEqual(before.devModelId, after.devModelId, file: file, line: line)
            XCTAssertEqual(before.rounds.count, after.rounds.count, file: file, line: line)
            XCTAssertEqual(before.finishedAt, after.finishedAt, file: file, line: line)
            XCTAssertEqual(before.createdAt, after.createdAt, file: file, line: line)
            XCTAssertEqual(before.note, after.note, file: file, line: line)
            XCTAssertEqual(before.founderNote, after.founderNote, file: file, line: line)
        }
    }

    private func seedProject(path: String = "repo") throws -> Project {
        let dir = tmp.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try projectStore.add(path: dir.path, name: nil)
    }

    // MARK: - loop resume --dry-run

    func testResumeDryRunDoesNotMutateDurableState() async throws {
        let project = try seedProject()
        let loopId = "loop_resume_dry"
        let state = LoopState(
            id: loopId,
            projectRoot: project.normalizedRootPath,
            docPath: "docs/spec.md",
            brief: nil,
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .escalated,
            rounds: [
                RelayRound(
                    roundNumber: 1,
                    baselineHead: "abc",
                    verdict: LoopVerdict(verdict: .escalate, handover: nil, note: "need answer"),
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    finishedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    outcome: .escalated
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "need answer"
        )
        try loopStore.save(state)

        let beforeLoop = try snapshotLoopDir(id: loopId)
        let beforeRuns = try snapshotRunStore()
        XCTAssertFalse(beforeLoop.isEmpty, "seed must write relay.json")

        let payload = await LoopEngineCLI.dryRunResume(
            opts: Options(["--relay", loopId, "--answer", "ship it", "--json"]),
            stateStore: loopStore,
            projectStore: projectStore
        )

        try assertDurableUnchanged(loopId: loopId, beforeLoop: beforeLoop, beforeRuns: beforeRuns)

        XCTAssertTrue(payload.ready, "escalated loop with answer should be ready; warnings=\(payload.warnings)")
        XCTAssertEqual(payload.brief, "ship it")
        XCTAssertEqual(payload.pm.occupant, "model_pm")
        XCTAssertEqual(payload.dev.occupant, "model_dev")
        XCTAssertEqual(payload.specPath, "docs/spec.md")
        XCTAssertTrue(payload.nextAction.command.contains("alln loop resume"))
        XCTAssertFalse(payload.nextAction.command.contains("--dry-run"))
        XCTAssertEqual(runStore.list().count, 0, "no worker run created")
    }

    func testResumeDryRunReportsIllegalStateWithoutMutating() async throws {
        let project = try seedProject("repo2")
        let loopId = "loop_resume_done"
        let state = LoopState(
            id: loopId,
            projectRoot: project.normalizedRootPath,
            docPath: nil,
            brief: "done work",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .done,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        try loopStore.save(state)
        let beforeLoop = try snapshotLoopDir(id: loopId)
        let beforeRuns = try snapshotRunStore()

        let payload = await LoopEngineCLI.dryRunResume(
            opts: Options(["--relay", loopId, "--answer", "too late"]),
            stateStore: loopStore,
            projectStore: projectStore
        )

        try assertDurableUnchanged(loopId: loopId, beforeLoop: beforeLoop, beforeRuns: beforeRuns)
        XCTAssertFalse(payload.ready)
        XCTAssertTrue(payload.warnings.contains { $0.contains("not resumable") }, "warnings=\(payload.warnings)")
    }

    // MARK: - loop step --dry-run

    func testStepDryRunDoesNotMutateDurableState() async throws {
        let project = try seedProject("repo_step")
        let loopId = "loop_step_dry"
        let state = LoopState(
            id: loopId,
            projectRoot: project.normalizedRootPath,
            docPath: nil,
            brief: "build the feature",
            pmModelId: LoopState.callerPMModelId,
            devModelId: "model_dev",
            status: .awaitingPM,
            rounds: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            pilotMaxRounds: 20
        )
        try loopStore.save(state)

        let beforeLoop = try snapshotLoopDir(id: loopId)
        let beforeRuns = try snapshotRunStore()

        let payload = await LoopCLI.dryRunStep(
            loopId: loopId,
            message: "implement the dry-run twins",
            doneSummary: nil,
            stateStore: loopStore,
            projectStore: projectStore
        )

        try assertDurableUnchanged(loopId: loopId, beforeLoop: beforeLoop, beforeRuns: beforeRuns)
        XCTAssertTrue(payload.ready, "awaitingPM + message should be ready; warnings=\(payload.warnings)")
        XCTAssertEqual(payload.brief, "implement the dry-run twins")
        XCTAssertEqual(payload.pm.occupant, "caller")
        XCTAssertEqual(payload.dev.occupant, "model_dev")
        XCTAssertTrue(payload.nextAction.command.hasPrefix("alln loop step"))
        XCTAssertEqual(runStore.list().count, 0)
    }

    func testStepDryRunIllegalStatusLeavesBytesIdentical() async throws {
        let project = try seedProject("repo_step2")
        let loopId = "loop_step_running"
        let state = LoopState(
            id: loopId,
            projectRoot: project.normalizedRootPath,
            docPath: "docs/x.md",
            pmModelId: LoopState.callerPMModelId,
            devModelId: "model_dev",
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try loopStore.save(state)
        let beforeLoop = try snapshotLoopDir(id: loopId)
        let beforeRuns = try snapshotRunStore()

        let payload = await LoopCLI.dryRunStep(
            loopId: loopId,
            message: "should not dispatch",
            doneSummary: nil,
            stateStore: loopStore,
            projectStore: projectStore
        )

        try assertDurableUnchanged(loopId: loopId, beforeLoop: beforeLoop, beforeRuns: beforeRuns)
        XCTAssertFalse(payload.ready)
        XCTAssertTrue(payload.warnings.contains { $0.contains("not awaiting") }, "warnings=\(payload.warnings)")
    }

    // MARK: - loop pm --dry-run

    func testPmCallerDryRunDoesNotMutateOccupantOrStatus() async throws {
        let project = try seedProject("repo_pm")
        let loopId = "loop_pm_caller_dry"
        let state = LoopState(
            id: loopId,
            projectRoot: project.normalizedRootPath,
            docPath: "docs/spec.md",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .escalated,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "open question"
        )
        try loopStore.save(state)
        let beforeLoop = try snapshotLoopDir(id: loopId)
        let beforeRuns = try snapshotRunStore()

        let models = [
            Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "cli", role: .both),
            Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "cli", role: .both),
        ]
        let payload = await LoopCLI.dryRunPm(
            loopId: loopId,
            occupant: "caller",
            opts: Options([]),
            models: models,
            stateStore: loopStore,
            projectStore: projectStore
        )

        try assertDurableUnchanged(loopId: loopId, beforeLoop: beforeLoop, beforeRuns: beforeRuns)
        // Critical: real `loop pm caller` would flip occupant + status; dry-run must not.
        let reloaded = try XCTUnwrap(loopStore.load(id: loopId))
        XCTAssertEqual(reloaded.pmModelId, "model_pm")
        XCTAssertEqual(reloaded.status, .escalated)
        XCTAssertTrue(payload.ready, "warnings=\(payload.warnings)")
        XCTAssertEqual(payload.pm.occupant, "caller")
        XCTAssertEqual(runStore.list().count, 0)
    }

    func testPmAgentDryRunDoesNotMutateOrDispatch() async throws {
        let project = try seedProject("repo_pm2")
        let loopId = "loop_pm_agent_dry"
        let state = LoopState(
            id: loopId,
            projectRoot: project.normalizedRootPath,
            docPath: nil,
            brief: "pilot work",
            pmModelId: LoopState.callerPMModelId,
            devModelId: "model_dev",
            status: .awaitingPM,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try loopStore.save(state)
        let beforeLoop = try snapshotLoopDir(id: loopId)
        let beforeRuns = try snapshotRunStore()

        let models = [
            Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "cli", role: .both),
            Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "cli", role: .both),
        ]
        let payload = await LoopCLI.dryRunPm(
            loopId: loopId,
            occupant: "model_pm",
            opts: Options([]),
            models: models,
            stateStore: loopStore,
            projectStore: projectStore
        )

        try assertDurableUnchanged(loopId: loopId, beforeLoop: beforeLoop, beforeRuns: beforeRuns)
        let reloaded = try XCTUnwrap(loopStore.load(id: loopId))
        XCTAssertEqual(reloaded.pmModelId, LoopState.callerPMModelId)
        XCTAssertEqual(reloaded.status, .awaitingPM)
        XCTAssertTrue(payload.ready, "warnings=\(payload.warnings)")
        XCTAssertEqual(payload.pm.occupant, "model_pm")
        XCTAssertEqual(payload.dev.occupant, "model_dev")
        XCTAssertEqual(runStore.list().count, 0)
    }

    // MARK: - Registry free twins + mutual exclusion

    func testSpendingLoopVerbsDeclareRealDryRunTwins() {
        let registry = ContractRegistry.milestone1
        let cases: [(name: String, twin: String)] = [
            ("loop resume", "alln loop resume <loop-id> --answer <text> --dry-run"),
            ("loop step", "alln loop step <loop-id> <message> --dry-run"),
            ("loop pm", "alln loop pm <loop-id> <occupant> --dry-run"),
        ]
        for item in cases {
            let spec = registry.commands.first { $0.name == item.name && $0.milestone == .m1 }
            XCTAssertNotNil(spec, item.name)
            XCTAssertEqual(spec?.freeTwinCommand, item.twin, item.name)
            XCTAssertTrue(spec?.spendsQuota == true, item.name)
            XCTAssertTrue(spec?.flags.contains { $0.name == "dry-run" } == true, item.name)
            XCTAssertEqual(
                ContractRegistry.resolveCommandName(from: item.twin),
                item.name,
                "twin must resolve to registered command"
            )
        }
    }

    func testDryRunMutuallyExclusiveWithDispatchFlags() {
        let registry = ContractRegistry.milestone1
        for name in ["loop resume", "loop pm"] {
            let spec = registry.commands.first { $0.name == name && $0.milestone == .m1 }
            let groups = Set(spec?.mutuallyExclusiveFlags.map { Set($0) } ?? [])
            XCTAssertTrue(groups.contains(["no-wait", "dry-run"]), "\(name) dry-run vs no-wait")
            XCTAssertTrue(groups.contains(["delivery", "dry-run"]), "\(name) dry-run vs delivery")
        }
    }
}
