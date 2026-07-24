import XCTest
@testable import AllnighterEngine

final class ResidentCoordinatorProcessReaperTests: XCTestCase {
    func testSelectsOnlyExtraServeProcessesAndPreservesHealthyPID() {
        let rows = """
        100 /Users/me/.local/bin/alln serve
        101 /repo/.build/debug/alln serve
        102 /Users/me/.local/bin/alln serve install
        103 /usr/bin/other
        """
        XCTAssertEqual(
            ResidentCoordinatorProcessReaper.candidates(lines: rows, preserving: 100),
            [.init(pid: 101, command: "/repo/.build/debug/alln serve")]
        )
    }
}
