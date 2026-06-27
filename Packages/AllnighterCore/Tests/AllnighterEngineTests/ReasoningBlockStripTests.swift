import XCTest
@testable import AllnighterEngine

final class ReasoningBlockStripTests: XCTestCase {
    func testSimpleInlineBlockRemoved() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("Hello <think>secret reasoning</think> world"),
            "Hello world")
    }
    func testMultilineBlockRemoved() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("Answer:\n<think>\nstep 1\nstep 2\n</think>\nDone"),
            "Answer:\n\nDone")
    }
    func testTwoBlocksKeepTextBetween() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("A<think>x</think>B<think>y</think>C"),
            "ABC")
    }
    func testNestedBlocksFullyRemoved() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("start<think>outer<think>inner</think>still outer</think>end"),
            "startend")
    }
    func testDanglingUnclosedBlockRemovedToEnd() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("visible<think>reasoning with no close"),
            "visible")
    }
    func testCaseInsensitiveThinkingVariant() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("p<THINKING>q</THINKING>r"),
            "pr")
    }
    func testExcessBlankLinesCollapsed() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("line1\n<think>r</think>\n\n\n\nline2"),
            "line1\n\nline2")
    }
    func testNoTagsJustTrims() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("  just text  "),
            "just text")
    }
    func testOnlyBlockYieldsEmpty() {
        XCTAssertEqual(
            TextUtil.stripReasoningBlocks("<think>everything</think>"),
            "")
    }
}
