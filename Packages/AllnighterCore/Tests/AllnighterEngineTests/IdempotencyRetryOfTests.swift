import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S05 / L9 — idempotency replay, conflict, expiry, and `--retry-of` gate.
final class IdempotencyRetryOfTests: XCTestCase {

    private func harness() throws -> (
        repo: URL, runs: RunStore, idem: IdempotencyStore, service: RunService
    ) {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("idem-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runs = RunStore(rootDirectory: repo.appendingPathComponent("runs", isDirectory: true))
        let idem = IdempotencyStore(fileURL: repo.appendingPathComponent("idempotency.json"))
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            runStore: runs,
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)]
            },
            idempotency: idem
        )
        return (repo, runs, idem, service)
    }

    func testReplayConflictAndExpiredCodes() async throws {
        let (repo, _, idem, service) = try harness()
        defer { try? FileManager.default.removeItem(at: repo) }

        let key = "k-\(UUID().uuidString)"
        let first = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path, idempotencyKey: key),
            origin: .cli
        )
        guard case .success(let firstRun) = first else { return XCTFail("\(first)") }

        let replay = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path, idempotencyKey: key),
            origin: .cli
        )
        guard case .success(let replayed) = replay else { return XCTFail("\(replay)") }
        XCTAssertEqual(replayed.id, firstRun.id)

        let conflict = await service.run(
            RunRequest(message: "different", repoRoot: repo.path, idempotencyKey: key),
            origin: .cli
        )
        guard case .failure(let err) = conflict else { return XCTFail("expected conflict") }
        XCTAssertEqual(err.code, "IDEMPOTENCY_CONFLICT")

        let expiredKey = "expired-\(UUID().uuidString)"
        try idem.seed(entry: .init(
            key: expiredKey,
            payloadDigest: "deadbeef",
            runId: "old-run",
            acceptedAt: Date().addingTimeInterval(-(IdempotencyStore.retention + 60))
        ))
        let expired = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path, idempotencyKey: expiredKey),
            origin: .cli
        )
        guard case .failure(let expiredErr) = expired else { return XCTFail("expected expired") }
        XCTAssertEqual(expiredErr.code, "IDEMPOTENCY_EXPIRED")
        XCTAssertEqual(IdempotencyStore.retention, 24 * 60 * 60)
    }

    func testRetryOfRefusesWhenSurvivorsWithoutAcceptFlag() async throws {
        let (repo, runs, _, service) = try harness()
        defer { try? FileManager.default.removeItem(at: repo) }

        let priorId = "prior-\(UUID().uuidString)"
        let prior = TeamRun(
            id: priorId, prompt: "old", status: .timedOut, createdAt: Date(),
            repoRoot: repo.path, endReason: .timedOut, killOutcome: .partial
        )
        try runs.save(prior, models: [])
        let dir = try runs.runDirectory(forRunId: priorId)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        let live = ProcessOwnership.OwnerIdentity(
            pid: pid, pgid: pid, startTimeTicks: ticks, kind: .devTurn)
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "w1", record: live.asRecord()), in: dir)

        let refused = await service.run(
            RunRequest(
                message: "retry", repoRoot: repo.path,
                idempotencyKey: "new-\(UUID().uuidString)", retryOf: priorId
            ),
            origin: .cli
        )
        guard case .failure(let err) = refused else { return XCTFail("expected RETRY_OF_SURVIVORS") }
        XCTAssertEqual(err.code, "RETRY_OF_SURVIVORS")

        let accepted = await service.run(
            RunRequest(
                message: "retry", repoRoot: repo.path,
                idempotencyKey: "new2-\(UUID().uuidString)",
                retryOf: priorId,
                acceptSurvivors: true
            ),
            origin: .cli
        )
        guard case .success(let run) = accepted else { return XCTFail("\(accepted)") }
        XCTAssertTrue(run.runLinks.contains(RunLink(kind: .retryOf, runId: priorId)))
        XCTAssertNotEqual(run.id, priorId)
    }

    func testRetryOfAfterVerifiedStop() async throws {
        let (repo, runs, _, service) = try harness()
        defer { try? FileManager.default.removeItem(at: repo) }

        let priorId = "stopped-\(UUID().uuidString)"
        let prior = TeamRun(
            id: priorId, prompt: "old", status: .cancelled, createdAt: Date(),
            repoRoot: repo.path, endReason: .killed, killOutcome: .stopped
        )
        try runs.save(prior, models: [])
        let dir = try runs.runDirectory(forRunId: priorId)
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_100_299, pgid: 9_401, startTimeTicks: 1, kind: .devTurn)
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "w1", record: dead.asRecord()), in: dir)

        let result = await service.run(
            RunRequest(
                message: "retry clean", repoRoot: repo.path,
                idempotencyKey: "retry-\(UUID().uuidString)", retryOf: priorId
            ),
            origin: .cli
        )
        guard case .success(let run) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(run.runLinks.contains(RunLink(kind: .retryOf, runId: priorId)))
    }

    func testClaimResultExpiredDirectly() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("idem-direct-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = IdempotencyStore(fileURL: file)
        let payload = AsyncTeamCanonicalPayload(
            prompt: "p", lane: "code", teamPresetId: "t", effort: "low",
            modelId: "m", type: nil, context: nil, repoRoot: "/r"
        )
        try store.seed(entry: .init(
            key: "k", payloadDigest: IdempotencyStore.digest(payload),
            runId: "r1",
            acceptedAt: Date().addingTimeInterval(-(IdempotencyStore.retention + 1))
        ))
        let result = try store.claim(key: "k", payload: payload, runId: "r2")
        guard case .expired = result else {
            return XCTFail("expected expired, got \(result)")
        }
    }
}
