import XCTest
import AllnighterCore

final class NudgePromptTests: XCTestCase {
    private let packet = WorkSlicePacket(
        sliceId: "B1a",
        intent: "fix it",
        touchAllowlist: ["a.mjs"],
        check: .init(method: .command, command: "npm test")
    )

    func testFailureRetryFirstAttemptIsLight() {
        let nudge = NudgePrompt.failureRetry(
            packet: packet,
            attempt: 1,
            maxAttempts: 3,
            reason: "repo check failed (exit 1)",
            checkStdoutTail: "assertion failed",
            stdoutTail: nil
        )
        XCTAssertTrue(nudge.contains("attempt 1/3"))
        XCTAssertTrue(nudge.contains("repo check failed"))
        XCTAssertFalse(nudge.contains("assertion failed"))
    }

    func testFailureRetrySecondAttemptIncludesCheckOutput() {
        let nudge = NudgePrompt.failureRetry(
            packet: packet,
            attempt: 2,
            maxAttempts: 3,
            reason: "repo check failed (exit 1)",
            checkStdoutTail: "assertion failed",
            stdoutTail: nil
        )
        XCTAssertTrue(nudge.contains("Prior attempts failed"))
        XCTAssertTrue(nudge.contains("assertion failed"))
    }
}
