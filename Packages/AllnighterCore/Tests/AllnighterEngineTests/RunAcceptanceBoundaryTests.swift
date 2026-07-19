import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S01b — the acceptance boundary (`docs/phases/Run_Lifecycle_Reliability.md`
/// RLR-L1/L2/L9, `docs/phases/rlr/S01_Execution_Plan.md` § S01b).
///
/// Proves the four S01b guarantees:
///  1. a durable, pollable run + typed blocker exist BEFORE the write-lock wait;
///  2. the `running` status is persisted BEFORE its event is emitted (no
///     emit-then-persist race);
///  3. a `RUN_NOT_FOUND` failure names the effective `ALLNIGHTER_SUPPORT_DIR`;
///  4. the generalized canonical idempotency payload round-trips and the sync
///     `alln run` acceptance path claims / replays / conflicts on the key.
final class RunAcceptanceBoundaryTests: XCTestCase {

    // MARK: - Shared harness (cursor default-route worker, mock CLI)

    private struct Harness {
        let repo: URL
        let runsDir: URL
        let runStore: RunStore
        let registry: RunWriteLockRegistry
        let service: RunService
        var root: String { RunWriteLock.normalize(repo.path) ?? repo.path }
        var lockKey: String { RunWriteLock.key(repoRoot: root) }
        func pollStore() -> RunStore { RunStore(rootDirectory: runsDir) }
    }

    private func makeHarness(idempotency: IdempotencyStore? = nil) throws -> Harness {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-accept-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let registry = RunWriteLockRegistry()
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: registry,
            defaultSettings: { settings },
            probeRecords: { [probe] },
            idempotency: idempotency ?? IdempotencyStore(
                fileURL: repo.appendingPathComponent("idempotency.json")))
        return Harness(repo: repo, runsDir: runsDir, runStore: runStore, registry: registry, service: service)
    }

    // MARK: - 1. Durable, pollable queued run + blocker during the write-lock wait

    func testWriteLockWaitLeavesDurablePollableQueuedRunWithBlocker() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // A competing mutating run already holds the per-root write lock.
        let holder = await h.registry.waitToAcquire(h.lockKey, timeout: .seconds(30))
        let holderToken = try XCTUnwrap(holder, "test could not pre-hold the write lock")

        // Start our run (blocks in `waitToAcquire`); mint id is ours so we can poll it.
        let runId = UUID().uuidString
        let request = RunRequest(message: "edit the repo", repoRoot: h.repo.path)
        let runTask = Task { await h.service.run(request, origin: .cli, runId: runId) }

        // A SECOND, independent RunStore polls the same durable truth mid-wait.
        let poll = h.pollStore()
        var pending: TeamRun?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let r = poll.loadRaw(runId: runId), r.status == .queued { pending = r; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let run = try XCTUnwrap(pending, "a queued run.json must be pollable DURING the write-lock wait")

        XCTAssertEqual(run.status, .queued)
        XCTAssertEqual(run.status.lifecycle, .queued)
        XCTAssertEqual(run.phase, .waitingForWriteLock)
        XCTAssertEqual(run.blocker?.resource, .repoWriteLock)
        XCTAssertEqual(run.blocker?.scopeRoot, h.root)
        XCTAssertFalse(run.status.isTerminal)

        // Release the lock → our run acquires it, clears the blocker, and settles.
        await h.registry.release(h.lockKey, token: holderToken)
        _ = await runTask.value
        let settled = try XCTUnwrap(poll.loadRaw(runId: runId))
        XCTAssertTrue(settled.status.isTerminal)
        XCTAssertNil(settled.blocker)
        XCTAssertNil(settled.phase)
    }

    // MARK: - 2. Save precedes the status-changed emit (no emit-then-persist race)

    func testRunningStatusIsDurableBeforeItsEventIsEmitted() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let runId = UUID().uuidString
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let poll = h.pollStore()

        // On the `running` runStatusChanged event, the journal must ALREADY have left
        // `queued` — proof that `runStore.save` ran before `emit`. Monotonic: once
        // running is emitted the run never regresses to queued, so a slightly-late read
        // can only show running/done, never queued (which would mean emit-before-save).
        let observer = Task { () -> (sawRunning: Bool, durable: Bool) in
            var sawRunning = false
            var durable = false
            for await e in stream where e.kind == RunEventKind.runStatusChanged
                && e.payload["to"] == .string(RunStatus.running.rawValue) {
                sawRunning = true
                durable = poll.loadRaw(runId: runId).map { $0.status.lifecycle != .queued } ?? false
            }
            return (sawRunning, durable)
        }

        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path),
            origin: .cli, runId: runId, events: continuation)
        let seen = await observer.value

        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(seen.sawRunning, "a running runStatusChanged event must be emitted")
        XCTAssertTrue(seen.durable, "the journal must be persisted at >= running BEFORE the running event fires")
    }

    // MARK: - 4. Canonical payload round-trip + sync-path idempotency claim

    func testExtendedCanonicalPayloadRoundTripsAndDigestsAreFieldSensitive() throws {
        let base = AsyncTeamCanonicalPayload(
            prompt: "do the thing", lane: "code", teamPresetId: "build_slice", effort: "high",
            modelId: "model_cursor_composer_25", type: nil, context: "ctx", repoRoot: "/tmp/repo",
            attachmentDigests: ["a1b2", "c3d4"], threadId: "thread_7",
            resolvedTeamId: "build_slice", resolvedWorkerIds: ["model_cursor_composer_25"],
            handshakeTimeout: 60, firstActivityTimeout: 120, idleTimeout: 300, wallTimeout: 3600,
            proofCommand: "swift test", commitMessage: "fix: thing", noCommit: false,
            contractVersion: "1")

        let data = try CoreJSON.encode(base)
        let decoded = try CoreJSON.decode(AsyncTeamCanonicalPayload.self, from: data)
        XCTAssertEqual(decoded, base, "generalized canonical payload must round-trip all fields")

        // Equal payloads → equal digest; a single generalized field change → different digest.
        XCTAssertEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(decoded))
        var changedProof = base; changedProof.proofCommand = "swift build"
        XCTAssertNotEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(changedProof))
        var changedAttachments = base; changedAttachments.attachmentDigests = ["a1b2"]
        XCTAssertNotEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(changedAttachments))
    }

    func testSyncRunClaimsIdempotencyKeyAndReplaysSameRunNeverASecondWorker() async throws {
        let idemFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("idem-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: idemFile) }
        let h = try makeHarness(idempotency: IdempotencyStore(fileURL: idemFile))
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let key = "idem-key-\(UUID().uuidString)"
        func request() -> RunRequest {
            RunRequest(message: "Say done", repoRoot: h.repo.path, idempotencyKey: key)
        }

        // First acceptance: claims the key, mints + runs one worker.
        let first = await h.service.run(request(), origin: .cli)
        guard case .success(let firstRun) = first else { return XCTFail("first run failed: \(first)") }

        // Second acceptance, same key + same payload: replays the ORIGINAL run — no
        // second run directory is created.
        let second = await h.service.run(request(), origin: .cli)
        guard case .success(let secondRun) = second else { return XCTFail("replay failed: \(second)") }
        XCTAssertEqual(secondRun.id, firstRun.id, "same key + payload must replay the original run id")

        let runDirs = (try? FileManager.default.contentsOfDirectory(atPath: h.runsDir.path))?
            .filter { $0.hasPrefix("run_") } ?? []
        XCTAssertEqual(runDirs.count, 1, "transport replay must not spawn a second run/worker")

        // Same key + DIFFERENT payload: conflict refusal (never silently re-executes).
        let conflict = await h.service.run(
            RunRequest(message: "different message", repoRoot: h.repo.path, idempotencyKey: key),
            origin: .cli)
        guard case .failure(let error) = conflict else { return XCTFail("expected conflict, got \(conflict)") }
        XCTAssertEqual(error.code, "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD")
    }

    func testRetryOfRecordsDurableRunLinkWithoutReplayExecution() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let oldId = "old-run-\(UUID().uuidString)"
        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path, retryOf: oldId), origin: .cli)
        guard case .success(let run) = result else { return XCTFail("retry run failed: \(result)") }
        XCTAssertTrue(
            run.runLinks.contains(RunLink(kind: .retryOf, runId: oldId)),
            "a --retry-of run must carry a durable RunLink.retryOf to the prior run")
        // Link only — the new run executed its own worker (a distinct id), no replay.
        XCTAssertNotEqual(run.id, oldId)
    }

    // MARK: - 3. RUN_NOT_FOUND names the effective support dir (real CLI)

    func testRunNotFoundErrorNamesEffectiveSupportDir() throws {
        let alln = try locateAllnBinary()
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlr-supportdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let env = [
            "ALLNIGHTER_SUPPORT_DIR": support.path,
            "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": support.path,
        ]
        let result = try runAlln(alln, ["team", "status", "does-not-exist", "--json"], env: env)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
            "expected a JSON error object, got: \(result.stdout.prefix(300))")
        let error = try XCTUnwrap(obj["error"] as? [String: Any], "expected an error envelope")
        XCTAssertEqual(error["code"] as? String, "RUN_NOT_FOUND")
        let message = error["message"] as? String ?? ""
        XCTAssertTrue(message.contains(support.path),
                      "RUN_NOT_FOUND message must name the effective support dir: \(message)")
        XCTAssertEqual(error["supportDir"] as? String, support.path,
                       "the machine envelope must carry the effective supportDir")
    }

    // MARK: - Subprocess helpers

    private func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: RunAcceptanceBoundaryTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path),
                      "alln binary missing at \(binary.path) — build the alln product first")
        return binary
    }

    private struct ProcessResult { var status: Int32; var stdout: String; var stderr: String }

    private func runAlln(_ alln: URL, _ arguments: [String], env: [String: String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.environment = env
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out; process.standardError = err
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
