import XCTest
import AgentOSTeam
@testable import AllnighterCore
@testable import AllnighterEngine

/// DL-S02 — HTML/SVG → WebKit PNG + designBoard stage wiring.
final class DesignBoardCaptureTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-s02-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    // MARK: - Locate / declare

    func testLocateArtifactConventionHTML() throws {
        let workerId = "model_opus#0"
        let html = tempRoot.appendingPathComponent("option_model_opus-0.html")
        try fixtureHTML.write(to: html, atomically: true, encoding: .utf8)
        let found = DesignBoardCapture.locateArtifact(
            workerId: workerId, runDirectory: tempRoot, seatOutput: nil)
        XCTAssertEqual(found?.standardizedFileURL, html.standardizedFileURL)
    }

    func testLocateArtifactPrefersDeclaredPath() throws {
        let declared = tempRoot.appendingPathComponent("seat-mock.svg")
        try fixtureSVG.write(to: declared, atomically: true, encoding: .utf8)
        let output = """
        Built a mock.
        capture: svg seat-mock.svg
        """
        let found = DesignBoardCapture.locateArtifact(
            workerId: "w#0", runDirectory: tempRoot, seatOutput: output)
        XCTAssertEqual(found?.lastPathComponent, "seat-mock.svg")
    }

    func testDeclaredPathIgnoresNativeAndConcept() {
        XCTAssertNil(DesignBoardCapture.declaredArtifactPath(in: "capture: native Foo.swift"))
        XCTAssertNil(DesignBoardCapture.declaredArtifactPath(in: "path: concept mood.png"))
        XCTAssertEqual(
            DesignBoardCapture.declaredArtifactPath(in: "capture: html option_x.html"),
            "option_x.html"
        )
    }

    func testMissingArtifactFailsClosedWithoutImageGen() async {
        let worker = Worker(
            id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
            skillId: "visual_system_designer", purpose: .answer)
        let board = await DesignBoardCapture.captureBoard(
            answerWorkers: [worker],
            answers: [TeamAnswer(
                memberId: worker.id, modelId: worker.modelId, role: "answer",
                result: WorkerRunResult(status: .done, output: "no file left behind"))],
            runDirectory: tempRoot
        )
        XCTAssertEqual(board.options.count, 1)
        XCTAssertEqual(board.options[0].status, .failed)
        XCTAssertNil(board.options[0].imagePath)
        XCTAssertTrue(board.options[0].failureReason?.contains("no captureable") == true)
        XCTAssertTrue(board.rendered.isEmpty)
    }

    // MARK: - WebKit capture

    func testWebKitCaptureFixtureHTMLWritesValidPNG() async throws {
        #if canImport(WebKit) && canImport(AppKit)
        let html = tempRoot.appendingPathComponent("fixture.html")
        let png = tempRoot.appendingPathComponent("out.png")
        try fixtureHTML.write(to: html, atomically: true, encoding: .utf8)

        try await DesignBoardCapture.capture(sourceFile: html, destinationPNG: png)

        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))
        XCTAssertTrue(WorkerImageCapture.isValidImage(at: png))
        let bytes = try Data(contentsOf: png)
        XCTAssertGreaterThan(bytes.count, 64)
        #else
        throw XCTSkip("WebKit/AppKit unavailable — Design camera is macOS-only")
        #endif
    }

    func testWebKitCaptureMissingFileFailsClosed() async {
        let missing = tempRoot.appendingPathComponent("gone.html")
        let png = tempRoot.appendingPathComponent("out.png")
        do {
            try await DesignBoardCapture.capture(sourceFile: missing, destinationPNG: png)
            XCTFail("expected fileMissing")
        } catch let error as DesignBoardCapture.CaptureError {
            XCTAssertEqual(error, .fileMissing)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: png.path))
    }

    func testCaptureBoardWritesOptionPNGAndMapsDesignBoard() async throws {
        #if canImport(WebKit) && canImport(AppKit)
        let workerId = "model_fable#0"
        let html = tempRoot.appendingPathComponent("option_model_fable-0.html")
        try fixtureHTML.write(to: html, atomically: true, encoding: .utf8)

        let worker = Worker(
            id: workerId, modelId: "model_fable", instanceIndex: 0,
            skillId: "visual_system_designer", purpose: .answer)
        let board = await DesignBoardCapture.captureBoard(
            answerWorkers: [worker],
            answers: [TeamAnswer(
                memberId: workerId, modelId: "model_fable", role: "answer",
                result: WorkerRunResult(status: .done, output: "built html"))],
            runDirectory: tempRoot
        )

        XCTAssertEqual(board.options.count, 1)
        XCTAssertEqual(board.options[0].status, .done)
        XCTAssertEqual(board.options[0].imagePath, "option_model_fable-0.png")
        XCTAssertTrue(board.options[0].hasImage)
        let png = tempRoot.appendingPathComponent("option_model_fable-0.png")
        XCTAssertTrue(WorkerImageCapture.isValidImage(at: png))

        // Board stage maps through TeamRunJSONMapper.mapDesignBoard.
        var run = TeamRun(
            id: "design-board-map",
            prompt: "mock a landing hero",
            status: .complete,
            origin: .cli,
            presetId: "design_design",
            workers: [worker],
            workerAnswers: [],
            stages: [StageOutput(
                id: "board-1", purpose: .board, status: .done, payload: .board(board)
            )],
            createdAt: Date(),
            lane: .design,
            outputKind: .designBoard
        )
        run.endReason = .completed
        let mapped = TeamRunJSONMapper.mapDesignBoard(run, runDirectory: tempRoot)
        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.options.count, 1)
        XCTAssertEqual(mapped?.options.first?.imagePath, "option_model_fable-0.png")
        XCTAssertEqual(
            mapped?.options.first?.absolutePath,
            png.standardizedFileURL.path
        )
        XCTAssertEqual(mapped?.options.first?.status, .done)
        #else
        throw XCTSkip("WebKit/AppKit unavailable — Design camera is macOS-only")
        #endif
    }

    // MARK: - CatalogRunCoordinator wiring

    func testDesignBoardRunAppendsBoardStageWithoutImageGen() async throws {
        #if canImport(WebKit) && canImport(AppKit)
        let runDir = tempRoot.appendingPathComponent("run_dir", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        let workerId = "model_opus#0"
        let html = runDir.appendingPathComponent("option_model_opus-0.html")
        try fixtureHTML.write(to: html, atomically: true, encoding: .utf8)

        let mock = MockCommandRunner(scripts: [
            "claude": .init(stdout: "seat built a surface", exitCode: 0),
            "writer": .init(stdout: "# Lead Call\n\npick the clean one", exitCode: 0)
        ])
        // Two manifests so answer + writer can resolve (same command ok for mock).
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "writer_cli", command: "writer")
        ])
        let coord = CatalogRunCoordinator(
            workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)),
            registry: registry,
            idFactory: { "id-\(UUID().uuidString)" }
        )
        let answer = Worker(
            id: workerId, modelId: "model_opus", instanceIndex: 0,
            skillId: "visual_system_designer", skillName: "Visual", purpose: .answer)
        let lead = Worker(
            id: "model_writer#0", modelId: "model_writer", instanceIndex: 0,
            skillId: "design_board_writer", skillName: "Board Writer", purpose: .plan)
        let resolved = ResolvedTeamRun(
            teamPresetId: "design_design", teamDisplayName: "Design", lane: .design,
            outputKind: .designBoard, effort: .med,
            answerWorkers: [answer], planWriter: lead, isRunnable: true)
        let models = [
            TestSupport.worker("model_opus", driverId: "claude_code"),
            TestSupport.worker("model_writer", driverId: "writer_cli", role: .both)
        ]

        let run = await coord.run(
            resolved: resolved,
            prompt: "Redesign this landing hero",
            models: models,
            runId: "dl-s02-coord",
            runDirectory: runDir
        )

        XCTAssertEqual(run.outputKind, .designBoard)
        let boardStage = run.stages.first { $0.purpose == .board }
        XCTAssertNotNil(boardStage, "designBoard runs must append a .board stage")
        let board = boardStage?.payload?.board
        XCTAssertEqual(board?.options.count, 1)
        XCTAssertEqual(board?.options.first?.status, .done)
        XCTAssertEqual(board?.options.first?.imagePath, "option_model_opus-0.png")
        XCTAssertTrue(
            WorkerImageCapture.isValidImage(at: runDir.appendingPathComponent("option_model_opus-0.png"))
        )
        // Plan writer still ran; board is host capture — not imageGen.
        XCTAssertTrue(run.stages.contains { $0.purpose == .plan && $0.status == .done })
        let mapped = TeamRunJSONMapper.mapDesignBoard(run, runDirectory: runDir)
        XCTAssertEqual(mapped?.options.first?.imagePath, "option_model_opus-0.png")
        #else
        throw XCTSkip("WebKit/AppKit unavailable — Design camera is macOS-only")
        #endif
    }

    func testDesignBoardMissingHTMLMarksOptionFailedNotDiffusion() async {
        let runDir = tempRoot.appendingPathComponent("run_empty", isDirectory: true)
        try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let mock = MockCommandRunner(scripts: [
            "claude": .init(stdout: "I forgot to write HTML", exitCode: 0),
            "writer": .init(stdout: "# Lead\n\nnothing to pick", exitCode: 0)
        ])
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "writer_cli", command: "writer")
        ])
        let coord = CatalogRunCoordinator(
            workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)),
            registry: registry
        )
        let answer = Worker(
            id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
            skillId: "visual_system_designer", purpose: .answer)
        let lead = Worker(
            id: "model_writer#0", modelId: "model_writer", instanceIndex: 0,
            skillId: "design_board_writer", purpose: .plan)
        let resolved = ResolvedTeamRun(
            teamPresetId: "design_design", teamDisplayName: "Design", lane: .design,
            outputKind: .designBoard, effort: .med,
            answerWorkers: [answer], planWriter: lead, isRunnable: true)

        let run = await coord.run(
            resolved: resolved,
            prompt: "design something",
            models: [
                TestSupport.worker("model_opus", driverId: "claude_code"),
                TestSupport.worker("model_writer", driverId: "writer_cli", role: .both)
            ],
            runId: "dl-s02-fail",
            runDirectory: runDir
        )

        let opt = run.latestStage(.board)?.payload?.board?.options.first
        XCTAssertEqual(opt?.status, .failed)
        XCTAssertNil(opt?.imagePath)
        XCTAssertTrue(opt?.failureReason?.contains("no captureable") == true)
    }

    // MARK: - Fixtures

    private var fixtureHTML: String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>DL-S02</title>
        <style>
          html,body{margin:0;background:#0b0d10;color:#f5a623;font-family:monospace}
          main{padding:48px}
          h1{font-size:42px;margin:0}
        </style></head>
        <body><main><h1>Allnighter Design Capture</h1>
        <p>Fixture surface for WebKit board capture.</p></main></body></html>
        """
    }

    private var fixtureSVG: String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="320" height="180">
          <rect width="100%" height="100%" fill="#0b0d10"/>
          <text x="24" y="96" fill="#f5a623" font-size="28" font-family="monospace">SVG</text>
        </svg>
        """
    }
}
