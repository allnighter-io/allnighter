import XCTest
import AllnighterCore
@testable import AllnighterMac

/// Bug list #4: the Floor card shows EXACTLY two composer-opening next moves, and never
/// Save-to-Pending / Draft / Run-when-ready.
final class FloorNextMovePresenterTests: XCTestCase {

    func testFloorCardShowsExactlyAskAnotherTeamAndContinueWithAuto() {
        let kinds = FloorNextMovePresenter.cardMoves.map(\.kind)
        XCTAssertEqual(kinds, [.askAnotherTeam, .continueWithAuto])
        XCTAssertEqual(FloorNextMovePresenter.cardMoves.first?.label, "Ask Another Team")
        XCTAssertEqual(FloorNextMovePresenter.cardMoves.last?.label, "Continue with Auto")
    }

    func testFloorCardNeverShowsSaveToPendingOrDrafts() {
        let kinds = Set(FloorNextMovePresenter.cardMoves.map(\.kind))
        for banned: FloorNextAction.Kind in [.savePending, .draftCopy, .sendTeam, .createCodeProposal, .createDesignBrief] {
            XCTAssertFalse(kinds.contains(banned), "\(banned) must not appear on the Floor card")
        }
    }
}
