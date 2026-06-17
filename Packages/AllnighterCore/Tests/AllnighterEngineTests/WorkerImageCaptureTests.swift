import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class WorkerImageCaptureTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wio-capture-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePNG(at url: URL) {
        let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01]
        try? Data(bytes).write(to: url)
    }

    private func imageGen(arrival: DriverManifest.ImageGen.Arrival) -> DriverManifest.ImageGen {
        .init(
            args: ["-p", "{{prompt}}"],
            promptTemplate: "Generate: {{designPrompt}} Save to {{imageOut}}",
            arrival: arrival,
            stdoutPathRegex: #"PATH=(\S+)"#
        )
    }

    func testPromptDirectedSuccess() {
        let dir = tempDir()
        let out = dir.appendingPathComponent("out.png")
        writePNG(at: out)
        let result = WorkerImageCapture.capture(
            imageGen: imageGen(arrival: .promptDirected),
            stdout: "done",
            intendedOut: out
        )
        XCTAssertEqual(result.normalizedImageURL, out)
        XCTAssertNil(result.failureReason)
    }

    func testStdoutPathSuccess() {
        let dir = tempDir()
        let out = dir.appendingPathComponent("out.png")
        let source = dir.appendingPathComponent("src.png")
        writePNG(at: source)
        let result = WorkerImageCapture.capture(
            imageGen: imageGen(arrival: .stdoutPath),
            stdout: "PATH=\(source.path)",
            intendedOut: out
        )
        XCTAssertEqual(result.normalizedImageURL, out)
        XCTAssertTrue(WorkerImageCapture.isValidImage(at: out))
    }

    func testPathOnlyCaptionStripped() {
        let dir = tempDir()
        let out = dir.appendingPathComponent("out.png")
        writePNG(at: out)
        let result = WorkerImageCapture.capture(
            imageGen: imageGen(arrival: .promptDirected),
            stdout: "\(out.path)\nHere is your cat photo.",
            intendedOut: out
        )
        XCTAssertEqual(result.captionText, "Here is your cat photo.")
    }

    func testInvalidBytesFail() {
        let dir = tempDir()
        let out = dir.appendingPathComponent("out.png")
        try? Data("not-image".utf8).write(to: out)
        let result = WorkerImageCapture.capture(
            imageGen: imageGen(arrival: .promptDirected),
            stdout: "done",
            intendedOut: out
        )
        XCTAssertNil(result.normalizedImageURL)
        XCTAssertNotNil(result.failureReason)
    }

    func testSessionIdRegexDoesNotScrapeVendorFolders() {
        let dir = tempDir()
        let out = dir.appendingPathComponent("out.png")
        let vendor = dir.appendingPathComponent(".grok/sessions/x/images/1.jpg")
        try? FileManager.default.createDirectory(at: vendor.deletingLastPathComponent(), withIntermediateDirectories: true)
        writePNG(at: vendor)
        let gen = DriverManifest.ImageGen(
            args: ["-p", "{{prompt}}"],
            promptTemplate: "x",
            arrival: .promptDirected,
            sessionIdRegex: #"SESSION=(\S+)"#
        )
        let result = WorkerImageCapture.capture(
            imageGen: gen,
            stdout: "SESSION=abc-123",
            intendedOut: out
        )
        XCTAssertNil(result.normalizedImageURL)
        XCTAssertEqual(result.sessionId, "abc-123")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }
}

final class ChatImageIntentTests: XCTestCase {
    private func imageManifest() -> DriverManifest {
        DriverManifest(
            id: "grok", displayName: "Grok", kind: .headlessCLI,
            invoke: .init(command: "grok", args: ["-p", "{{prompt}}"]),
            imageGen: .init(args: ["-p", "{{prompt}}"], promptTemplate: "x", arrival: .promptDirected)
        )
    }

    func testPositiveExplicitImageRequest() {
        XCTAssertEqual(
            ChatImageIntent.decide(message: "generate an image of a cat", manifest: imageManifest(), hasPriorImageContext: false),
            .imageGen
        )
        XCTAssertEqual(
            ChatImageIntent.decide(message: "return an updated mockup please", manifest: imageManifest(), hasPriorImageContext: false),
            .imageGen
        )
    }

    func testPositiveVisualEditWithPriorContext() {
        XCTAssertEqual(
            ChatImageIntent.decide(message: "make the header bolder", manifest: imageManifest(), hasPriorImageContext: true),
            .imageGen
        )
        XCTAssertEqual(
            ChatImageIntent.decide(message: "more like this but dark mode", manifest: imageManifest(), hasPriorImageContext: true),
            .imageGen
        )
    }

    func testNegativeOpinionQuestionWithPriorContext() {
        XCTAssertEqual(
            ChatImageIntent.decide(message: "what do you think of it?", manifest: imageManifest(), hasPriorImageContext: true),
            .regularText
        )
    }

    func testNegativeTextOnlyToImageCapableWorker() {
        XCTAssertEqual(
            ChatImageIntent.decide(message: "explain the layout choices", manifest: imageManifest(), hasPriorImageContext: false),
            .regularText
        )
    }
}
