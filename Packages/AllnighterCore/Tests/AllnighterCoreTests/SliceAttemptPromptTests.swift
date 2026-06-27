import XCTest
@testable import AllnighterCore

final class SliceAttemptPromptTests: XCTestCase {
    func testAssemblesReadBoundedOrder() {
        let packet = WorkSlicePacket(
            sliceId: "OC-S01a",
            title: "Extractor",
            readPaths: [.init(path: "TextUtil.swift", symbol: "extractOpenCodeVisibleText")],
            resolvedSymbols: [.init(name: "extractOpenCodeVisibleText", signature: "static func extractOpenCodeVisibleText(_:)", definedAt: "TextUtil.swift:10")],
            intent: "Strip metadata footer.",
            touchAllowlist: ["TextUtil.swift"],
            check: .init(method: .command, command: "swift test --filter OpenCodeVisibleText")
        )
        let prompt = SliceAttemptPrompt.assemble(packet: packet)
        XCTAssertTrue(prompt.contains("OC-S01a"))
        XCTAssertTrue(prompt.contains("Do not grep"))
        XCTAssertTrue(prompt.contains("TextUtil.swift"))
        XCTAssertTrue(prompt.contains("swift test --filter OpenCodeVisibleText"))
    }
}
