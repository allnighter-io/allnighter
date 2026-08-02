import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RunPMTurnTests: XCTestCase {
    private var root: URL!
    private var runStore: RunStore!
    private var pmTurnStore: PMTurnStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-pm-turn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runStore = RunStore(rootDirectory: root.appendingPathComponent("Runs", isDirectory: true))
        pmTurnStore = PMTurnStore(runsRootDirectory: runStore.rootDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        runStore = nil
        pmTurnStore = nil
    }

    func testTerminalExecutionWritesPMTurnBeforeTerminalRunState() async throws {
        let service = makeExecutionService()
        let result = await service.run(
            RunRequest(message: "make the change", repoRoot: root.path, presetId: "execution_pm_turn"),
            origin: .cli,
            runId: "run-terminal"
        )

        guard case .success(let run) = result else {
            return XCTFail("terminal run failed: \(result)")
        }
        XCTAssertEqual(run.status.lifecycle, .done)

        let turn = try XCTUnwrap(try pmTurnStore.load(kind: .run, subjectId: run.id))
        XCTAssertEqual(turn.sequence, 1)
        XCTAssertEqual(turn.reason, "done")
        XCTAssertEqual(turn.lifecycleStatus, "done")
        XCTAssertEqual(turn.report, "# Delivered\nThe change is complete.")
        XCTAssertEqual(turn.nextCommands, [
            "alln show run-terminal --json",
        ])
        XCTAssertEqual(turn.notes, [])
        XCTAssertTrue(try XCTUnwrap(runStore.loadRaw(runId: run.id)).status.isTerminal)
    }

    func testTerminalRunDoesNotPublishTerminalStateWhenPMTurnWriteFails() async throws {
        let blockedRoot = root.appendingPathComponent("pm-turn-root-is-a-file")
        try "not a directory".write(to: blockedRoot, atomically: true, encoding: .utf8)
        let service = makeExecutionService(
            pmTurnStore: PMTurnStore(runsRootDirectory: blockedRoot)
        )

        let result = await service.run(
            RunRequest(message: "make the change", repoRoot: root.path, presetId: "execution_pm_turn"),
            origin: .cli,
            runId: "run-pm-turn-failure"
        )

        guard case .failure(let error) = result else {
            return XCTFail("PM turn storage failure must fail the terminal boundary")
        }
        XCTAssertEqual(error.code, "RUN_JOURNAL_UNAVAILABLE")
        XCTAssertFalse(
            try XCTUnwrap(runStore.loadRaw(runId: "run-pm-turn-failure")).status.isTerminal,
            "run.json must not publish terminal state before pm-turn.json succeeds"
        )
    }

    func testTerminalTeamUsesLeadSynthesisForPMTurnReport() async throws {
        let service = makeResearchTeamService()
        let result = await service.run(
            RunRequest(message: "review the change", repoRoot: root.path, presetId: "research_pm_turn"),
            origin: .cli,
            runId: "team-terminal"
        )

        guard case .success = result else {
            return XCTFail("terminal team failed: \(result)")
        }
        let turn = try XCTUnwrap(try pmTurnStore.load(kind: .run, subjectId: "team-terminal"))
        XCTAssertEqual(turn.report, "# Lead synthesis\nShip the reviewed change.")
    }

    func testFailedTerminalRunStillWritesPMTurnWithMissingReportNote() async throws {
        let service = makeExecutionService(output: "", exitCode: 1)
        let result = await service.run(
            RunRequest(message: "make the change", repoRoot: root.path, presetId: "execution_pm_turn"),
            origin: .cli,
            runId: "failed-terminal"
        )

        guard case .success(let run) = result else {
            return XCTFail("worker failure should settle the run: \(result)")
        }
        XCTAssertEqual(run.status.lifecycle, .failed)
        let turn = try XCTUnwrap(try pmTurnStore.load(kind: .run, subjectId: run.id))
        XCTAssertEqual(turn.reason, "failed")
        XCTAssertNil(turn.report)
        XCTAssertTrue(turn.notes.contains("run_report_missing"))
    }

    /// ORS-S03b: PM turn projects onto `TeamRunJSON` via show/mapper (not team status/result).
    func testTerminalShowProjectionIncludesPersistedPMTurn() async throws {
        let service = makeExecutionService()
        let result = await service.run(
            RunRequest(message: "make the change", repoRoot: root.path, presetId: "execution_pm_turn"),
            origin: .cli,
            runId: "status-terminal"
        )
        guard case .success(let run) = result else {
            return XCTFail("terminal run failed: \(result)")
        }

        let turn = try XCTUnwrap(try pmTurnStore.load(kind: .run, subjectId: run.id))
        let projection = PMTurnStatusProjection.load(
            kind: .run, subjectId: run.id, atPMBoundary: true, store: pmTurnStore
        )
        let resultJSON = TeamRunJSONMapper.map(
            run,
            models: [],
            manifests: [],
            context: .init(
                runJournalPath: "", pmTurn: projection.pmTurn, pmTurnNotes: projection.notes
            )
        )
        XCTAssertEqual(resultJSON.pmTurn, turn)
        XCTAssertTrue(resultJSON.notes.isEmpty)
    }

    func testTerminalShowProjectionMarksMissingPMTurn() async throws {
        let service = makeExecutionService()
        let result = await service.run(
            RunRequest(message: "make the change", repoRoot: root.path, presetId: "execution_pm_turn"),
            origin: .cli,
            runId: "missing-status-turn"
        )
        guard case .success(let run) = result else {
            return XCTFail("terminal run failed: \(result)")
        }
        try FileManager.default.removeItem(at: try pmTurnStore.fileURL(for: .run, subjectId: run.id))

        let projection = PMTurnStatusProjection.load(
            kind: .run, subjectId: run.id, atPMBoundary: true, store: pmTurnStore
        )
        let resultJSON = TeamRunJSONMapper.map(
            run,
            models: [],
            manifests: [],
            context: .init(
                runJournalPath: "", pmTurn: projection.pmTurn, pmTurnNotes: projection.notes
            )
        )
        XCTAssertNil(resultJSON.pmTurn)
        XCTAssertEqual(resultJSON.notes, ["pm_turn_missing"])
    }

    private func makeExecutionService(
        output: String = "# Delivered\nThe change is complete.",
        exitCode: Int32 = 0,
        pmTurnStore: PMTurnStore? = nil
    ) -> RunService {
        let model = Model(
            id: "model_opus",
            displayName: "Opus",
            modelLabel: "opus",
            driverId: "claude_code",
            role: .both
        )
        let team = TeamPreset(
            id: "execution_pm_turn",
            displayName: "Execution",
            lane: .code,
            outputKind: .plan,
            mutating: true,
            executionSourceId: "claude_code",
            agentSpecs: [
                TeamAgentSpec(
                    id: "executor",
                    skillId: "first_principles_builder",
                    purpose: .answer,
                    preferredModelId: model.id
                ),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build")
        )
        return RunService(
            models: [model],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            ]),
            teams: [team],
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: [
                "claude": .init(stdout: output, exitCode: exitCode),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier,
                    allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: [model.id])
                )
            },
            probeRecords: {
                [ToolProbeRecord(
                    driverId: "claude_code",
                    status: .ready(version: "1"),
                    lastProbeAt: .distantPast
                )]
            },
            pmTurnStore: pmTurnStore
        )
    }

    private func makeResearchTeamService() -> RunService {
        let answerModel = Model(
            id: "model_opus",
            displayName: "Opus",
            modelLabel: "opus",
            driverId: "claude_code",
            role: .both
        )
        let leadModel = Model(
            id: "model_gemini",
            displayName: "Gemini",
            modelLabel: "gemini",
            driverId: "gemini",
            role: .both
        )
        let team = TeamPreset(
            id: "research_pm_turn",
            displayName: "Research",
            lane: .code,
            outputKind: .plan,
            mutating: false,
            agentSpecs: [
                TeamAgentSpec(id: "researcher_one", skillId: "bug_reproducer", purpose: .answer,
                              preferredModelId: answerModel.id),
                TeamAgentSpec(id: "researcher_two", skillId: "bug_reproducer", purpose: .answer,
                              preferredModelId: answerModel.id),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: leadModel.id)
        )
        return RunService(
            models: [answerModel, leadModel],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "claude_code", command: "claude"),
                TestSupport.headlessManifest(id: "gemini", command: "gemini"),
            ]),
            teams: [team],
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: [
                "claude": .init(stdout: "# Seat answer\nInvestigated the change.", exitCode: 0),
                "gemini": .init(stdout: "# Lead synthesis\nShip the reviewed change.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier,
                    allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: [answerModel.id, leadModel.id])
                )
            },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "gemini", status: .ready(version: "1"), lastProbeAt: .distantPast),
                ]
            },
            pmTurnStore: pmTurnStore
        )
    }
}
