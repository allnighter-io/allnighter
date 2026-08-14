import XCTest
@testable import AllnighterMac
import AllnighterCore

@MainActor
final class AskAIModelTests: XCTestCase {
    func testCanAskRequiresNonEmptyDraftAndIdle() {
        let model = AskAIModel()
        XCTAssertFalse(model.canAsk)
        model.draft = "   "
        XCTAssertFalse(model.canAsk)
        model.draft = "Where is Boost?"
        XCTAssertTrue(model.canAsk)
        model.phase = .running
        XCTAssertFalse(model.canAsk)
    }

    func testSupportMailtoIsTheLegalHatch() {
        XCTAssertEqual(AskAIPrompt.supportEmail, "support@allnighter.io")
        XCTAssertEqual(AskAIPrompt.supportMailto.scheme, "mailto")
    }
}
