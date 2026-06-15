import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class DesignImageRunnerTests: XCTestCase {

    // MARK: - Helpers

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-design-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePNG(at url: URL) {
        let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01]
        try? Data(bytes).write(to: url)
    }

    private func seat() -> Worker { Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0, skillId: "bold") }
    private func worker() -> Model { Model(id: "model_grok", displayName: "Grok", modelLabel: "grok-build", driverId: "grok") }

    private func imageManifest(arrival: DriverManifest.ImageGen.Arrival) -> DriverManifest {
        DriverManifest(
            id: "grok", displayName: "Grok", kind: .headlessCLI,
            invoke: .init(command: "grok", args: ["-p", "{{prompt}}"]),
            imageGen: .init(
                args: ["-p", "{{prompt}}", "--yolo", "--cwd", "{{runDir}}"],
                promptTemplate: "Generate an image: {{designPrompt}}. Save the final image to {{imageOut}} and reply with the path.",
                arrival: arrival,
                stdoutPathRegex: #"PATH=(\S+)"#,
                sessionIdRegex: #"SESSION=(\S+)"#
            )
        )
    }

    private func req() -> DesignSeatRequest {
        DesignSeatRequest(userPrompt: "make it premium", personaId: "bold",
                          personaDirection: "high contrast, big type", targetShape: .mobile)
    }

    // MARK: - Capture paths

    /// A CommandRunner that simulates a `promptDirected` engine: it parses the
    /// requested save path out of the wrapped prompt and writes a PNG there (as the
    /// real model would mid-run), then reports a session id.
    private struct FileWritingRunner: CommandRunner {
        let session: String
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            let prompt = args.first { $0.contains("Save the final image to") } ?? ""
            if let r = DesignImageRunner.firstCapture(prompt, pattern: #"Save the final image to (\S+)"#) {
                let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]
                try? Data(bytes).write(to: URL(fileURLWithPath: r))
            }
            return CommandResult(stdout: "SESSION=\(session) done", exitCode: 0)
        }
    }

    func testPromptDirectedSuccessWhenModelWroteToImageOut() async {
        let dir = tempDir()
        let option = await DesignImageRunner(commandRunner: FileWritingRunner(session: "sess-9"))
            .run(seat: seat(), worker: worker(), manifest: imageManifest(arrival: .promptDirected), request: req(), runDir: dir)

        XCTAssertEqual(option.status, .done)
        XCTAssertEqual(option.imagePath, "option_model_grok-0.png")
        XCTAssertEqual(option.persona, "bold")
        XCTAssertEqual(option.sessionId, "sess-9")
        XCTAssertTrue(option.hasImage)
    }

    func testPromptDirectedFallsBackToParsedStdoutPath() async {
        let dir = tempDir()
        let elsewhere = tempDir().appendingPathComponent("img.png")
        writePNG(at: elsewhere)
        let mock = MockCommandRunner(scripts: ["grok": .init(stdout: "PATH=\(elsewhere.path)", exitCode: 0)])
        let option = await DesignImageRunner(commandRunner: mock)
            .run(seat: seat(), worker: worker(), manifest: imageManifest(arrival: .promptDirected), request: req(), runDir: dir)

        XCTAssertEqual(option.status, .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("option_model_grok-0.png").path))
    }

    func testStdoutPathArrivalParsesAndCopies() async {
        let dir = tempDir()
        let opaque = tempDir().appendingPathComponent("brain/abc.png")
        try? FileManager.default.createDirectory(at: opaque.deletingLastPathComponent(), withIntermediateDirectories: true)
        writePNG(at: opaque)
        let mock = MockCommandRunner(scripts: ["grok": .init(stdout: "image: PATH=\(opaque.path) SESSION=s1", exitCode: 0)])
        let option = await DesignImageRunner(commandRunner: mock)
            .run(seat: seat(), worker: worker(), manifest: imageManifest(arrival: .stdoutPath), request: req(), runDir: dir)

        XCTAssertEqual(option.status, .done)
        XCTAssertEqual(option.imagePath, "option_model_grok-0.png")
        XCTAssertEqual(option.sessionId, "s1")
    }

    // MARK: - Failures (a failed seat is a gray tile, never a thrown error)

    func testNoImageProducedIsFailed() async {
        let dir = tempDir()
        let mock = MockCommandRunner(scripts: ["grok": .init(stdout: "I made an image!", exitCode: 0)])
        let option = await DesignImageRunner(commandRunner: mock)
            .run(seat: seat(), worker: worker(), manifest: imageManifest(arrival: .promptDirected), request: req(), runDir: dir)
        XCTAssertEqual(option.status, .failed)
        XCTAssertFalse(option.hasImage)
        XCTAssertNotNil(option.failureReason)
    }

    func testNonzeroExitIsFailedWithReason() async {
        let dir = tempDir()
        let mock = MockCommandRunner(scripts: ["grok": .init(stderr: "rate limited", exitCode: 1)])
        let option = await DesignImageRunner(commandRunner: mock)
            .run(seat: seat(), worker: worker(), manifest: imageManifest(arrival: .promptDirected), request: req(), runDir: dir)
        XCTAssertEqual(option.status, .failed)
        XCTAssertEqual(option.failureReason, "rate limited")
    }

    func testNonImageCapableManifestIsFailed() async {
        let dir = tempDir()
        let textOnly = DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI,
                                      invoke: .init(command: "claude", args: ["-p", "{{prompt}}"]))
        let mock = MockCommandRunner(scripts: [:])
        let option = await DesignImageRunner(commandRunner: mock)
            .run(seat: seat(), worker: worker(), manifest: textOnly, request: req(), runDir: dir)
        XCTAssertEqual(option.status, .failed)
    }

    // MARK: - Pure helpers

    func testAssembleDesignPromptRedesignPreservesScreen() {
        let p = DesignImageRunner.assembleDesignPrompt(
            DesignSeatRequest(userPrompt: "cleaner", personaId: "minimal", personaDirection: "whitespace",
                              targetShape: .mobile, screenshotPath: "/tmp/before.png"))
        XCTAssertTrue(p.contains("/tmp/before.png"))
        XCTAssertTrue(p.contains("information architecture"))
        XCTAssertTrue(p.contains("vertical mobile layout"))
    }

    func testAssembleDesignPromptGreenfieldHasNoScreenshot() {
        let p = DesignImageRunner.assembleDesignPrompt(
            DesignSeatRequest(userPrompt: "a settings screen", personaId: "bold", personaDirection: "loud",
                              targetShape: .desktop))
        XCTAssertFalse(p.contains("attached screenshot"))
        XCTAssertTrue(p.contains("wide desktop layout"))
    }

    func testResolveArgsKeepsPromptAsOneElement() {
        let args = DesignImageRunner.resolveArgs(["-p", "{{prompt}}", "--cwd", "{{runDir}}", "-m", "{{model}}"],
                                                 prompt: "a b c", model: "grok-build", runDir: "/run")
        XCTAssertEqual(args, ["-p", "a b c", "--cwd", "/run", "-m", "grok-build"])
    }

    func testIsValidImageMagicBytes() {
        let dir = tempDir()
        let png = dir.appendingPathComponent("a.png"); writePNG(at: png)
        let jpeg = dir.appendingPathComponent("b.jpg"); try? Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00]).write(to: jpeg)
        let text = dir.appendingPathComponent("c.txt"); try? Data("not an image".utf8).write(to: text)
        XCTAssertTrue(DesignImageRunner.isValidImage(at: png))
        XCTAssertTrue(DesignImageRunner.isValidImage(at: jpeg))
        XCTAssertFalse(DesignImageRunner.isValidImage(at: text))
        XCTAssertFalse(DesignImageRunner.isValidImage(at: dir.appendingPathComponent("missing.png")))
    }
}
