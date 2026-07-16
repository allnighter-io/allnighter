import XCTest
import AllnighterCore

final class CommitMessageFidelityTests: XCTestCase {
    func testMatchedComparesNewestSubjectTrailingWhitespaceOnly() {
        let delta = RepoDelta(
            changed: true, baseline: "a", head: "b",
            commits: [.init(sha: "bbb", subject: "feat: ship it  ")],
            filesChanged: 1, files: ["x.swift"])
        XCTAssertTrue(CommitMessageFidelity.matched(requested: "feat: ship it", delta: delta)!)
        XCTAssertTrue(CommitMessageFidelity.matched(requested: "feat: ship it   ", delta: delta)!)
    }

    func testMismatchWhenSubjectDiffers() {
        let delta = RepoDelta(
            changed: true, baseline: "a", head: "b",
            commits: [.init(sha: "bbb", subject: "feat: reworded")],
            filesChanged: 1, files: ["x.swift"])
        XCTAssertFalse(CommitMessageFidelity.matched(requested: "feat: ship it", delta: delta)!)
    }

    func testNilWhenNoRequest() {
        XCTAssertNil(CommitMessageFidelity.matched(requested: "", delta: nil))
    }
}
