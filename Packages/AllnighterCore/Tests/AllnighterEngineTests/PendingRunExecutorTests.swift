import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PendingRunExecutorTests: XCTestCase {
    private let models = [
        Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both),
        Model(id: "model_codex", displayName: "Codex", modelLabel: "gpt", driverId: "codex", role: .answerer),
    ]

    private var root: URL!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pending-run-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeExecutor(
        scripts: [String: MockCommandRunner.Script],
        manifests: [DriverManifest]? = nil
    ) -> PendingRunExecutor {
        let store = PendingStore(rootDirectory: root)
        let now = fixedNow
        let service = PendingService(
            store: store,
            models: models,
            idFactory: { "pending_test_\(UUID().uuidString.prefix(8))" },
            now: { now }
        )
        let registry = DriverRegistry(manifests ?? [
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "codex", command: "codex"),
        ])
        return PendingRunExecutor(
            service: service,
            registry: registry,
            commandRunner: MockCommandRunner(scripts: scripts),
            now: { now }
        )
    }

    private func addWorkerChat(_ executor: PendingRunExecutor, worker: String = "claude", prompt: String = "Review patch") throws -> PendingItem {
        try executor.service.add(.init(prompt: prompt, workerToken: worker, submit: true))
    }

    func testWorkerChatRunSuccessSettlesDone() async throws {
        let executor = makeExecutor(scripts: ["claude": .init(stdout: "Review complete.", exitCode: 0)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)
        let json = try executor.service.mapJSON(settled)

        XCTAssertEqual(settled.status, .done)
        XCTAssertEqual(settled.attempts.last?.status, .done)
        XCTAssertNil(settled.lease)
        XCTAssertNil(settled.resume)
        XCTAssertNotNil(settled.attempts.last?.transcriptRef)
        XCTAssertEqual(json.pendingItem.status, .done)
        XCTAssertEqual(json.attempts.last?.status, "done")
        XCTAssertEqual(json.attempts.last?.transcriptRef, settled.attempts.last?.transcriptRef)
        XCTAssertFalse(jsonBlob(json).contains("Review complete."))
    }

    func testOrdinaryFailureSettlesFailed() async throws {
        let executor = makeExecutor(scripts: ["claude": .init(stderr: "boom", exitCode: 1)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)

        XCTAssertEqual(settled.status, .failed)
        XCTAssertEqual(settled.attempts.last?.status, .failed)
        XCTAssertEqual(settled.attempts.last?.reason, "boom")
        XCTAssertNil(settled.lease)
        XCTAssertNil(settled.resume)
    }

    func testAccountRateLimitReturnsPendingWithCooldownResume() async throws {
        let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"You've been rate limited","retry_after":9900}}"#
        let executor = makeExecutor(scripts: ["claude": .init(stderr: stderr, exitCode: 1)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)
        let json = try executor.service.mapJSON(settled)

        XCTAssertEqual(settled.status, .pending)
        XCTAssertEqual(settled.attempts.last?.status, .blocked)
        XCTAssertEqual(settled.resume?.reason, .cooldown)
        XCTAssertEqual(settled.resume?.capacityObservation?.kind, .accountRateLimit)
        XCTAssertNil(settled.lease)
        XCTAssertNotNil(json.capacityObservation)
        XCTAssertEqual(json.capacityObservation?.kind, "accountRateLimit")
        XCTAssertNotNil(json.pendingItem.nextWakeAt)
    }

    func testProviderBusyReturnsPendingWithProviderBusyResume() async throws {
        let stderr = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let executor = makeExecutor(scripts: ["claude": .init(stderr: stderr, exitCode: 1)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)
        let json = try executor.service.mapJSON(settled)

        XCTAssertEqual(settled.status, .pending)
        XCTAssertEqual(settled.attempts.last?.status, .blocked)
        XCTAssertEqual(settled.resume?.reason, .providerBusy)
        XCTAssertEqual(settled.resume?.capacityObservation?.kind, .providerBusy)
        XCTAssertNotNil(settled.resume?.wakeAfter)
        XCTAssertNotNil(json.capacityObservation)
        XCTAssertEqual(json.capacityObservation?.kind, "providerBusy")
    }

    func testAuthRequiredBlocksWithoutWakeTicket() async throws {
        let executor = makeExecutor(scripts: ["claude": .init(stderr: "Error: not signed in — please run /login", exitCode: 1)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)
        let json = try executor.service.mapJSON(settled)

        XCTAssertEqual(settled.status, .pending)
        XCTAssertEqual(settled.attempts.last?.status, .blocked)
        XCTAssertEqual(settled.attempts.last?.reason, "authRequired")
        XCTAssertNil(settled.resume)
        XCTAssertNil(json.capacityObservation)
        XCTAssertNil(json.pendingItem.nextWakeAt)
    }

    func testManualRequiredBlocksWithoutWakeTicket() async throws {
        let executor = makeExecutor(scripts: ["claude": .init(stderr: "awaiting manual paste from user", exitCode: 1)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)

        XCTAssertEqual(settled.status, .pending)
        XCTAssertEqual(settled.attempts.last?.status, .blocked)
        XCTAssertEqual(settled.attempts.last?.reason, "manualRequired")
        XCTAssertNil(settled.resume)
    }

    func testTimedOutClearsLeaseAndDoesNotLeaveRunning() async throws {
        let executor = makeExecutor(scripts: ["claude": .init(forcesTimeout: true)])
        let item = try addWorkerChat(executor)

        let settled = try await executor.run(id: item.id)

        XCTAssertEqual(settled.status, .pending)
        XCTAssertEqual(settled.attempts.last?.status, .timedOut)
        XCTAssertNil(settled.lease)
    }

    func testDraftItemIsSubmittedBeforeRun() async throws {
        let executor = makeExecutor(scripts: ["claude": .init(stdout: "ok", exitCode: 0)])
        let draft = try executor.service.add(.init(prompt: "Draft run", workerToken: "claude"))

        let settled = try await executor.run(id: draft.id)

        XCTAssertEqual(settled.status, .done)
        XCTAssertNotNil(settled.submittedAt)
    }

    func testUnsupportedTeamRunKindIsRejected() async throws {
        let executor = makeExecutor(scripts: [:])
        let item = try executor.service.add(.init(prompt: "Team", kind: .teamRun, workerToken: "claude", submit: true))

        do {
            _ = try await executor.run(id: item.id)
            XCTFail("expected unsupportedKind")
        } catch let error as PendingServiceError {
            XCTAssertEqual(error, .unsupportedKind("teamRun"))
        }
    }

    func testDispatchKindIsMutationDeferred() async throws {
        let executor = makeExecutor(scripts: [:])
        let item = try executor.service.add(.init(prompt: "Dispatch", kind: .dispatch, workerToken: "claude", submit: true))

        do {
            _ = try await executor.run(id: item.id)
            XCTFail("expected mutationDeferred")
        } catch let error as PendingServiceError {
            XCTAssertEqual(error, .mutationDeferred)
        }
    }

    func testCodexJSONLUsageLimitInStdout() async throws {
        let stdout = #"{"type":"error","message":"usage_limit_reached","resetsAt":"2026-06-19T12:00:00Z"}"#
        let executor = makeExecutor(scripts: ["codex": .init(stdout: stdout, exitCode: 1)])
        let item = try executor.service.add(.init(prompt: "Codex limit", workerToken: "codex", submit: true))

        let settled = try await executor.run(id: item.id)

        XCTAssertEqual(settled.status, .pending)
        XCTAssertEqual(settled.resume?.reason, .cooldown)
        XCTAssertEqual(settled.resume?.capacityObservation?.kind, .accountRateLimit)
    }

    private func jsonBlob<T: Encodable>(_ value: T) -> String {
        String(decoding: (try? CoreJSON.encode(value)) ?? Data(), as: UTF8.self)
    }
}
