import XCTest
@testable import AllnighterCore

/// The PM/dev/re-ask prompt templates (docs/phases/PM_Relay.md §2, §4). Assembly is pure
/// and deterministic; the load-bearing property is that embedded third-party text (dev
/// reports, handovers) survives verbatim even when it contains ```json fences or backticks
/// of its own — the sentinel-delimited blocks must never truncate or mutate it.
final class LoopPromptsTests: XCTestCase {

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
        let context = LoopDevPrompt.Context(
            handover: "Build the parser.",
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 2,
            workerDisplayName: "Cursor Composer"
        )
        let first = LoopDevPrompt.assemble(context: context)
        let second = LoopDevPrompt.assemble(context: context)
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
        XCTAssertTrue(prompt.contains("The report is never evidence of a passing gate"))
    }

    func testFailedExecutionOutcomeLeadsThePMPromptAndIgnoresSeatProse() {
        let lie = "the change is applied and ready for review"
        let outcome = LoopExecutionOutcome(
            status: .failed,
            reasons: ["declared proof `swift build` exited 1"]
        )
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/OpenCode_Local_Ollama_Seats.md",
            roundNumber: 2,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: lie,
            executionOutcome: outcome,
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 19
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        let outcomeIdx = prompt.range(of: "Allnighter execution outcome")?.lowerBound
        let reportIdx = prompt.range(of: lie)?.lowerBound
        XCTAssertNotNil(outcomeIdx)
        XCTAssertNotNil(reportIdx)
        if let outcomeIdx, let reportIdx {
            XCTAssertLessThan(outcomeIdx, reportIdx, "lead must see Allnighter facts before the seat's prose")
        }
        XCTAssertTrue(prompt.contains("status: failed"))
        XCTAssertTrue(prompt.contains("declared proof `swift build` exited 1"))
        XCTAssertTrue(prompt.contains("claim, not evidence"))
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
        let context = LoopDevPrompt.Context(
            handover: tricky,
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 4,
            workerDisplayName: "Grok Build"
        )
        let prompt = LoopDevPrompt.assemble(context: context)
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
        XCTAssertTrue(pmPrompt.contains("LoopVerdict"))
        XCTAssertTrue(pmPrompt.contains("\"verdict\": \"continue\""))

        let devContext = LoopDevPrompt.Context(
            handover: "Build the first unit of work described in the doc.",
            docPath: "docs/phases/PM_Relay.md",
            roundNumber: 1,
            workerDisplayName: "Dev Seat"
        )
        let devPrompt = LoopDevPrompt.assemble(context: devContext)
        XCTAssertFalse(devPrompt.contains("LoopVerdict"))
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

    // MARK: - Kickoff brief (ATL-S01)

    func testKickoffBriefAppearsWhenSet() throws {
        let brief = "Ship the parser fix; do not touch UI"
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/Agent_Team_Loop.md",
            roundNumber: 1,
            baselineHead: "abc123",
            kickoffMessage: brief,
            maxRounds: 20,
            roundsRemaining: 20
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains("## Kickoff brief (founder)"), prompt)
        XCTAssertTrue(prompt.contains(brief), prompt)
        // Placement: after rounds-remaining line, before founderNote / dev-report blocks.
        let kickoffIdx = try XCTUnwrap(prompt.range(of: "## Kickoff brief (founder)")).lowerBound
        let roundsIdx = try XCTUnwrap(prompt.range(of: "rounds left before this relay stops")).lowerBound
        XCTAssertLessThan(roundsIdx, kickoffIdx)
    }

    func testKickoffBriefAbsentWhenNilAsAfterConsume() {
        // Simulated second-round assemble: coordinator clears kickoffMessage after first PM turn.
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/Agent_Team_Loop.md",
            roundNumber: 2,
            baselineHead: "abc123",
            currentHead: "def456",
            devReport: "Dev delivered the parser fix.",
            kickoffMessage: nil,
            maxRounds: 20,
            roundsRemaining: 19
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertFalse(prompt.contains("Kickoff brief"), prompt)
        XCTAssertFalse(prompt.contains("## Kickoff brief (founder)"), prompt)
    }

    func testKickoffBriefVerbatimNotParaphrased() {
        let brief = "Ship X exactly;\n  keep  indentation\nand newlines."
        let context = RelayPMPrompt.Context(
            docPath: "docs/spec.md",
            roundNumber: 1,
            baselineHead: "abc",
            kickoffMessage: brief,
            maxRounds: 5,
            roundsRemaining: 5
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains("## Kickoff brief (founder)\n\(brief)"), prompt)
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
        XCTAssertTrue(prompt.contains("LoopVerdict"))
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

    // MARK: - Folder-native memory pointer (Folder_Native_Memory.md)

  private static let memoryPointerMarker = "If MEMORY.md exists at the repo root, read it before anything else"

    func testPMPromptIncludesMemoryPointerExactlyOnce() {
        let context = RelayPMPrompt.Context(
            docPath: "docs/phases/Folder_Native_Memory.md",
            roundNumber: 1,
            baselineHead: "abc123",
            currentHead: nil,
            devReport: nil,
            founderNote: nil,
            maxRounds: 20,
            roundsRemaining: 20
        )
        let prompt = RelayPMPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains(Self.memoryPointerMarker))
        XCTAssertTrue(prompt.contains("honored MEMORY: <line>"))
        XCTAssertTrue(prompt.contains("do not silently work around it"))
        XCTAssertEqual(prompt.components(separatedBy: Self.memoryPointerMarker).count - 1, 1)
    }

    func testDevPromptIncludesMemoryPointerExactlyOnce() {
        let context = LoopDevPrompt.Context(
            handover: "Add the pointer line.",
            docPath: "docs/phases/Folder_Native_Memory.md",
            roundNumber: 2,
            workerDisplayName: "Grok Build"
        )
        let prompt = LoopDevPrompt.assemble(context: context)
        XCTAssertTrue(prompt.contains(Self.memoryPointerMarker))
        XCTAssertTrue(prompt.contains("honored MEMORY: <line>"))
        XCTAssertTrue(prompt.contains("do not silently work around it"))
        XCTAssertEqual(prompt.components(separatedBy: Self.memoryPointerMarker).count - 1, 1)
    }

    // MARK: - Provenance trailer (FR4)

    func testDevPromptIncludesCommitTrailerAskExactlyOnce() {
        let context = LoopDevPrompt.Context(
            handover: "Ship repoDelta.",
            docPath: "docs/phases/Field_Reports_1.md",
            roundNumber: 2,
            workerDisplayName: "Grok Build"
        )
        let prompt = LoopDevPrompt.assemble(context: context)
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

        let devContext = LoopDevPrompt.Context(
            handover: "Do the thing.",
            docPath: "docs/phases/Weird_Doc.md",
            roundNumber: 1,
            workerDisplayName: "Dev Seat"
        )
        XCTAssertTrue(LoopDevPrompt.assemble(context: devContext).contains("docs/phases/Weird_Doc.md"))
    }
}
