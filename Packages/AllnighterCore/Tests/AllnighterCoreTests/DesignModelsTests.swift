import XCTest
@testable import AllnighterCore

/// Contract-first proof for the design team (Lane 2) Core models: the design
/// request, the board payload/option/pick, the `board` stage, and the `imageGen`
/// driver capability. The unit is a generated image; OCR and HTML rendering are
/// dead (see docs/mvp/Design0).
final class DesignModelsTests: XCTestCase {

    private func assertRoundTrips<T: Codable & Equatable>(_ value: T) throws {
        let data = try CoreJSON.encode(value)
        let back = try CoreJSON.decode(T.self, from: data)
        XCTAssertEqual(value, back)
    }

    func testDesignRequestRoundTrips() throws {
        try assertRoundTrips(DesignRequest(
            prompt: "make this profile screen feel premium and clean",
            personaIds: ["minimal", "bold", "editorial"],
            screenshotPath: "screenshot.png",
            targetShape: .mobile
        ))
        // Greenfield: no screenshot.
        try assertRoundTrips(DesignRequest(prompt: "a settings screen", personaIds: ["minimal"], targetShape: .desktop))
    }

    func testBoardPayloadRoundTripsWithMixedOptions() throws {
        let board = BoardPayload(
            targetShape: .mobile,
            screenshotPath: "screenshot.png",
            options: [
                DesignOption(agentId: "model_grok#0", modelId: "model_grok", persona: "bold",
                             imagePath: "option_model_grok#0.png", sessionId: "sess-1", status: .done),
                DesignOption(agentId: "model_gemini#0", modelId: "model_gemini", persona: "minimal",
                             imagePath: "option_model_gemini#0.jpg", status: .done),
                DesignOption(agentId: "model_chatgpt#0", modelId: "model_chatgpt", persona: "editorial",
                             status: .failed, failureReason: "engine error: rate limited")
            ],
            chosen: ChosenOption(agentId: "model_grok#0", persona: "bold",
                                 rationale: "tightest hierarchy", rejectedAgentIds: ["model_gemini#0"])
        )
        try assertRoundTrips(board)
        XCTAssertEqual(board.options.count, 3)
        XCTAssertEqual(board.rendered.count, 2)           // one failed seat excluded
        XCTAssertEqual(board.chosen?.agentId, "model_grok#0")
        XCTAssertFalse(board.options[2].hasImage)          // failed seat
        XCTAssertTrue(board.options[0].hasImage)
    }

    func testBoardStageOutputRoundTripsAndDiscriminates() throws {
        let board = BoardPayload(targetShape: .desktop, options: [
            DesignOption(agentId: "w#0", modelId: "w", persona: "minimal", imagePath: "option_w#0.png", status: .done)
        ])
        let stage = StageOutput(id: "board-1", purpose: .board, status: .done, payload: .board(board))
        try assertRoundTrips(stage)

        let data = try CoreJSON.encode(stage)
        let back = try CoreJSON.decode(StageOutput.self, from: data)
        XCTAssertEqual(back.purpose, .board)
        XCTAssertEqual(back.payload?.purpose, .board)
        XCTAssertEqual(back.payload?.board?.options.first?.imagePath, "option_w#0.png")
        XCTAssertNil(back.payload?.markdown)               // board is purely structured
    }

    func testImageGenManifestRoundTripsAndFlags() throws {
        let manifest = DriverManifest(
            id: "grok",
            displayName: "Grok Build CLI",
            kind: .headlessCLI,
            invoke: .init(command: "grok", args: ["-p", "{{prompt}}"]),
            output: .init(),
            imageGen: .init(
                args: ["-p", "{{prompt}}", "--yolo", "--output-format", "json", "--cwd", "{{runDir}}"],
                promptTemplate: "Generate an image: {{designPrompt}}. Save the final image to {{imageOut}} and reply with the absolute path only.",
                arrival: .promptDirected,
                stdoutPathRegex: #""path"\s*:\s*"([^"]+)""#,
                sessionIdRegex: #""sessionId"\s*:\s*"([^"]+)""#
            )
        )
        try assertRoundTrips(manifest)
        XCTAssertTrue(manifest.canGenerateImages)
        XCTAssertEqual(manifest.imageGen?.arrival, .promptDirected)
    }

    func testTextManifestCannotGenerateImages() {
        let text = DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
                                  invoke: .init(command: "claude", args: ["-p", "{{prompt}}"]))
        XCTAssertFalse(text.canGenerateImages)
        XCTAssertNil(text.imageGen)
    }
}
