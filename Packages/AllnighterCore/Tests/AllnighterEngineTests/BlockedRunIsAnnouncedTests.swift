import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// A run blocked behind another run's write lock must SAY SO.
///
/// It used to wait up to `writeLockWaitTimeout` (1800s) in total silence and then
/// fail. The facts were already recorded — `recordBlockerTicket` writes the holder,
/// the hold duration and the queue position into the journal — but nobody told the
/// person waiting. That is the same defect as "Allnighter isn't open": something
/// knowable is true and the caller is left to guess.
///
/// One-Running-per-lane is not weakened by any of this. Exactly one mutating run
/// still executes at a time; only the silence is gone.
final class BlockedRunIsAnnouncedTests: XCTestCase {

    private func ticket(position: Int, heldSeconds: Double, holderId: String) -> ExecutionLaneTicket {
        ExecutionLaneTicket(
            position: position,
            holder: .init(
                identity: ProcessOwnerRecord(
                    pid: 4321, pgid: nil, startTimeTicks: 7, kind: "inProcess"),
                kind: "mutatingRun",
                id: holderId),
            heldSinceSeconds: heldSeconds)
    }

    func testTheNoticeNamesTheHolderTheWaitAndThePosition() {
        let notice = RunService.blockedNotice(
            ticket: ticket(position: 2, heldSeconds: 91.4, holderId: "run_ABC"),
            root: "/Users/me/Code/thing")

        XCTAssertTrue(notice.contains("run_ABC"), "the caller must be able to find the holder")
        XCTAssertTrue(notice.contains("mutatingRun"))
        XCTAssertTrue(notice.contains("4321"), "a pid makes it actionable with `alln ps`")
        XCTAssertTrue(notice.contains("91s"), "how long it has been held is the deciding fact")
        XCTAssertTrue(notice.contains("#2"), "position in line")
        XCTAssertTrue(notice.contains("/Users/me/Code/thing"))
    }

    /// The point of the notice is that the human chooses. It must offer the exit and
    /// must not imply the tool is doing something clever on their behalf.
    func testTheNoticeHandsTheDecisionToTheHuman() {
        let notice = RunService.blockedNotice(
            ticket: ticket(position: 1, heldSeconds: 5, holderId: "run_X"), root: "/repo")

        XCTAssertTrue(notice.contains("Ctrl-C"), "waiting must be escapable and said to be")
        XCTAssertTrue(notice.contains("read-only runs never queue"),
                      "most work is unaffected and the caller should know it")
        for guess in ["probably", "should finish", "try again later", "stuck"] {
            XCTAssertFalse(notice.lowercased().contains(guess),
                           "the notice states observed facts, it does not speculate: \(guess)")
        }
    }
}
