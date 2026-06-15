import XCTest
@testable import AllnighterCore

/// Contract-first proof for the design council (Lane 2) Core models: the design
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
            personaIds: ["minimal", "bold", "editorial", "on_brand"],
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
                DesignOption(seatId: "worker_grok#0", workerId: "worker_grok", persona: "bold",
                             imagePath: "option_worker_grok#0.png", sessionId: "sess-1", status: .done),
                DesignOption(seatId: "worker_gemini#0", workerId: "worker_gemini", persona: "minimal",
                             imagePath: "option_worker_gemini#0.jpg", status: .done),
                DesignOption(seatId: "worker_chatgpt#0", workerId: "worker_chatgpt", persona: "editorial",
                             status: .failed, failureReason: "engine error: rate limited")
            ],
            chosen: ChosenOption(seatId: "worker_grok#0", persona: "bold",
                                 rationale: "tightest hierarchy", rejectedSeatIds: ["worker_gemini#0"])
        )
        try assertRoundTrips(board)
        XCTAssertEqual(board.options.count, 3)
        XCTAssertEqual(board.rendered.count, 2)           // one failed seat excluded
        XCTAssertEqual(board.chosen?.seatId, "worker_grok#0")
        XCTAssertFalse(board.options[2].hasImage)          // failed seat
        XCTAssertTrue(board.options[0].hasImage)
    }

    func testBoardStageOutputRoundTripsAndDiscriminates() throws {
        let board = BoardPayload(targetShape: .desktop, options: [
            DesignOption(seatId: "w#0", workerId: "w", persona: "minimal", imagePath: "option_w#0.png", status: .done)
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
