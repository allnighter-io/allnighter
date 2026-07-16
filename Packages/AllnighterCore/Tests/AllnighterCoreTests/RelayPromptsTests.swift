import XCTest
@testable import AllnighterCore

/// The PM/dev/re-ask prompt templates (docs/phases/PM_Relay.md §2, §4). Assembly is pure
/// and deterministic; the load-bearing property is that embedded third-party text (dev
/// reports, handovers) survives verbatim even when it contains ```json fences or backticks
/// of its own — the sentinel-delimited blocks must never truncate or mutate it.
final class RelayPromptsTests: XCTestCase {

    // MARK: - Determinism

    func testPMPromptAssemblyIsDeterministic() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 3,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: "Shipped the parser.",
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 17
        )
        let first = RelayPMPrompt.assemble(context: context)
        let second = RelayPMPrompt.assemble(context: context)
        XCTAssertEqual(first, second)
    }

    func testDevPromptAssemblyIsDeterministic() {
        let context = RelayDevPrompt.Context(
            handover: "Build the parser.",
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 2,
            workerDisplayName: "Cursor Composer"
        )
        let first = RelayDevPrompt.assemble(context: context)
        let second = RelayDevPrompt.assemble(context: context)
        XCTAssertEqual(first, second)
    }

    func testReaskPromptAssemblyIsDeterministic() {
        let first = RelayReaskPrompt.assemble(previousOutput: "Looks done.", parseError: .noVerdictFound)
        let second = RelayReaskPrompt.assemble(previousOutput: "Looks done.", parseError: .noVerdictFound)
        XCTAssertEqual(first, second)
    }

    // MARK: - Round 1 vs round N structure

    func testRound1HasNoDevReportSection() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 1,
            baselineHead: "abc123",
            currentHead: nil,
            devReport: nil,
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 20
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains("Round 1 — no dev report yet"))
        XCTAssertFalse(prompt.contains("DEV REPORT (VERBATIM"))
        XCTAssertFalse(prompt.contains("Review the actual work"))
    }

    func testRoundNHasDevReportSectionAndReviewInstructions() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 2,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: "Implemented the thing.",
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 19
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertFalse(prompt.contains("Round 1 — no dev report yet"))
        XCTAssertTrue(prompt.contains("DEV REPORT (VERBATIM, ROUND 1) BEGIN"))
        XCTAssertTrue(prompt.contains("Review the actual work"))
        XCTAssertTrue(prompt.contains("git log abc123..def456"))
        XCTAssertTrue(prompt.contains("git diff abc123..def456"))
    }

    // MARK: - Verbatim survival

    func testDevReportSurvivesVerbatimIncludingEmbeddedFences() {
        let tricky = """
        Committed the parser. Verified with:
        ```json
        {"verdict": "continue", "handover": "not a real verdict, just quoting the shape"}
        ```
        Also used some `inline backticks` and a stray ``` triple-backtick fragment.
        """
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 2,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: tricky,
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 19
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains(tricky), "the dev report must appear byte-for-byte, embedded fences included")
    }

    func testHandoverSurvivesVerbatimInDevPrompt() {
        let tricky = """
        Build the endpoint. Reference shape:
        ```json
        {"verdict": "done", "note": "quoted only, not a real verdict"}
        ```
        Watch for `edge cases` and a lone ``` fragment.
        """
        let context = RelayDevPrompt.Context(
            handover: tricky,
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 4,
            workerDisplayName: "Grok Build"
        )
        let prompt = RelayDevPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains(tricky), "the handover must appear byte-for-byte, embedded fences included")
    }

    // MARK: - Verdict contract presence (PM) vs absence (dev)

    func testVerdictContractPresentInPMPromptAbsentInDevPrompt() {
        let pmContext = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 1,
            baselineHead: "abc123",
            currentHead: nil,
            devReport: nil,
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 20
        )
        let pmPrompt = RelayPMPrompt.assemble(context: pmContext)
        XCTAssertTrue(pmPrompt.contains("RelayVerdict"))
        XCTAssertTrue(pmPrompt.contains("\"verdict\": \"continue\""))

        let devContext = RelayDevPrompt.Context(
            handover: "Build the first unit of work described in the doc.",
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 1,
            workerDisplayName: "Dev Seat"
        )
        let devPrompt = RelayDevPrompt.assemble(context: devContext)
        XCTAssertFalse(devPrompt.contains("RelayVerdict"))
        XCTAssertFalse(devPrompt.contains("\"verdict\""))
        XCTAssertFalse(devPrompt.contains("escalate"))
    }

    // MARK: - Founder note

    func testFounderNoteAppearsWhenSet() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 5,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: "Report text.",
            founderNote: "Go with option 76, not 88.",
            maxRounds: 20,
            roundsRemaining: 15
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains("Founder note (injected on resume)"))
        XCTAssertTrue(prompt.contains("Go with option 76, not 88."))
    }

    func testFounderNoteAbsentWhenNil() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 5,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: "Report text.",
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 15
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertFalse(prompt.contains("Founder note"))
    }

    // MARK: - Ceiling awareness

    func testRoundsRemainingRendered() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 3,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: "Report text.",
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 17
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains("17 of 20 rounds left"))
    }

    // MARK: - Re-ask prompt

    func testReaskPromptQuotesParseErrorAndRestatesContractWithoutRedoingReview() {
        let previous = "Reviewed everything, looks solid, no verdict tail here though."
        let prompt = RelayReaskPrompt.assemble(previousOutput: previous, parseError: .noVerdictFound)
        XCTAssertTrue(prompt.contains("no JSON object anywhere in the reply carried a `verdict` key"))
        XCTAssertTrue(prompt.contains(previous))
        XCTAssertTrue(prompt.contains("RelayVerdict"))
        XCTAssertTrue(prompt.contains("Do not redo the review"))
    }

    func testReaskPromptDescribesUnknownVerdict() {
        let prompt = RelayReaskPrompt.assemble(previousOutput: "x", parseError: .unknownVerdict("maybe"))
        XCTAssertTrue(prompt.contains("\"maybe\""))
    }

    func testReaskPromptDescribesContinueWithoutHandover() {
        let prompt = RelayReaskPrompt.assemble(previousOutput: "x", parseError: .continueWithoutHandover)
        XCTAssertTrue(prompt.contains("handover"))
    }

    // MARK: - Provenance trailer (FR4)

    func testDevPromptIncludesCommitTrailerAskExactlyOnce() {
        let context = RelayDevPrompt.Context(
            handover: "Ship repoDelta.",
            docPath: "docs/phases/Field_Reports_1.md",
            roundNumber: 2,
            workerDisplayName: "Grok Build"
        )
        let prompt = RelayDevPrompt.assemble(context: context)
        let trailer = ProvenanceConvention.commitTrailerAsk(displayName: "Grok Build")
        XCTAssertTrue(prompt.contains(trailer))
        XCTAssertEqual(prompt.components(separatedBy: trailer).count - 1, 1)
    }

    // MARK: - Doc path anchoring

    func testDocPathAppearsInBothPrompts() {
        let pmContext = RelayPMPrompt.Context(
            docPath: "docs/phases/Weird_Doc.md",
            roundNumber: 1,
            baselineHead: "abc123",
            currentHead: nil,
            devReport: nil,
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 20
        )
        XCTAssertTrue(RelayPMPrompt.assemble(context: pmContext).contains("docs/phases/Weird_Doc.md"))

        let devContext = RelayDevPrompt.Context(
            handover: "Do the thing.",
            docPath: "docs/phases/Weird_Doc.md",
            roundNumber: 1,
            workerDisplayName: "Dev Seat"
        )
        XCTAssertTrue(RelayDevPrompt.assemble(context: devContext).contains("docs/phases/Weird_Doc.md"))
    }
}
