import XCTest
@testable import AllnighterCore

final class ThreadAgentPresentationTests: XCTestCase {
    func testPlainChatSingleLine() {
        let label = ThreadAgentPresentation.make(
            threadId: "thread_1",
            turnId: "turn_1",
            modelId: "model_opus",
            modelDisplayName: "Opus 5",
            driverId: "claude_code"
        )
        XCTAssertEqual(label.primary, "Agent · Opus 5")
        XCTAssertEqual(label.driverId, "claude_code")
    }

    func testPlainChatFallsBackToModelId() {
        let label = ThreadAgentPresentation.make(
            threadId: "thread_1",
            turnId: "turn_1",
            modelId: "model_opus",
            modelDisplayName: nil,
            driverId: nil
        )
        XCTAssertEqual(label.primary, "Agent · model_opus")
        XCTAssertNil(label.driverId)
    }

    func testPlainChatUnknownWhenNoIdentity() {
        let label = ThreadAgentPresentation.make(
            threadId: "thread_1",
            turnId: "turn_1",
            modelId: nil,
            modelDisplayName: nil,
            driverId: nil
        )
        XCTAssertEqual(label.primary, "Agent · unknown")
    }

    func testRelaySingleLineDevSeat() {
        let label = ThreadAgentPresentation.make(
            threadId: "relay_abc",
            turnId: "relay_abc_dev5",
            modelId: "model_grok",
            modelDisplayName: "Grok Build",
            driverId: "grok"
        )
        XCTAssertEqual(label.primary, "Dev · Grok Build")
        XCTAssertEqual(label.driverId, "grok")
    }

    func testRelaySingleLinePMSeat() {
        let label = ThreadAgentPresentation.make(
            threadId: "relay_abc",
            turnId: "relay_abc_pm3",
            modelId: "model_opus",
            modelDisplayName: "Opus 5",
            driverId: "claude_code"
        )
        XCTAssertEqual(label.primary, "PM · Opus 5")
    }

    func testRelaySeatDetection() {
        XCTAssertEqual(ThreadAgentPresentation.relaySeat(threadId: "relay_x", turnId: "relay_x_pm1"), .pm)
        XCTAssertEqual(ThreadAgentPresentation.relaySeat(threadId: "relay_x", turnId: "relay_x_dev12"), .dev)
        XCTAssertNil(ThreadAgentPresentation.relaySeat(threadId: "thread_x", turnId: "turn_1"))
        XCTAssertNil(ThreadAgentPresentation.relaySeat(threadId: "relay_x", turnId: "relay_x_escalate1"))
    }
}
