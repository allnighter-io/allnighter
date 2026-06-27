import XCTest
@testable import AllnighterCore

final class ReviewAttemptPromptTests: XCTestCase {
    func testAssemblesInlinedReviewOrder() {
        let packet = WorkSlicePacket(
            sliceId: "CR-01",
            title: "RunWriteLock",
            intent: "Lens 1: two holders same root?",
            touchAllowlist: ["docs/phases/code_review/findings/CR-01.md"],
            check: .init(method: .command, command: "test -f docs/phases/code_review/findings/CR-01.md"),
            mode: .review,
            inlinedSources: [
                .init(path: "RunWriteLock.swift", content: "public actor RunWriteLockRegistry {}")
            ]
        )
        let prompt = ReviewAttemptPrompt.assemble(packet: packet)
        XCTAssertTrue(prompt.contains("Code review — CR-01"))
        XCTAssertTrue(prompt.contains("READ-ONLY advisory"))
        XCTAssertTrue(prompt.contains("RunWriteLockRegistry"))
        XCTAssertTrue(prompt.contains("Do **not** edit Swift"))
        XCTAssertTrue(prompt.contains("findings/CR-01.md"))
        XCTAssertFalse(prompt.contains("Skeleton"))
    }

    func testWorkSlicePacketReviewModeDecodes() throws {
        let json = """
        {"sliceId":"CR-02","mode":"review","intent":"x","touchAllowlist":["a.md"],
         "check":{"method":"command","command":"true"},
         "inlinedSources":[{"path":"f.swift","content":"let x = 1"}]}
        """
        let packet = try CoreJSON.decode(WorkSlicePacket.self, from: Data(json.utf8))
        XCTAssertTrue(packet.isReviewMode)
        XCTAssertEqual(packet.inlinedSources.count, 1)
    }
}
