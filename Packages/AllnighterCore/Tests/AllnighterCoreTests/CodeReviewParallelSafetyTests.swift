import XCTest
@testable import AllnighterCore

final class CodeReviewParallelSafetyTests: XCTestCase {
    func testDisjointFindingsTouchesAreSafe() {
        let a = CodeReviewParallelSafety.PacketSurface(
            sliceId: "CR-01",
            touchAllowlist: ["docs/phases/code_review/findings/CR-01.md"]
        )
        let b = CodeReviewParallelSafety.PacketSurface(
            sliceId: "CR-02",
            touchAllowlist: ["docs/phases/code_review/findings/CR-02.md"]
        )
        XCTAssertTrue(CodeReviewParallelSafety.canRunConcurrently([a, b]))
        XCTAssertTrue(CodeReviewParallelSafety.violations([a, b]).isEmpty)
    }

    func testTouchOverlapIsUnsafe() {
        let path = "docs/phases/code_review/findings/CR-01.md"
        let a = CodeReviewParallelSafety.PacketSurface(sliceId: "CR-01", touchAllowlist: [path])
        let b = CodeReviewParallelSafety.PacketSurface(sliceId: "CR-01b", touchAllowlist: [path])
        XCTAssertFalse(CodeReviewParallelSafety.canRunConcurrently([a, b]))
    }

    func testTouchOutsideFindingsIsUnsafe() {
        let bad = CodeReviewParallelSafety.PacketSurface(
            sliceId: "CR-99",
            touchAllowlist: ["Packages/Foo.swift"]
        )
        XCTAssertFalse(bad.touchAllowlist.isEmpty)
        XCTAssertFalse(CodeReviewParallelSafety.canRunConcurrently([bad]))
    }

    func testSafeBatchesGreedyPacks() {
        let packets = (1...5).map { n in
            CodeReviewParallelSafety.PacketSurface(
                sliceId: String(format: "CR-%02d", n),
                touchAllowlist: ["docs/phases/code_review/findings/CR-\(String(format: "%02d", n)).md"]
            )
        }
        let batches = CodeReviewParallelSafety.safeBatches(packets, maxConcurrent: 4)
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].count, 4)
        XCTAssertEqual(batches[1].count, 1)
    }
}
