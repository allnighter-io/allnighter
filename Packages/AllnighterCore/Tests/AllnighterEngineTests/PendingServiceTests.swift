import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class PendingServiceTests: XCTestCase {
    private let models = [
        Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both),
        Model(id: "model_codex", displayName: "Codex", modelLabel: "gpt", driverId: "codex", role: .answerer),
    ]

    private var root: URL!
    private var service: PendingService!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pending-\(UUID().uuidString)", isDirectory: true)
        let now = fixedNow
        service = PendingService(
            store: PendingStore(rootDirectory: root),
            models: models,
            idFactory: { "pending_test_\(UUID().uuidString.prefix(8))" },
            now: { now }
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddCreatesDraftWithWorkerAlias() throws {
        let item = try service.add(.init(prompt: "Review this patch when Claude is ready.", workerToken: "claude"))
        XCTAssertEqual(item.status, .draft)
        XCTAssertEqual(item.target.preferredWorkerIds, ["model_opus"])
        XCTAssertEqual(item.execution?.intent, .ask)
        let json = try service.mapJSON(item)
        XCTAssertEqual(json.pendingItem.status, .draft)
        XCTAssertNil(json.admission)
        XCTAssertFalse(jsonBlob(json).lowercased().contains("quota"))
        XCTAssertFalse(jsonBlob(json).lowercased().contains("estimated"))
    }

    func testSubmitAndAddWithSubmitFlag() throws {
        let draft = try service.add(.init(prompt: "First", workerToken: "claude"))
        let pending = try service.submit(id: draft.id)
        XCTAssertEqual(pending.status, .pending)
        XCTAssertNotNil(pending.submittedAt)

        let direct = try service.add(.init(prompt: "Continue security review.", workerToken: "claude", submit: true))
        XCTAssertEqual(direct.status, .pending)
    }

    func testReorderPreservesLifecycleStatus() throws {
        let first = try service.add(.init(prompt: "A", workerToken: "claude", submit: true))
        let second = try service.add(.init(prompt: "B", workerToken: "claude", submit: true))
        _ = try service.reorder(id: second.id, anchor: .before(first.id))
        let order = try service.list().map(\.id)
        XCTAssertEqual(order, [second.id, first.id])
        XCTAssertEqual(try service.store.load(id: first.id)?.status, .pending)
        XCTAssertEqual(try service.store.load(id: second.id)?.status, .pending)
    }

    func testCancelMarksCancelled() throws {
        let item = try service.add(.init(prompt: "Cancel me", workerToken: "claude", submit: true))
        let cancelled = try service.cancel(id: item.id)
        XCTAssertEqual(cancelled.status, .cancelled)
    }

    func testPersistenceAcrossStoreReopen() throws {
        _ = try service.add(.init(prompt: "One", workerToken: "claude", submit: true, threadId: "thread_a"))
        _ = try service.add(.init(prompt: "Two", workerToken: "codex", submit: true, threadId: "thread_a"))
        _ = try service.add(.init(prompt: "Three", workerToken: "claude", threadId: "thread_a"))

        let now = fixedNow
        let reopened = PendingService(store: PendingStore(rootDirectory: root), models: models, now: { now })
        let items = try reopened.list()
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter { $0.threadId == "thread_a" }.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
    }

    func testEditPendingReturnsToDraftAndClearsLease() throws {
        var item = try service.add(.init(prompt: "Edit me", workerToken: "claude", submit: true))
        item.lease = PendingLease(leaseId: "lease_test", owner: .cli, leasedAt: fixedNow)
        item.resume = PendingResume(reason: .cooldown, wakeAfter: fixedNow.addingTimeInterval(3600))
        try service.store.save(item)

        item = try service.edit(id: item.id, .init(prompt: "Edited prompt"))
        XCTAssertEqual(item.status, .draft)
        XCTAssertNil(item.lease)
        XCTAssertNil(item.resume)
        XCTAssertNil(item.submittedAt)
        XCTAssertEqual(item.prompt, "Edited prompt")
    }

    func testManualRunRecordsQueuedAttempt() throws {
        let item = try service.add(.init(prompt: "Run me", workerToken: "claude", submit: true))
        let running = try service.run(id: item.id)
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(running.attempts.count, 1)
        XCTAssertEqual(running.attempts.last?.status, .queued)
        XCTAssertEqual(running.attempts.last?.reason, "manualRunAwaitingAdmission")
    }

    func testListJSONProjection() throws {
        _ = try service.add(.init(prompt: "Listed", workerToken: "claude", submit: true))
        let items = try service.list().map { try service.mapJSON($0) }
        let list = PendingListJSON(contractVersion: ContractRegistry.contractVersion, items: items)
        let blob = jsonBlob(list)
        XCTAssertFalse(blob.lowercased().contains("runtime"))
        XCTAssertFalse(blob.lowercased().contains("token"))
    }

    func testCapacityObservationProjectsThroughPendingJSON() throws {
        let resetAt = fixedNow.addingTimeInterval(9_900)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "You've been rate limited",
            observedAt: fixedNow,
            observedResetAt: resetAt,
            retryAfterSeconds: 9_900,
            wakeAfter: resetAt
        )
        var item = try service.add(.init(prompt: "Cooling", workerToken: "claude", submit: true))
        item.resume = PendingResume(
            reason: .cooldown,
            observedResetAt: resetAt,
            wakeAfter: resetAt,
            capacityObservation: observation
        )
        try service.store.save(item)

        let json = try service.mapJSON(item)
        XCTAssertNotNil(json.capacityObservation)
        XCTAssertEqual(json.capacityObservation?.kind, "accountRateLimit")
        XCTAssertEqual(json.capacityObservation?.source, "claude_code")
        XCTAssertEqual(json.capacityObservation?.sourceConfidence, "structured")
        XCTAssertEqual(json.capacityObservation?.retryAfterSeconds, 9_900)
        XCTAssertNotNil(json.pendingItem.nextWakeAt)
        let blob = jsonBlob(json).lowercased()
        XCTAssertFalse(blob.contains("quota"))
        XCTAssertFalse(blob.contains("estimated"))
    }

    private func jsonBlob<T: Encodable>(_ value: T) -> String {
        String(decoding: (try? CoreJSON.encode(value)) ?? Data(), as: UTF8.self)
    }
}

final class PendingItemJSONFixtureTests: XCTestCase {
    func testFixtureRoundTrips() throws {
        let decoded = try Fixtures.pendingItemJSON()
        let reEncoded = try CoreJSON.encode(decoded)
        let back = try CoreJSON.decode(PendingItemJSON.self, from: reEncoded)
        XCTAssertEqual(decoded, back)
    }

    func testPendingSchemaMatchesFixtureTopLevel() throws {
        let item = try Fixtures.pendingItemJSON()
        let schema = ContractSchema.pendingItemSchema()
        let dict = try XCTUnwrap(schema["properties"] as? [String: Any])
        let props = Set(dict.keys)
        let labels = Set(Mirror(reflecting: item).children.compactMap(\.label))
        XCTAssertEqual(props, labels)
    }

    func testCoolingFixtureHasCapacityObservationWithoutForecastFields() throws {
        let item = try Fixtures.pendingItemCoolingJSON()
        let obs = try XCTUnwrap(item.capacityObservation)
        XCTAssertEqual(obs.kind, "accountRateLimit")
        XCTAssertNotNil(obs.observedResetAt)
        let blob = String(decoding: try CoreJSON.encode(item), as: UTF8.self).lowercased()
        XCTAssertFalse(blob.contains("quota"))
        XCTAssertFalse(blob.contains("cost"))
        XCTAssertFalse(blob.contains("runtime"))
    }
}
