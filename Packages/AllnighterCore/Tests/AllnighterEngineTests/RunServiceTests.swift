import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RunServiceTests: XCTestCase {
    // Several cases build RunService without an explicit runStore, whose default is
    // the real ~/Library/Application Support/Allnighter/Runs. Redirect the support
    // root to a temp dir so runs never leak into real user state.
    private var supportDir: URL!
    override func setUpWithError() throws {
        supportDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("runservice-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", supportDir.path, 1)
    }
    override func tearDownWithError() throws {
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: supportDir)
    }

    func testExecutionRunStreamFinishesAndEmitsTerminalEvents() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let model = Model(
            id: "model_cursor_composer_25",
            displayName: "Cursor Composer",
            modelLabel: "composer-2.5",
            driverId: "cursor_agent",
            role: .both
        )
        // Auto (default route) resolves the worker from the Default-model tiers, so the
        // test's model must be the default tier's default and its source probe ready.
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )
        let request = RunRequest(message: "Say done", repoRoot: repo.path)
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let eventsTask = Task {
            var events: [RunEvent] = []
            for await event in stream { events.append(event) }
            return events
        }

        let result = await service.run(request, origin: .cli, events: continuation)
        let events = await eventsTask.value

        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(events.contains { $0.kind == RunEventKind.workerStatusChanged && $0.payload["to"] == .string(WorkerAnswerStatus.done.rawValue) })
        XCTAssertTrue(events.contains { $0.kind == RunEventKind.runStatusChanged && $0.payload["to"] == .string(RunStatus.complete.rawValue) })
    }

    func testExecutionRunPersistsTimingLadder() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let model = Model(
            id: "model_cursor_composer_25",
            displayName: "Cursor Composer",
            modelLabel: "composer-2.5",
            driverId: "cursor_agent",
            role: .both
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let runStore = RunStore(rootDirectory: repo.appendingPathComponent("runs", isDirectory: true))
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        var seed = RunTimingReport()
        seed.stamp(RunTimingKey.composerSubmit)
        seed.stamp(RunTimingKey.contextBuildStart)
        seed.stamp(RunTimingKey.contextBuildEnd)
        seed.set(RunTimingKey.contextTurnCount, int: 3)

        let request = RunRequest(
            message: "Say done",
            repoRoot: repo.path,
            context: "file reference context",
            timing: seed
        )
        let result = await service.run(request, origin: .cli, runId: "timing-run")

        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        let timing = try XCTUnwrap(run.timing)
        XCTAssertNotNil(timing.event(named: RunTimingKey.composerSubmit))
        XCTAssertNotNil(timing.event(named: RunTimingKey.runRequested))
        XCTAssertNotNil(timing.event(named: RunTimingKey.workerResolveStart))
        XCTAssertNotNil(timing.event(named: RunTimingKey.workerResolveEnd))
        XCTAssertNotNil(timing.event(named: RunTimingKey.driverCommandResolved))
        XCTAssertNotNil(timing.event(named: RunTimingKey.processSpawnStart))
        XCTAssertNotNil(timing.event(named: RunTimingKey.processExit))
        XCTAssertNotNil(timing.event(named: RunTimingKey.runOutcomePersisted))
        XCTAssertEqual(timing.facts[RunTimingKey.sourceId], .string("cursor_agent"))
        XCTAssertEqual(timing.facts[RunTimingKey.modelId], .string("model_cursor_composer_25"))
        XCTAssertEqual(timing.facts[RunTimingKey.commandModelFlag], .string("composer-2.5"))
        XCTAssertEqual(timing.facts[RunTimingKey.contextBytes], .int("file reference context".utf8.count))

        let persisted = try XCTUnwrap(runStore.load(runId: "timing-run"))
        XCTAssertNotNil(persisted.timing?.event(named: RunTimingKey.runOutcomePersisted))
    }

    /// SBDS-S03: Auto runs the tier default, but routes around a down CLI to the next
    /// source-ready model on the same tier — without asking.
    func testAutoRoutesAroundADownCLIWithinTheTier() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        // Frontier = [Opus (claude_code, DOWN), ChatGPT (codex, ready)]. Auto must skip
        // the down default and run ChatGPT.
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let gpt = Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt", driverId: "codex", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_opus", "model_chatgpt"]))
        // Only codex is probe-ready; claude_code has no ready record → Opus is down.
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [opus, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "claude_code", command: "claude"),
                TestSupport.headlessManifest(id: "codex", command: "codex")]),
            commandRunner: MockCommandRunner(scripts: [
                "claude": .init(stdout: "", exitCode: 1),       // would fail if Auto wrongly used it
                "codex": .init(stdout: "Routed.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(RunRequest(message: "hi", repoRoot: repo.path), origin: .cli)
        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }
        XCTAssertEqual(run.answers.first?.modelId, "model_chatgpt", "Auto routed around the down Opus to ChatGPT")
        XCTAssertEqual(run.executionSourceId, "codex", "run records the CLI it actually ran on, not the default team's declared source")
        XCTAssertEqual(run.status, .complete)
    }

    /// SBDS-S03: when the whole default tier is down, Auto waits (clean failure) rather
    /// than guessing some other model.
    func testAutoWaitsWhenTheWholeTierIsDown() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_opus"]))
        let service = RunService(
            models: [opus],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "x", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [] }   // nothing probe-ready
        )

        let result = await service.run(RunRequest(message: "hi", repoRoot: repo.path), origin: .cli)
        guard case .failure(let err) = result else { return XCTFail("expected Auto to wait, got \(result)") }
        XCTAssertEqual(err.code, "DEFAULT_TEAM_INVALID")
    }

    // MARK: - PO-F10 honest explicit --model

    func testExplicitWorkerDisabledFailsWithWorkerNotAvailableNeverSubstitutes() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: false
        )
        let gpt = Model(
            id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_chatgpt"]))
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [grok, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
                TestSupport.headlessManifest(id: "codex", command: "codex"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(stdout: "Should never run.", exitCode: 0),
                "codex": .init(stdout: "Silent substitute.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_cursor_grok_45"),
            origin: .cli
        )
        guard case .failure(let err) = result else {
            return XCTFail("expected AGENT_NOT_AVAILABLE, got success: \(result)")
        }
        XCTAssertEqual(err.code, "AGENT_NOT_AVAILABLE")
        XCTAssertTrue(err.description.contains("model_cursor_grok_45"))
        XCTAssertTrue(err.description.contains("disabled"))
    }

    func testExplicitWorkerUnknownFailsWithAgentNotAvailable() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let gpt = Model(
            id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_chatgpt"]))
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [gpt],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "codex", command: "codex")]),
            commandRunner: MockCommandRunner(scripts: ["codex": .init(stdout: "Nope.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_does_not_exist"),
            origin: .cli
        )
        guard case .failure(let err) = result else {
            return XCTFail("expected AGENT_NOT_AVAILABLE, got \(result)")
        }
        XCTAssertEqual(err.code, "AGENT_NOT_AVAILABLE")
        XCTAssertTrue(err.description.contains("unknown"))
    }

    func testExplicitWorkerNotReadyFailsWithAgentNotAvailable() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: true
        )
        let gpt = Model(
            id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_chatgpt"]))
        // Only codex is probe-ready; explicit grok is enabled-but-notReady.
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [grok, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
                TestSupport.headlessManifest(id: "codex", command: "codex"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(stdout: "Should never run.", exitCode: 0),
                "codex": .init(stdout: "Silent substitute.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_cursor_grok_45"),
            origin: .cli
        )
        guard case .failure(let err) = result else {
            return XCTFail("expected AGENT_NOT_AVAILABLE, got \(result)")
        }
        XCTAssertEqual(err.code, "AGENT_NOT_AVAILABLE")
        XCTAssertTrue(err.description.contains("notReady"))
    }

    func testExplicitWorkerEnabledAndReadyIsHonored() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: true
        )
        let gpt = Model(
            id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_chatgpt"]))
        let probes = [
            ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1"), lastProbeAt: .distantPast),
            ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast),
        ]
        let service = RunService(
            models: [grok, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
                TestSupport.headlessManifest(id: "codex", command: "codex"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(stdout: "Grok ran.", exitCode: 0),
                "codex": .init(stdout: "Should not run.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { probes }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_cursor_grok_45"),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        XCTAssertEqual(run.answers.first?.modelId, "model_cursor_grok_45")
        XCTAssertEqual(run.executionSourceId, "cursor_agent")
        XCTAssertEqual(run.status, .complete)
    }

    /// Regression for the silent skill substitution bug: a pinned worker's `skillId`
    /// used to be read from `resolved.answerWorkers.first`, which only contains rows
    /// that found a READY model. When `build_slice`'s declared answer-row model
    /// (Cursor Composer) is disabled, `resolved.answerWorkers` resolves empty even
    /// though a *different* worker is explicitly pinned via `--model` — so the old
    /// code silently fell back to `first_principles_builder` instead of the team's
    /// declared `execution_playbook` skill. The skill must come from the preset's
    /// durable declaration, never from bench readiness.
    func testPinnedWorkerKeepsDeclaredSkillWhenDeclaredAnswerModelIsDisabled() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        guard let buildSlice = TeamCatalog.get("build_slice"),
              let declaredAnswerRow = buildSlice.agentSpecs.first(where: { $0.purpose == .answer }) else {
            return XCTFail("build_slice must declare exactly one answer row for this gate")
        }
        XCTAssertEqual(declaredAnswerRow.skillId, "execution_playbook")

        // The declared answer-row model, disabled — `resolved.answerWorkers` will
        // resolve empty because neither it nor any same-driver substitute is ready.
        let composer = Model(
            id: declaredAnswerRow.preferredModelId ?? "model_cursor_composer_25",
            displayName: "Cursor Composer", modelLabel: "composer-2.5",
            driverId: "cursor_agent", role: .both, enabled: false
        )
        // A different, ready model pinned explicitly via `--model`.
        let gpt = Model(
            id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_chatgpt"]))
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [composer, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
                TestSupport.headlessManifest(id: "codex", command: "codex"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "codex": .init(stdout: "Sliced.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(
                message: "do the thing", repoRoot: repo.path,
                presetId: "build_slice", pinnedModelId: "model_chatgpt"
            ),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        XCTAssertEqual(run.workers.first?.modelId, "model_chatgpt")
        XCTAssertEqual(
            run.workers.first?.skillId, "execution_playbook",
            "pinned worker must keep the preset's declared answer skill, never the generic fallback"
        )
    }

    /// AE-S03: answer-path (non-mutating team) must fail closed on a bogus `--model`,
    /// never accept-and-drop.
    func testAnswerPathBogusWorkerFailsWithAgentNotAvailable() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-answer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        guard let bugHunt = TeamCatalog.get("code_bug_hunt"), bugHunt.mutating == false else {
            return XCTFail("code_bug_hunt must be a non-mutating answer team for this gate")
        }

        let gpt = Model(
            id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_chatgpt"]))
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [gpt],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "codex", command: "codex")]),
            teams: [bugHunt],
            commandRunner: MockCommandRunner(scripts: [
                "codex": .init(stdout: "Should never run.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(
                message: "probe",
                repoRoot: repo.path,
                presetId: "code_bug_hunt",
                pinnedModelId: "model_bogus_id"
            ),
            origin: .cli
        )
        guard case .failure(let err) = result else {
            return XCTFail("expected AGENT_NOT_AVAILABLE on answer path, got success: \(result)")
        }
        XCTAssertEqual(err.code, "AGENT_NOT_AVAILABLE")
        XCTAssertTrue(err.description.contains("model_bogus_id"))
    }
}
