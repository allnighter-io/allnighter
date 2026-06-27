import XCTest
@testable import AllnighterCore

final class SliceGateTests: XCTestCase {
    private let runnable = SliceGate.ExecutorFacts(
        teamId: "execution_playbook", exists: true, isMutating: true, isRunnable: true, workerCount: 1)

    private func packet(danger: [String] = [], allowlist: [String] = ["a.swift"]) -> WorkSlicePacket {
        .init(
            sliceId: "S1",
            intent: "do work",
            touchAllowlist: allowlist,
            check: .init(method: .command, command: "true"),
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
}
