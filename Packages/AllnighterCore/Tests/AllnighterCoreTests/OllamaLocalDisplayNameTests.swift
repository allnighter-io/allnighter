import XCTest
@testable import AllnighterCore

final class OllamaLocalDisplayNameTests: XCTestCase {
    func testDerivesReadableTitleFromCommonTags() {
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "gpt-oss:20b"), "GPT-OSS 20B")
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "qwen3:8b"), "Qwen3 8B")
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "qwen3.8:27b-mlx"), "Qwen3.8 27B")
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "qwen2.5-coder:7b"), "Qwen2.5 Coder 7B")
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "qwen2.5-coder:1.5b"), "Qwen2.5 Coder 1.5B")
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "llama3.1:8b"), "Llama3.1 8B")
    }

    func testEmptyTagStaysEmpty() {
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: ""), "")
        XCTAssertEqual(OllamaLocalDisplayName.from(tag: "  "), "")
    }
}
