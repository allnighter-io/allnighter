import XCTest
@testable import AllnighterMac

/// RLS-P0: reasoning is audit/debug by default. A running (or latest) turn must NOT
/// auto-expand and render unbounded, growing reasoning text while the answer streams —
/// it stays collapsed to the compact "Thinking" header unless the user opens it.
final class ReasoningRenderPolicyTests: XCTestCase {

    func testRunningTurnDoesNotAutoExpandReasoning() {
        XCTAssertFalse(ReasoningRenderPolicy.expanded(userToggle: nil, isLatestTurn: false, isRunning: true),
                       "a running turn must not auto-render full reasoning")
    }

    func testLatestTurnDoesNotAutoExpandReasoning() {
        XCTAssertFalse(ReasoningRenderPolicy.expanded(userToggle: nil, isLatestTurn: true, isRunning: false),
                       "being the latest turn must not auto-expand reasoning")
    }

    func testExplicitToggleWins() {
        XCTAssertTrue(ReasoningRenderPolicy.expanded(userToggle: true, isLatestTurn: false, isRunning: true),
                      "an explicit open reveals reasoning even while running")
        XCTAssertFalse(ReasoningRenderPolicy.expanded(userToggle: false, isLatestTurn: true, isRunning: true),
                       "an explicit collapse stays collapsed")
    }
}
