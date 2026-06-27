import XCTest
@testable import AllnighterCore

final class ReviewVerifyPromptTests: XCTestCase {
    func testAssemblesVerifyOrder() {
        let packet = WorkSlicePacket(
            sliceId: "CR-01-verify",
            title: "Verify RunWriteLock",
            intent: "Default P0 to reject.",
            touchAllowlist: ["docs/phases/code_review/findings/CR-01-verified.md"],
            check: .init(method: .command, command: "true"),
            mode: .reviewVerify,
            inlinedSources: [
                .init(path: "RunWriteLock.swift", content: "public actor RunWriteLockRegistry {}")
            ],
            inlinedFindings: "### P0 — test\nclaim"
        )
        let prompt = ReviewVerifyPrompt.assemble(packet: packet)
        XCTAssertTrue(prompt.contains("ADVERSARIAL VERIFY"))
        XCTAssertTrue(prompt.contains("Default every **P0**"))
        XCTAssertTrue(prompt.contains("### P0 — test"))
        XCTAssertTrue(prompt.contains("RunWriteLockRegistry"))
        XCTAssertTrue(prompt.contains("CR-01-verified.md"))
    }
}
