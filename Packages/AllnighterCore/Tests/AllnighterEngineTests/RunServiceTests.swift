import XCTest
import AgentOSTeam
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
        let gpt = Model(id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt", driverId: "codex", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_opus", "model_gpt_sol"]))
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
        XCTAssertEqual(run.answers.first?.modelId, "model_gpt_sol", "Auto routed around the down Opus to ChatGPT")
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
            id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_gpt_sol"]))
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
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(err.description),
            "disabled reason must name models enable; got \(err.description)"
        )
    }

    func testExplicitWorkerUnknownFailsWithAgentNotAvailable() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let gpt = Model(
            id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_gpt_sol"]))
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
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(err.description),
            "unknown id must name models --json discovery; got \(err.description)"
        )
    }

    func testExplicitWorkerNotReadyStillDispatchesWhenDriverInstalled() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: true
        )
        let gpt = Model(
            id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_gpt_sol"]))
        // Cached negative readiness, but driver is installed (installedNotProbed) —
        // ORS-P0-DEGRADE: must ATTEMPT, not pre-emptively refuse.
        let probe = ToolProbeRecord(
            driverId: "cursor_agent",
            status: .installedNotProbed(version: "0.2.117"),
            invocation: .direct(path: "/usr/bin/cursor"),
            version: "0.2.117",
            lastProbeAt: .distantPast
        )
        let codexReady = ToolProbeRecord(
            driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [grok, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
                TestSupport.headlessManifest(id: "codex", command: "codex"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(stdout: "Grok ran despite stale cache.", exitCode: 0),
                "codex": .init(stdout: "Should not run.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe, codexReady] }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_cursor_grok_45"),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail("stale notReady must not block dispatch; got \(result)")
        }
        XCTAssertEqual(run.answers.first?.modelId, "model_cursor_grok_45")
        XCTAssertEqual(run.executionSourceId, "cursor_agent")
    }

    /// Stale-cache case: probe says `.notInstalled` but the binary is on PATH
    /// (mock succeeds). Explicit `--model` must dispatch and complete — never
    /// pre-dispatch AGENT_NOT_AVAILABLE from the cache.
    func testExplicitWorkerCachedNotInstalledStillDispatchesWhenBinaryPresent() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_grok_45"]))
        let probe = ToolProbeRecord(
            driverId: "cursor_agent", status: .notInstalled, lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [grok],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(stdout: "Installed after cache went stale.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_cursor_grok_45"),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail(
                "stale notInstalled cache must not veto explicit pin; got \(result)"
            )
        }
        XCTAssertEqual(run.answers.first?.modelId, "model_cursor_grok_45")
        XCTAssertEqual(run.executionSourceId, "cursor_agent")
        XCTAssertEqual(run.status, .complete)
    }

    /// Cached `.notInstalled` + genuinely missing binary: dispatch is attempted;
    /// failure is loud at spawn (names the binary), not pre-dispatch AGENT_NOT_AVAILABLE.
    func testExplicitWorkerCachedNotInstalledFailsAtSpawnNamingBinary() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_grok_45"]))
        let probe = ToolProbeRecord(
            driverId: "cursor_agent", status: .notInstalled, lastProbeAt: .distantPast
        )
        let missingMessage = "command not found: cursor"
        let service = RunService(
            models: [grok],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(launchError: missingMessage),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, pinnedModelId: "model_cursor_grok_45"),
            origin: .cli
        )
        guard case .success(let run) = result else {
            if case .failure(let err) = result {
                XCTFail(
                    "missing binary must reach spawn, not pre-dispatch AGENT_NOT_AVAILABLE; " +
                    "got \(err.code): \(err.description)"
                )
            }
            return
        }
        XCTAssertNotEqual(run.status, .complete, "dead CLI must not report success")
        let reason = run.answers.first?.result.errorReason
            ?? run.failedWorkerAnswers.first?.result.errorReason
            ?? run.attempts.last?.reason
            ?? ""
        XCTAssertTrue(
            reason.contains("cursor") || reason.contains(missingMessage),
            "failure must name the missing binary; got \(reason)"
        )
        let kind = run.answers.first?.result.errorKind
            ?? run.failedWorkerAnswers.first?.result.errorKind
        if let kind {
            XCTAssertEqual(kind, .missingCLI, "spawn miss should be typed missingCLI; got \(kind)")
        }
    }

    /// Legitimate refusal: user-parked driver still hard-blocks with unpark remediation.
    func testExplicitWorkerParkedStillHardBlocksWithUnparkRemediation() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        var state = SetupStore().load()
        state.park("cursor_agent")
        try SetupStore().save(state)

        let grok = Model(
            id: "model_cursor_grok_45", displayName: "Cursor Grok", modelLabel: "grok",
            driverId: "cursor_agent", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_grok_45"]))
        let probe = ToolProbeRecord(
            driverId: "cursor_agent", status: .ready(version: "1"), lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [grok],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "cursor_agent", command: "cursor"),
            ]),
            commandRunner: MockCommandRunner(scripts: [
                "cursor": .init(stdout: "Should never run.", exitCode: 0),
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
            return XCTFail("expected AGENT_NOT_AVAILABLE for parked driver, got \(result)")
        }
        XCTAssertEqual(err.code, "AGENT_NOT_AVAILABLE")
        XCTAssertTrue(err.description.contains("parked"), "got \(err.description)")
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(err.description),
            "parked reason must name unpark; got \(err.description)"
        )
    }

    /// Legitimate refusal: write-lock busy error stays typed and names kill/ps.
    func testWriteLockBusyErrorStillTypedWithWorkingRemediation() {
        let err = RunServiceError.writeLockBusy("/tmp/repo-root")
        XCTAssertEqual(err.code, "RUN_WRITE_LOCK_BUSY")
        XCTAssertTrue(err.description.contains("alln ps") || err.description.contains("alln kill"))
        XCTAssertTrue(
            DispatchReadiness.blockedReasonNamesWorkingRemediation(err.description),
            "write-lock busy must name a working remediation; got \(err.description)"
        )
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
            id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_gpt_sol"]))
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
            id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_gpt_sol"]))
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
                presetId: "build_slice", pinnedModelId: "model_gpt_sol"
            ),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        XCTAssertEqual(run.workers.first?.modelId, "model_gpt_sol")
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
            id: "model_gpt_sol", displayName: "ChatGPT", modelLabel: "gpt",
            driverId: "codex", role: .both, enabled: true
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_gpt_sol"]))
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

    // MARK: - VSI-S05 partial-answer durability

    /// Mid-stream answer deltas must land in `run.json` before kill; after kill
    /// the durable partial survives (not watcher-buffer-only).
    func testKillAfterDeltaPreservesDurablePartial() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-partial-kill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        var manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        manifest.streaming = .init(
            supported: true, mode: .jsonlStdout,
            args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
            partialOutput: true, finalAnswerSource: .parserAccumulator)
        let model = Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_grok"]))
        let probe = ToolProbeRecord(
            driverId: "grok", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let team = TeamPreset(
            id: "vsi_s05_kill_team", displayName: "VSI Kill Team", lane: .code,
            outputKind: .plan, mutating: true, defaultEffort: .low, isDefaultForLane: false,
            agentSpecs: [TeamAgentSpec(
                id: "r1", skillId: "bug_reproducer", purpose: .answer,
                preferredModelId: "model_grok")],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_grok"),
            builtIn: false)

        let marker = "VSI_S05_DURABLE_PARTIAL_MARKER"
        // Exceed StreamingPartialBuffer.flushByteThreshold so emitAnswer runs
        // mid-stream while the runner is still hung (cadence alone never fires
        // without a later delta after 0.1s — both lines arrive in one stdout).
        let pad = String(repeating: "x", count: 2_100)
        let ndjson = """
        {"type":"text","data":"\(marker) \(pad)"}
        {"type":"text","data":" more work"}

        """
        let hang = HangAfterDribbleRunner(events: [
            .started(startedAt: Date()),
            .stdout(Data(ndjson.utf8)),
        ])
        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            teams: [team],
            runStore: runStore,
            commandRunner: hang,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let runId = UUID().uuidString
        let runTask = Task {
            await service.run(
                RunRequest(message: "produce work", repoRoot: repo.path, presetId: team.id),
                origin: .cli, runId: runId)
        }

        let deadline = Date().addingTimeInterval(8)
        var sawPartial = false
        while Date() < deadline {
            if let live = runStore.loadRaw(runId: runId),
               let out = live.answers.first?.result.output,
               out.contains(marker) {
                sawPartial = true
                break
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTAssertTrue(sawPartial, "mid-stream flush must persist the partial to run.json before kill")

        // Stamp a verified kill the same way ProcessOwnershipSurface does once
        // settlement returns `.stopped` — status cancelled, endReason killed,
        // answers cancelled without erasing output.
        var durable = try XCTUnwrap(runStore.loadRaw(runId: runId))
        durable.status = .cancelled
        durable.endReason = .killed
        durable.phase = nil
        for i in durable.answers.indices where !durable.answers[i].result.status.isTerminal {
            durable.answers[i].result.status = .cancelled
        }
        try runStore.save(durable, models: [model])
        hang.cancel()

        let settled = await runTask.value
        guard case .success(let returned) = settled else {
            return XCTFail("expected durable terminal return, got \(settled)")
        }
        XCTAssertEqual(returned.status, .cancelled)
        let text = try XCTUnwrap(returned.answers.first?.result.output)
        XCTAssertTrue(text.contains(marker), "kill must preserve durable partial: \(text)")

        let trj = TeamRunJSONMapper.map(
            returned, models: [model], manifests: [manifest], context: .init())
        XCTAssertEqual(trj.answer?.markdown?.contains(marker), true)
        XCTAssertEqual(trj.answer?.status, .cancelled)
        XCTAssertNotEqual(trj.answer?.status, .done)
    }

    /// A late partial flush against an already-terminal run must no-op — never
    /// resurrect status or clobber settled truth.
    func testLatePartialFlushCannotResurrectTerminalRun() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-late-flush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let runStore = RunStore(rootDirectory: repo.appendingPathComponent("runs"))
        let worker = Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0)
        let run = TeamRun(
            id: UUID().uuidString, prompt: "done", status: .failed,
            workers: [worker],
            answers: [TeamAnswer(
                memberId: worker.id, modelId: worker.modelId, role: "answer",
                result: WorkerRunResult(status: .failed, output: "settled output"))],
            createdAt: Date(), endReason: .failed)
        try runStore.save(run, models: [])

        let wrote = runStore.updatePartialAnswer(
            runId: run.id, workerId: worker.id,
            output: "late flush must not land", at: Date())
        XCTAssertFalse(wrote, "terminal run must refuse the late partial flush")

        let after = try XCTUnwrap(runStore.loadRaw(runId: run.id))
        XCTAssertEqual(after.status, .failed)
        XCTAssertEqual(after.endReason, .failed)
        XCTAssertEqual(after.answers.first?.result.output, "settled output")
        XCTAssertNotEqual(after.status, .running)
    }
}

/// Streams scripted events then parks until `cancel()` — models a worker killed
/// mid-answer after durable partial text has already flushed.
private final class HangAfterDribbleRunner: CommandRunner, StreamingCommandRunner, @unchecked Sendable {
    private let events: [CommandEvent]
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancelled = false

    init(events: [CommandEvent]) { self.events = events }

    func cancel() {
        lock.lock()
        cancelled = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        CommandResult(stdout: "", exitCode: 1)
    }

    func runStreaming(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        let events = self.events
        return AsyncThrowingStream { cont in
            Task {
                for event in events { cont.yield(event) }
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    self.lock.lock()
                    if self.cancelled {
                        self.lock.unlock()
                        c.resume()
                    } else {
                        self.continuation = c
                        self.lock.unlock()
                    }
                }
                cont.finish()
            }
        }
    }
}
