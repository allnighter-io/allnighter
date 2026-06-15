import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Design2 "Build this": the chosen image → a coding agent restyles the existing
/// code (our ICP is redesign, not build-from-scratch).
final class DesignBuildTests: XCTestCase {

    private func designRun(chosen: Bool) -> (TeamRun, URL) {
        let runFolder = FileManager.default.temporaryDirectory.appendingPathComponent("dbt-\(UUID().uuidString)")
        var board = BoardPayload(
            targetShape: .mobile,
            screenshotPath: "screenshot.png",
            options: [
                DesignOption(workerId: "w1#0", modelId: "w1", persona: "minimal", imagePath: "option_w1-0.png", status: .done),
                DesignOption(workerId: "w2#0", modelId: "w2", persona: "bold", status: .failed, failureReason: "x")
            ]
        )
        if chosen { board.chosen = ChosenOption(workerId: "w1#0", persona: "minimal", rejectedWorkerIds: []) }
        let run = TeamRun(
            id: "run-d", prompt: "make the profile premium", status: .complete, presetId: "design_board",
            workers: [Worker(id: "w1#0", modelId: "w1", instanceIndex: 0, skillId: "minimal")],
            stages: [StageOutput(id: "b", purpose: .board, status: .done, payload: .board(board))],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return (run, runFolder)
    }

    func testBuildsDesignBriefFromChosenOption() throws {
        let (run, folder) = designRun(chosen: true)
        let brief = try XCTUnwrap(DesignBriefBuilder.build(
            run: run, chosenSeatId: "w1#0", executionWorkerId: "model_opus",
            workingDirectory: "/repo", runFolder: folder))

        XCTAssertEqual(brief.sourceArtifact, .designImage)
        XCTAssertTrue(brief.isDesignBuild)
        XCTAssertEqual(brief.designImagePath, folder.appendingPathComponent("option_w1-0.png").path)
        XCTAssertEqual(brief.beforeScreenshotPath, folder.appendingPathComponent("screenshot.png").path)
        XCTAssertEqual(brief.workingDirectory, "/repo")
    }

    func testBuildFromFailedSeatReturnsNil() {
        let (run, folder) = designRun(chosen: true)
        XCTAssertNil(DesignBriefBuilder.build(run: run, chosenSeatId: "w2#0", executionWorkerId: "w", workingDirectory: "/r", runFolder: folder))
    }

    func testDesignExecutionPromptRestylesExistingCode() throws {
        let (run, folder) = designRun(chosen: true)
        let brief = try XCTUnwrap(DesignBriefBuilder.build(run: run, chosenSeatId: "w1#0", executionWorkerId: "w", workingDirectory: "/repo", runFolder: folder))
        let prompt = BriefMarkdown.executionPrompt(brief)
        XCTAssertTrue(prompt.contains("redesign, not a build-from-scratch"))
        XCTAssertTrue(prompt.contains(brief.designImagePath!))
        XCTAssertTrue(prompt.contains("/repo"))
        XCTAssertTrue(prompt.contains("MODIFY"))
        // The brief markdown is design-flavored, not the code spec template.
        XCTAssertTrue(BriefMarkdown.brief(brief).contains("Design Build Brief"))
    }

    func testReadsImagesCapabilityFlag() throws {
        let claude = DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI,
                                    invoke: .init(command: "claude", args: ["-p", "{{prompt}}"]), readsImages: true)
        let grok = DriverManifest(id: "grok", displayName: "Grok", kind: .headlessCLI,
                                  invoke: .init(command: "grok", args: ["-p", "{{prompt}}"]))
        XCTAssertTrue(claude.canReadImages)
        XCTAssertFalse(grok.canReadImages)
    }
}
