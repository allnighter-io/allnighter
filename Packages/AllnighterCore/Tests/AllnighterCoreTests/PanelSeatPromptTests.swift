import XCTest
@testable import AllnighterCore

/// PN-S02 per-seat prompt assembly: lens + brief verbatim + schema contract exactly once;
/// brief with embedded fences survives byte-exact; two seats' prompts have no cross-refs.
final class PanelSeatPromptTests: XCTestCase {

    func testAssemblesLensBriefTargetAndSchemaExactlyOnce() {
        let seat = PanelSeat(
            workerId: "model_opus",
            lens: "adversary",
            lensInstruction: "Hunt for scope leaks and silent refusals."
        )
        let brief = PanelSeatPrompt.builtinBrief
        let prompt = PanelSeatPrompt.assemble(
            seat: seat, brief: brief, targetPath: "docs/phases/Pilot_Panel.md"
        )

        XCTAssertTrue(prompt.contains("# Lens: adversary"))
        XCTAssertTrue(prompt.contains("Hunt for scope leaks and silent refusals."))
        XCTAssertTrue(prompt.contains("# Brief"))
        XCTAssertTrue(prompt.contains(brief), "brief must appear verbatim")
        XCTAssertTrue(prompt.contains("docs/phases/Pilot_Panel.md"))
        XCTAssertTrue(prompt.contains(PanelSeatPrompt.schemaContract))

        // Schema contract present exactly once (not double-injected).
        let schemaCount = prompt.components(separatedBy: PanelSeatPrompt.schemaContract).count - 1
        XCTAssertEqual(schemaCount, 1, "schema contract must appear exactly once")

        // Findings block shape markers in the contract.
        XCTAssertTrue(prompt.contains("noMaterialFindings"))
        XCTAssertTrue(prompt.contains("\"findings\""))
    }

    func testBriefWithEmbeddedFencesSurvivesByteExact() {
        let brief = """
        Refuted last round: the clonefile claim — do not re-litigate.

        Example of a bad seat report that embeds a fence:

        ```json
        {"findings": [], "noMaterialFindings": true, "reason": "example only"}
        ```

        stance: edit-in-place
        """
        let seat = PanelSeat(workerId: "model_sonnet", lens: "simplicity")
        let prompt = PanelSeatPrompt.assemble(
            seat: seat, brief: brief, targetPath: "docs/X.md"
        )

        // Byte-exact: the brief substring is present unchanged (including fences).
        guard let range = prompt.range(of: brief) else {
            XCTFail("brief must appear byte-exact inside the assembled prompt")
            return
        }
        XCTAssertEqual(String(prompt[range]), brief)
    }

    func testBlindIndependenceTwoSeatsHaveNoCrossReferences() {
        let a = PanelSeat(workerId: "model_opus", lens: "adversary", lensInstruction: "Lens A only")
        let b = PanelSeat(workerId: "model_sonnet", lens: "simplicity", lensInstruction: "Lens B only")
        let brief = "Shared brief text unique_token_xyz"
        let path = "docs/target.md"

        let promptA = PanelSeatPrompt.assemble(seat: a, brief: brief, targetPath: path)
        let promptB = PanelSeatPrompt.assemble(seat: b, brief: brief, targetPath: path)

        // Each seat sees its own lens, not the other's.
        XCTAssertTrue(promptA.contains("adversary"))
        XCTAssertTrue(promptA.contains("Lens A only"))
        XCTAssertFalse(promptA.contains("Lens B only"))
        XCTAssertFalse(promptA.contains("simplicity"))

        XCTAssertTrue(promptB.contains("simplicity"))
        XCTAssertTrue(promptB.contains("Lens B only"))
        XCTAssertFalse(promptB.contains("Lens A only"))
        XCTAssertFalse(promptB.contains("adversary"))

        // No seat id / worker cross-references in either prompt.
        XCTAssertFalse(promptA.contains("model_sonnet"))
        XCTAssertFalse(promptB.contains("model_opus"))
        // Neither prompt embeds the other seat's assembled identity markers.
        XCTAssertFalse(promptA.contains("# Lens: simplicity"))
        XCTAssertFalse(promptB.contains("# Lens: adversary"))
    }

    func testWorkerPromptsMapKeysAreWorkerIds() {
        let seats = [
            PanelSeat(workerId: "model_opus", lens: "adversary"),
            PanelSeat(workerId: "model_sonnet", lens: "simplicity"),
        ]
        let map = PanelSeatPrompt.workerPrompts(
            seats: seats, brief: "b", targetPath: "t.md"
        )
        XCTAssertEqual(Set(map.keys), ["model_opus", "model_sonnet"])
        XCTAssertTrue(map["model_opus"]?.contains("adversary") == true)
        XCTAssertTrue(map["model_sonnet"]?.contains("simplicity") == true)
    }

    /// PP-S01: schema contract forbids parking the findings block in an artifact/file.
    func testSchemaContractContainsPlacementRule() {
        let contract = PanelSeatPrompt.schemaContract
        XCTAssertTrue(
            contract.contains("report text itself"),
            "placement law must require the fenced block in the report text itself"
        )
        XCTAssertTrue(
            contract.contains("never in an artifact"),
            "placement law must forbid artifact/file delegation"
        )
        XCTAssertTrue(
            contract.contains("only channel Allnighter reads"),
            "placement law must state report text is the only channel"
        )
        // Example fenced block still present (placement rules extend Rules; example untouched).
        XCTAssertTrue(contract.contains("```json"))
        XCTAssertTrue(contract.contains("\"findings\""))
    }
}
