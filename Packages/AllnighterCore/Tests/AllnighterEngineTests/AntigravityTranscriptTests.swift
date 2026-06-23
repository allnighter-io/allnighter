import XCTest
@testable import AllnighterEngine

final class AntigravityTranscriptTests: XCTestCase {
    /// Multi-step run: the "I will X" PLANNER_RESPONSE steps become reasoning; the final
    /// PLANNER_RESPONSE is the clean answer.
    func testSplitsNarrationFromFinalAnswer() {
        let jsonl = """
        {"type":"USER_INPUT","content":"improve this page"}
        {"type":"PLANNER_RESPONSE","content":"I will list the contents of the Apps directory."}
        {"type":"LIST_DIRECTORY","content":"... tool output ..."}
        {"type":"PLANNER_RESPONSE","content":"I will view HomeView.swift to inspect the sidebar."}
        {"type":"VIEW_FILE","content":"... big file dump ..."}
        {"type":"PLANNER_RESPONSE","content":"Here are three suggestions:\\n\\n1. Do X\\n2. Do Y"}
        """
        let split = AntigravityTranscript.split(transcriptText: jsonl)
        XCTAssertEqual(split?.answer, "Here are three suggestions:\n\n1. Do X\n2. Do Y")
        XCTAssertEqual(split?.reasoning,
            "I will list the contents of the Apps directory.\nI will view HomeView.swift to inspect the sidebar.")
    }

    /// Simple no-tool run: one PLANNER_RESPONSE → it's the answer, no reasoning.
    func testSingleResponseHasNoReasoning() {
        let jsonl = """
        {"type":"USER_INPUT","content":"capital of France?"}
        {"type":"PLANNER_RESPONSE","content":"The capital of France is Paris."}
        """
        let split = AntigravityTranscript.split(transcriptText: jsonl)
        XCTAssertEqual(split?.answer, "The capital of France is Paris.")
        XCTAssertEqual(split?.reasoning, "")
    }

    func testReturnsNilWhenNoPlannerResponse() {
        XCTAssertNil(AntigravityTranscript.split(transcriptText: "{\"type\":\"USER_INPUT\",\"content\":\"hi\"}"))
        XCTAssertNil(AntigravityTranscript.split(transcriptText: ""))
    }
}
