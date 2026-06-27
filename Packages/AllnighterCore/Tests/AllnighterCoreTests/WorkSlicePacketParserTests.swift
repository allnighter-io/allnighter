import XCTest
@testable import AllnighterCore

final class WorkSlicePacketParserTests: XCTestCase {
    private let markdown = """
    # OC-S02b

    ```work-slice-packet
    {
      "sliceId": "OC-S02b",
      "title": "Strip reasoning blocks",
      "readPaths": [{"path": "Packages/AllnighterCore/Sources/AllnighterEngine/TextUtil.swift"}],
      "resolvedSymbols": [{"name": "stripReasoningBlocks", "signature": "static func stripReasoningBlocks(_ text: String) -> String", "definedAt": "TextUtil.swift:42"}],
      "intent": "Ensure reasoning blocks are stripped from OpenCode output.",
      "touchAllowlist": ["Packages/AllnighterCore/Sources/AllnighterEngine/TextUtil.swift"],
      "check": {"method": "command", "command": "swift test --package-path Packages/AllnighterCore --filter OpenCodeVisibleText"},
      "dangerFlags": []
    }
    ```
    """

    func testParsesFencedBlock() {
        let packet = try? XCTUnwrap(WorkSlicePacketParser.parse(fromMarkdown: markdown))
        XCTAssertEqual(packet?.sliceId, "OC-S02b")
        XCTAssertEqual(packet?.touchAllowlist.count, 1)
        XCTAssertEqual(packet?.check.method, .command)
        XCTAssertEqual(packet?.maxRetries, 2)
    }

    func testParsesJSONFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wsp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("slice.json")
        try Data("""
        {"sliceId":"PPT-S01","intent":"x","touchAllowlist":["a.swift"],"check":{"method":"command","command":"true"}}
        """.utf8).write(to: path)
        let packet = try WorkSlicePacketParser.parseFile(at: path.path)
        XCTAssertEqual(packet.sliceId, "PPT-S01")
    }
}
