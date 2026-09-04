import XCTest
@testable import AllnighterCore

final class EntitlementGateTests: XCTestCase {
    private let day0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testMachineHashIsNotRawUUID() {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let hash = PlatformMachineIdentity.hash(uuid)
        XCTAssertEqual(hash.count, 64)
        XCTAssertFalse(hash.lowercased().contains("a1b2c3d4"))
        XCTAssertNotEqual(hash, uuid)
        XCTAssertEqual(hash, PlatformMachineIdentity.hash(uuid), "hash must be deterministic")
    }

    func testProductIsFreeForeverAlwaysAdmits() async {
        let store = MemoryEntitlementStore()
        let started = day0.addingTimeInterval(-20 * 86400)
        let gate = makeGate(
            store: store,
            transport: StubTransport.status(plan: "free", paid: false, trialStartedAt: started),
            isTestHost: false
        )
        for _ in 0..<10 {
            let decision = await gate.admitDispatch()
            XCTAssertEqual(decision, .admit)
        }
        XCTAssertNil(store.state, "free-forever path must not persist counters")
    }

    func testProductIsFreeForeverOmitsMenuEntitlement() {
        let gate = makeGate(isTestHost: false)
        XCTAssertNil(gate.menuProjection())
    }

    func testProductIsFreeForeverStatusJSON() async {
        let gate = makeGate(isTestHost: false)
        let json = await gate.statusJSON()
        XCTAssertEqual(json.plan, "free")
        XCTAssertFalse(json.paid)
        XCTAssertNil(json.runsUsedToday)
        XCTAssertNil(json.runsAllowedToday)
        XCTAssertNil(json.trialEndsAt)
        XCTAssertEqual(json.message, "Allnighter is free. No trial or daily run limit.")
    }

    func testProductIsFreeForeverCheckoutRefused() async {
        let gate = makeGate(isTestHost: false)
        let result = await gate.checkoutJSON(plan: .monthly)
        guard case .failure(let refusal) = result else {
            return XCTFail("expected checkout refusal")
        }
        XCTAssertEqual(refusal.message, "Allnighter is free — no checkout needed.")
    }

    func testTestHostSkipsAndAdmits() async {
        let gate = makeGate(isTestHost: true)
        let decision = await gate.admitDispatch()
        XCTAssertEqual(decision, .admit)
        XCTAssertNil(gate.menuProjection())
    }

    func testSkipEnvAdmitsWithoutCounting() async {
        let store = MemoryEntitlementStore()
        let gate = makeGate(store: store, env: [EntitlementPolicy.skipEnvKey: "1"], isTestHost: false)
        let first = await gate.admitDispatch()
        let second = await gate.admitDispatch()
        XCTAssertEqual(first, .admit)
        XCTAssertEqual(second, .admit)
        XCTAssertNil(store.state, "skip path must not persist a trial")
    }

    func testInnerDispatchSkipDoesNotCount() async {
        let store = MemoryEntitlementStore()
        let gate = makeGate(store: store, isTestHost: false)
        let outer = await gate.admitDispatch()
        XCTAssertEqual(outer, .admit)
        await EntitlementAdmission.skippingInner {
            let innerOne = await gate.admitDispatch()
            let innerTwo = await gate.admitDispatch()
            XCTAssertEqual(innerOne, .admit)
            XCTAssertEqual(innerTwo, .admit)
        }
    }

    // MARK: - helpers

    private func makeGate(
        clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) },
        store: MemoryEntitlementStore = MemoryEntitlementStore(),
        transport: any EntitlementTransport = StubTransport.down(),
        env: [String: String] = [:],
        isTestHost: Bool
    ) -> EntitlementGate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return EntitlementGate(
            clock: clock,
            calendar: calendar,
            identity: FixedIdentity(value: "abc123"),
            transport: transport,
            store: store,
            isTestHost: isTestHost,
            env: env
        )
    }
}

private struct FixedIdentity: MachineIdentity {
    let value: String
    func machineHash() -> String { value }
}

private final class MemoryEntitlementStore: EntitlementStoring, @unchecked Sendable {
    var state: EntitlementState?
    func load() -> EntitlementState? { state }
    func save(_ state: EntitlementState) { self.state = state }
}

private struct StubTransport: EntitlementTransport {
    let handler: @Sendable (String, Data) async throws -> (Int, Data)

    func post(path: String, json: Data) async throws -> (status: Int, body: Data) {
        try await handler(path, json)
    }

    static func down() -> StubTransport {
        StubTransport { _, _ in throw URLError(.timedOut) }
    }

    static func status(
        plan: String,
        paid: Bool,
        trialStartedAt: Date,
        trialEndsAt: Date? = nil
    ) -> StubTransport {
        StubTransport { _, _ in
            statusPayload(plan: plan, paid: paid, trialStartedAt: trialStartedAt, trialEndsAt: trialEndsAt)
        }
    }

    static func statusPayload(
        plan: String,
        paid: Bool,
        trialStartedAt: Date,
        trialEndsAt: Date? = nil
    ) -> (Int, Data) {
        var obj: [String: Any] = [
            "plan": plan,
            "paid": paid,
            "trialStartedAt": trialStartedAt.timeIntervalSince1970 * 1000,
        ]
        if let trialEndsAt {
            obj["trialEndsAt"] = trialEndsAt.timeIntervalSince1970 * 1000
        }
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return (200, data)
    }
}
