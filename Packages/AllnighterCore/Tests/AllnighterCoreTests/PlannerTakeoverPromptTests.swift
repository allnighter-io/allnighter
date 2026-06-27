import XCTest
import AllnighterCore

final class PlannerTakeoverPromptTests: XCTestCase {
    func testAssembleIncludesFailureContext() {
        let packet = WorkSlicePacket(
            sliceId: "B1a",
            title: "R2 route lookup",
            intent: "Wire publish to R2",
            touchAllowlist: ["publish-service.mjs"],
            check: .init(method: .command, command: "npm test")
        )
        let prompt = PlannerTakeoverPrompt.assemble(
            packet: packet,
            context: .init(
                executorAttempts: 3,
                lastTerminal: "failed",
                checkExitCode: 1,
                checkStdoutTail: "expected true",
                lastWorkerOutput: "I edited the file"
            )
        )
        XCTAssertTrue(prompt.contains("Planner takeover"))
        XCTAssertTrue(prompt.contains("failed 3 times"))
        XCTAssertTrue(prompt.contains("publish-service.mjs"))
        XCTAssertTrue(prompt.contains("expected true"))
    }
}
