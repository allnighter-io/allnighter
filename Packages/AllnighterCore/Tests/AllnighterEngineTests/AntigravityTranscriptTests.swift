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

    /// AGY injects SYSTEM_MESSAGE turns AFTER the model has answered the user, and the model
    /// replies to them. Those replies are addressed to the system, not the user, and are
    /// content-free pleasantries. Taking the last step shipped the pleasantry as the answer
    /// while the run still settled `done` — a silently faked success.
    ///
    /// Shape taken verbatim from a real transcript
    /// (`~/.gemini/antigravity-cli/brain/<id>/.system_generated/logs/transcript.jsonl`,
    /// steps 17-19): the real answer landed 14s in, the pleasantry 2m49s later.
    func testIgnoresPlannerRepliesToTrailingSystemMessages() {
        let jsonl = """
        {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"what line is makeID on?"}
        {"step_index":15,"source":"MODEL","type":"PLANNER_RESPONSE","tool_calls":[{"name":"run_command"}]}
        {"step_index":16,"source":"MODEL","type":"RUN_COMMAND","content":"... tool output ..."}
        {"step_index":17,"source":"MODEL","type":"PLANNER_RESPONSE","content":"Line 73."}
        {"step_index":18,"source":"SYSTEM","type":"SYSTEM_MESSAGE","content":"The following is a <SYSTEM_MESSAGE> not actually sent by the user."}
        {"step_index":19,"source":"MODEL","type":"PLANNER_RESPONSE","content":"Thank you, task-6 completed. All required information was provided above."}
        """
        let split = AntigravityTranscript.split(transcriptText: jsonl)
        XCTAssertEqual(split?.answer, "Line 73.", "the pleasantry addressed to the system must not become the answer")
        XCTAssertEqual(split?.reasoning, "", "the trailing reply must not be demoted into reasoning either")
    }

    /// The degenerate real case: several SYSTEM_MESSAGE round trips, each reply emptier than
    /// the last. Only the pre-system answer counts.
    func testKeepsFirstAnswerAcrossRepeatedSystemMessageRoundTrips() {
        let jsonl = """
        {"step_index":23,"type":"PLANNER_RESPONSE","content":"Summary: the struct defines thirteen stored properties."}
        {"step_index":24,"type":"SYSTEM_MESSAGE","content":"<SYSTEM_MESSAGE>"}
        {"step_index":25,"type":"PLANNER_RESPONSE","content":"The background task has finished."}
        {"step_index":26,"type":"SYSTEM_MESSAGE","content":"<SYSTEM_MESSAGE>"}
        {"step_index":27,"type":"PLANNER_RESPONSE","content":"All background search tasks have finished."}
        {"step_index":28,"type":"SYSTEM_MESSAGE","content":"<SYSTEM_MESSAGE>"}
        {"step_index":29,"type":"PLANNER_RESPONSE","content":"All background processes are complete."}
        """
        let split = AntigravityTranscript.split(transcriptText: jsonl)
        XCTAssertEqual(split?.answer, "Summary: the struct defines thirteen stored properties.")
    }

    /// A SYSTEM_MESSAGE that arrives BEFORE any answer must not starve the parse — otherwise a
    /// harmless early notice would make us return nil and fall back to agy's useless stdout.
    func testSystemMessageBeforeAnyAnswerDoesNotSuppressTheAnswer() {
        let jsonl = """
        {"step_index":0,"type":"USER_INPUT","content":"hi"}
        {"step_index":1,"type":"SYSTEM_MESSAGE","content":"permission notice"}
        {"step_index":2,"type":"PLANNER_RESPONSE","content":"The capital of France is Paris."}
        """
        let split = AntigravityTranscript.split(transcriptText: jsonl)
        XCTAssertEqual(split?.answer, "The capital of France is Paris.")
    }

    /// Transcripts with no SYSTEM_MESSAGE are unaffected — the last step is still the answer.
    /// (Verified against a real `agy -p "17 times 23"` transcript, which has none.)
    func testNoSystemMessageKeepsLastStepBehaviour() {
        let jsonl = """
        {"type":"USER_INPUT","content":"17 times 23?"}
        {"type":"PLANNER_RESPONSE","content":"391"}
        """
        XCTAssertEqual(AntigravityTranscript.split(transcriptText: jsonl)?.answer, "391")
    }
}
