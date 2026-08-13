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

    func testPaidPlanNeverIncrements() async {
        let store = MemoryEntitlementStore()
        let gate = makeGate(
            store: store,
            transport: StubTransport.status(plan: "monthly", paid: true, trialStartedAt: day0),
            isTestHost: false
        )
        let first = await gate.admitDispatch()
        let second = await gate.admitDispatch()
        XCTAssertEqual(first, .admit)
        XCTAssertEqual(second, .admit)
        XCTAssertEqual(store.state?.runsUsedToday, 0)
        XCTAssertEqual(store.state?.plan, .monthly)
    }

    func testTrialAdmitsWithoutIncrement() async {
        let store = MemoryEntitlementStore()
        let gate = makeGate(
            store: store,
            transport: StubTransport.status(
                plan: "trial",
                paid: false,
                trialStartedAt: day0,
                trialEndsAt: day0.addingTimeInterval(14 * 86400)
            ),
            isTestHost: false
        )
        let decision = await gate.admitDispatch()
        XCTAssertEqual(decision, .admit)
        XCTAssertEqual(store.state?.runsUsedToday, 0)
        XCTAssertEqual(store.state?.plan, .trial)
    }

    func testFreeTierCapsAtThree() async {
        let store = MemoryEntitlementStore()
        let started = day0.addingTimeInterval(-20 * 86400)
        let gate = makeGate(
            store: store,
            transport: StubTransport.status(plan: "free", paid: false, trialStartedAt: started),
            isTestHost: false
        )
        let one = await gate.admitDispatch()
        let two = await gate.admitDispatch()
        let three = await gate.admitDispatch()
        let four = await gate.admitDispatch()
        XCTAssertEqual(one, .admit)
        XCTAssertEqual(two, .admit)
        XCTAssertEqual(three, .admit)
        XCTAssertEqual(four, .refuse(.dailyCap))
        XCTAssertEqual(store.state?.runsUsedToday, 3)
    }

    func testReinstallDoesNotMintNewTrialWhenServerHasOldStart() async {
        let store = MemoryEntitlementStore()
        let started = day0.addingTimeInterval(-20 * 86400)
        let gate = makeGate(
            store: store,
            transport: StubTransport.status(plan: "free", paid: false, trialStartedAt: started),
            isTestHost: false
        )
        let decision = await gate.admitDispatch()
        XCTAssertEqual(decision, .admit)
        XCTAssertEqual(store.state?.plan, .free)
        XCTAssertEqual(store.state?.serverTrialStartedAt, started)
        XCTAssertNotEqual(store.state?.plan, .trial)
    }

    func testOfflineGraceThenLocalThreePerDay() async {
        let store = MemoryEntitlementStore()
        let clock = Clock(now: day0)
        let gate = makeGate(
            clock: { clock.now },
            store: store,
            transport: StubTransport.down(),
            isTestHost: false
        )
        let duringGrace = await gate.admitDispatch()
        XCTAssertEqual(duringGrace, .admit)
        XCTAssertEqual(store.state?.plan, .trial)

        clock.now = day0.addingTimeInterval(EntitlementPolicy.offlineGraceHours * 3600 + 1)
        let afterGrace = makeGate(
            clock: { clock.now },
            store: store,
            transport: StubTransport.down(),
            isTestHost: false
        )
        let after = await afterGrace.admitDispatch()
        XCTAssertEqual(after, .admit)
        XCTAssertEqual(store.state?.plan, .free)
        XCTAssertEqual(store.state?.runsUsedToday, 1)
    }

    func testClockRollbackForcesRefresh() async {
        let store = MemoryEntitlementStore()
        let clock = Clock(now: day0)
        let firstGate = makeGate(
            clock: { clock.now },
            store: store,
            transport: StubTransport.status(plan: "monthly", paid: true, trialStartedAt: day0),
            isTestHost: false
        )
        let first = await firstGate.admitDispatch()
        XCTAssertEqual(first, .admit)
        XCTAssertEqual(store.state?.plan, .monthly)

        clock.now = day0.addingTimeInterval(-3600)
        let issued = day0
        let calls = CallCounter()
        let rolled = makeGate(
            clock: { clock.now },
            store: store,
            transport: StubTransport { path, _ in
                calls.value += 1
                XCTAssertEqual(path, "v1/status")
                return StubTransport.statusPayload(plan: "monthly", paid: true, trialStartedAt: issued)
            },
            isTestHost: false
        )
        let second = await rolled.admitDispatch()
        XCTAssertEqual(second, .admit)
        XCTAssertEqual(calls.value, 1, "local clock earlier than issuedAt must force refresh")
    }

    func testCheckoutReturnsUrlAndCompiledCommand() async {
        let gate = makeGate(
            transport: StubTransport { _, _ in
                let body = try JSONSerialization.data(withJSONObject: [
                    "url": "https://checkout.stripe.com/c/pay/cs_test_123"
                ])
                return (200, body)
            },
            isTestHost: false
        )
        let result = await gate.checkoutJSON(plan: .monthly)
        guard case .success(let json) = result else {
            return XCTFail("expected checkout url")
        }
        XCTAssertEqual(json.url, "https://checkout.stripe.com/c/pay/cs_test_123")
        XCTAssertEqual(json.checkoutCommand, EntitlementPolicy.checkoutCommand)
        XCTAssertFalse(json.checkoutCommand.contains("stripe.com"))
        XCTAssertEqual(EntitlementLimitNextAction.agent.command, EntitlementPolicy.checkoutCommand)
    }

    func testInnerDispatchSkipDoesNotCount() async {
        let store = MemoryEntitlementStore()
        let started = day0.addingTimeInterval(-20 * 86400)
        let gate = makeGate(
            store: store,
            transport: StubTransport.status(plan: "free", paid: false, trialStartedAt: started),
            isTestHost: false
        )
        let outer = await gate.admitDispatch()
        XCTAssertEqual(outer, .admit)
        await EntitlementAdmission.skippingInner {
            let innerOne = await gate.admitDispatch()
            let innerTwo = await gate.admitDispatch()
            XCTAssertEqual(innerOne, .admit)
            XCTAssertEqual(innerTwo, .admit)
        }
        XCTAssertEqual(store.state?.runsUsedToday, 1)
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

private final class Clock: @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

private final class CallCounter: @unchecked Sendable {
    var value = 0
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
