import XCTest
@testable import AllnighterCore

final class SliceGateTests: XCTestCase {
    private let runnable = SliceGate.ExecutorFacts(
        teamId: "execution_playbook", exists: true, isMutating: true, isRunnable: true, workerCount: 1)

    private func packet(
        danger: [String] = [],
        allowlist: [String] = ["a.swift"],
        check: WorkSlicePacket.Check = .init(method: .command, command: "true")
    ) -> WorkSlicePacket {
        .init(
            sliceId: "S1",
            intent: "do work",
            touchAllowlist: allowlist,
            check: check,
            dangerFlags: danger
        )
    }

    func testAllowsRunnablePacket() {
        XCTAssertEqual(SliceGate.evaluate(packet: packet(), executor: runnable), .allowed)
    }

    func testBlocksDanger() {
        let decision = SliceGate.evaluate(packet: packet(danger: ["credentials"]), executor: runnable)
        XCTAssertEqual(decision, .blocked(code: "PAIR_SLICE_UNSAFE", reason: "danger flag(s): credentials"))
    }

    func testBlocksEmptyAllowlist() {
        let decision = SliceGate.evaluate(packet: packet(allowlist: []), executor: runnable)
        XCTAssertTrue(decision.isAllowed == false)
    }

    func testBlocksEmptyAllowlistEntry() {
        let decision = SliceGate.evaluate(packet: packet(allowlist: [""]), executor: runnable)
        XCTAssertEqual(
            decision,
            .blocked(code: "PAIR_SLICE_UNSAFE", reason: "touchAllowlist is required for mutating units"))
    }

    func testBlocksWhitespaceOnlyAllowlistEntries() {
        let decision = SliceGate.evaluate(packet: packet(allowlist: ["   ", "\t"]), executor: runnable)
        XCTAssertEqual(
            decision,
            .blocked(code: "PAIR_SLICE_UNSAFE", reason: "touchAllowlist is required for mutating units"))
    }

    func testBlocksUnknownCheckMethod() {
        let decision = SliceGate.decisionForCheckMethod(rawValue: "manual", command: nil, fixture: nil)
        XCTAssertEqual(decision, .blocked(code: "PAIR_SLICE_UNSAFE", reason: "unsupported check.method: manual"))
    }

    func testAllowsUserObservationCheckMethod() {
        let decision = SliceGate.evaluate(
            packet: packet(check: .init(method: .userObservation)),
            executor: runnable)
        XCTAssertEqual(decision, .allowed)
    }
}
