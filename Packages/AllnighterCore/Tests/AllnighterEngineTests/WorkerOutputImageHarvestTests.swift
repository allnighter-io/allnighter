import XCTest
import AgentOSTeam
@testable import AllnighterCore
@testable import AllnighterEngine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class WorkerOutputImageHarvestTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harvest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A real, decodable PNG (the ingestor fully decodes — magic bytes alone won't do).
    @discardableResult
    private func writeRealPNG(at url: URL) -> URL {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        try? (data as Data).write(to: url)
        return url
    }

    // MARK: - Candidate extraction

    func testFindsAbsoluteImagePathInProse() {
        let dir = tempDir()
        let png = writeRealPNG(at: dir.appendingPathComponent("cat.png"))
        let prose = """
        Done! I've generated an image of a super cute adorable cat for you.
        The file is saved here:
        \(png.path)
        Want any variations?
        """
        let urls = WorkerOutputImageHarvest.candidateImageURLs(in: [prose], runDirectory: nil)
        XCTAssertEqual(urls.map(\.path), [png.path])
    }

    /// AGY/antigravity wraps the produced image in a `.md` artifact and the answer links only
    /// the `.md` (via a `file://` URL); the real image is `![alt](…jpg)` inside it. Harvest must
    /// follow the artifact and capture the embedded image.
    func testFollowsMarkdownArtifactToEmbeddedImage() {
        let dir = tempDir()
        let png = writeRealPNG(at: dir.appendingPathComponent("vancouver_sunset.png"))
        let artifact = dir.appendingPathComponent("vancouver_sunset.md")
        try? """
        # Vancouver Sunset

        Here is the generated image:

        ![Vancouver Sunset](\(png.path))
        """.write(to: artifact, atomically: true, encoding: .utf8)

        let answer = "I have generated the image. You can view it in the "
            + "[vancouver_sunset.md](file://\(artifact.path)) artifact."
        let urls = WorkerOutputImageHarvest.candidateImageURLs(in: [answer], runDirectory: nil)
        XCTAssertEqual(urls.map(\.path), [png.path], "image embedded in the linked .md is harvested")
    }

    /// The artifact link is kept in the caption (it's a real, openable artifact) — the inner
    /// image path, never shown in the prose, is what gets captured, so the caption is intact.
    func testArtifactCaptionIsPreserved() {
        let dir = tempDir()
        let png = writeRealPNG(at: dir.appendingPathComponent("art.png"))
        let artifact = dir.appendingPathComponent("art.md")
        try? "![art](\(png.path))".write(to: artifact, atomically: true, encoding: .utf8)
        let answer = "Done. See [art.md](file://\(artifact.path))."
        let candidates = WorkerOutputImageHarvest.candidates(in: [answer], runDirectory: nil)
        let cleaned = WorkerOutputImageHarvest.cleanedCaption(
            from: answer, removing: candidates.map(\.token))
        XCTAssertTrue(cleaned.contains("[art.md]"), "the artifact link stays in the caption")
    }

    func testIgnoresPathWithNoFileAndNonImageBytes() {
        let dir = tempDir()
        // Path that doesn't exist on disk.
        let ghost = dir.appendingPathComponent("missing.png").path
        // A ".png" path whose bytes are not a real image — must be rejected.
        let fake = dir.appendingPathComponent("fake.png")
        try? Data("not an image".utf8).write(to: fake)
        let urls = WorkerOutputImageHarvest.candidateImageURLs(
            in: ["see \(ghost) and \(fake.path)"], runDirectory: nil)
        XCTAssertTrue(urls.isEmpty)
    }

    func testResolvesRunRelativePathUnderRunDirectoryOnly() {
        let runDir = tempDir()
        writeRealPNG(at: runDir.appendingPathComponent("option_grok.png"))
        // Relative path resolves under the run dir...
        let resolved = WorkerOutputImageHarvest.candidateImageURLs(
            in: ["result: option_grok.png"], runDirectory: runDir)
        XCTAssertEqual(resolved.count, 1)
        // ...but not when there's no run directory to anchor it.
        let unanchored = WorkerOutputImageHarvest.candidateImageURLs(
            in: ["result: option_grok.png"], runDirectory: nil)
        XCTAssertTrue(unanchored.isEmpty)
    }

    func testDedupesAndCaps() {
        let dir = tempDir()
        let png = writeRealPNG(at: dir.appendingPathComponent("one.png"))
        let urls = WorkerOutputImageHarvest.candidateImageURLs(
            in: ["\(png.path) \(png.path)", "again \(png.path)"], runDirectory: nil)
        XCTAssertEqual(urls.count, 1)
    }

    // MARK: - Caption stripping

    func testCleanedCaptionDropsPathAndDanglingLabel() {
        let path = "/Users/mike/.grok/sessions/%2FUsers%2Fmike/019ef0e9/images/2.jpg"
        let caption = """
        Got it. Refined to a sweet, seductive neighbor vibe — warm, approachable.

        Updated image saved: \(path)
        """
        let cleaned = WorkerOutputImageHarvest.cleanedCaption(from: caption, removing: [path])
        XCTAssertFalse(cleaned.contains(path))
        XCTAssertFalse(cleaned.contains("Updated image saved"))
        XCTAssertTrue(cleaned.hasPrefix("Got it."))
    }

    func testCleanedCaptionStripsOwnLinePath() {
        let path = "/tmp/run/cat.png"
        let caption = "Done!\nThe file is saved here:\n\(path)\nWant variations?"
        let cleaned = WorkerOutputImageHarvest.cleanedCaption(from: caption, removing: [path])
        XCTAssertFalse(cleaned.contains(path))
        XCTAssertFalse(cleaned.contains("saved here"))
        XCTAssertTrue(cleaned.contains("Done!"))
        XCTAssertTrue(cleaned.contains("Want variations?"))
    }

    func testCleanedCaptionIsNoOpWithoutTokens() {
        let caption = "Just text, no image."
        XCTAssertEqual(WorkerOutputImageHarvest.cleanedCaption(from: caption, removing: []), caption)
    }

    // MARK: - Commit into the canonical store

    func testCommitIngestsWorkerGeneratedAttachment() throws {
        let dir = tempDir()
        let png = writeRealPNG(at: dir.appendingPathComponent("cat.png"))
        let threadDir = tempDir()
        let store = ThreadAttachmentStore(threadDirectory: threadDir)

        let refs = WorkerOutputImageHarvest.commit(
            imageURLs: [png], threadId: "t1", store: store,
            startSequence: 0, idFactory: { UUID().uuidString }, now: Date())

        XCTAssertEqual(refs.count, 1)
        let resolved = ThreadAttachmentResolver.resolve(refs: refs, store: store)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertFalse(resolved[0].missing)
        XCTAssertEqual(resolved[0].sourceKind, .workerGenerated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved[0].canonicalPath))
    }

    func testCodexRolloutHarvesterExtractsFunctionCallOutputImage() throws {
        let root = tempDir()
        let sessionId = "019ef0bc-eba8-7e81-ae14-aec8fd52f789"
        let png = writeRealPNG(at: root.appendingPathComponent("source.png"))
        let dataURL = "data:image/png;base64,\(try Data(contentsOf: png).base64EncodedString())"
        let rollout = root.appendingPathComponent("rollout-2026-06-22T12-09-33-\(sessionId).jsonl")
        try rolloutFixture(
            timestamp: "2026-06-22T19:09:40.000Z",
            sessionId: sessionId,
            dataURL: dataURL
        ).write(to: rollout, atomically: true, encoding: .utf8)

        let harvester = CodexRolloutImageHarvester(searchRoots: [root])
        let images = harvester.images(
            sessionId: sessionId,
            after: isoDate("2026-06-22T19:09:30.000Z"),
            before: isoDate("2026-06-22T19:09:50.000Z")
        )

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].mimeType, "image/png")
        XCTAssertEqual(images[0].data, try Data(contentsOf: png))
    }

    func testCodexRolloutDataCandidatesCommitAsWorkerGeneratedAttachments() throws {
        let root = tempDir()
        let sessionId = "codex-session-1"
        let oldPNG = writeRealPNG(at: root.appendingPathComponent("old.png"))
        let currentPNG = writeRealPNG(at: root.appendingPathComponent("current.png"))
        let oldURL = "data:image/png;base64,\(try Data(contentsOf: oldPNG).base64EncodedString())"
        let currentURL = "data:image/png;base64,\(try Data(contentsOf: currentPNG).base64EncodedString())"
        let rollout = root.appendingPathComponent("rollout-2026-06-22T12-09-33-\(sessionId).jsonl")
        try [
            rolloutFixture(timestamp: "2026-06-22T18:59:00.000Z", sessionId: sessionId, dataURL: oldURL),
            rolloutFixture(timestamp: "2026-06-22T19:09:40.000Z", sessionId: sessionId, dataURL: currentURL),
        ].joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let run = TeamRun(
            id: "run1",
            prompt: "generate an image",
            status: .complete,
            workers: [TestSupport.seat("chatgpt")],
            answers: [
                TeamAnswer(
                    memberId: "chatgpt#0",
                    modelId: "chatgpt",
                    role: "answer",
                    result: WorkerRunResult(
                        status: .done,
                        output: "Here is the generated image.",
                        capturedSessionId: sessionId,
                        timing: RunTiming(
                            startedAt: isoDate("2026-06-22T19:09:30.000Z"),
                            finishedAt: isoDate("2026-06-22T19:09:50.000Z")
                        )
                    )
                )
            ],
            createdAt: isoDate("2026-06-22T19:09:30.000Z")
        )
        let models = [TestSupport.worker("chatgpt", driverId: "codex")]
        let images = WorkerOutputImageHarvest.codexRolloutDataCandidates(
            run: run,
            models: models,
            harvester: CodexRolloutImageHarvester(searchRoots: [root])
        )
        XCTAssertEqual(images.count, 1, "only images inside the worker answer window are harvested")

        let threadDir = tempDir()
        let store = ThreadAttachmentStore(threadDirectory: threadDir)
        let refs = WorkerOutputImageHarvest.commit(
            dataCandidates: images,
            threadId: "t1",
            store: store,
            startSequence: 0,
            idFactory: { "att-\(UUID().uuidString)" },
            now: isoDate("2026-06-22T19:10:00.000Z")
        )

        XCTAssertEqual(refs.count, 1)
        let resolved = ThreadAttachmentResolver.resolve(refs: refs, store: store)
        XCTAssertEqual(resolved.first?.sourceKind, .workerGenerated)
        XCTAssertEqual(resolved.first?.missing, false)
    }

    /// The real generation shape: a `response_item` of type `image_generation_call` whose
    /// `result` is RAW base64 (no `data:` prefix). This is what was missed — the harvester
    /// only handled `function_call_output`/`input_image` (which is `view_image`, not gen).
    func testCodexRolloutHarvesterExtractsImageGenerationCall() throws {
        let root = tempDir()
        let sessionId = "019ef16f-gen-session"
        let png = writeRealPNG(at: root.appendingPathComponent("gen.png"))
        let rawB64 = try Data(contentsOf: png).base64EncodedString()
        let rollout = root.appendingPathComponent("rollout-2026-06-22T15-25-07-\(sessionId).jsonl")
        try """
        {"timestamp":"2026-06-22T22:25:07.000Z","type":"session_meta","payload":{"id":"\(sessionId)","cwd":"/tmp/proj","originator":"allnighter"}}
        {"timestamp":"2026-06-22T22:26:01.000Z","type":"response_item","payload":{"type":"image_generation_call","id":"ig_1","status":"completed","result":"\(rawB64)"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)

        let harvester = CodexRolloutImageHarvester(searchRoots: [root])
        // By captured session id.
        let bySession = harvester.images(
            sessionId: sessionId,
            after: isoDate("2026-06-22T22:25:00.000Z"),
            before: isoDate("2026-06-22T22:26:30.000Z"))
        XCTAssertEqual(bySession.count, 1)
        XCTAssertEqual(bySession[0].mimeType, "image/png")
        XCTAssertEqual(bySession[0].data, try Data(contentsOf: png))

        // By cwd alone — the real-world path, since Codex's vendorSessionId is not captured.
        let byCwd = harvester.images(sessionId: nil, cwd: "/tmp/proj", after: nil, before: nil)
        XCTAssertEqual(byCwd.count, 1, "rollout located by session_meta.cwd when no session id")
    }

    /// The hot-path optimization: locate the rollout via the date-partitioned dir
    /// (sessions/YYYY/MM/DD) without a recursive walk over the whole session history.
    func testRolloutURLUsesDatePartitionFastPath() throws {
        let root = tempDir()
        let sessionId = "019ef-fastpath"
        let when = isoDate("2026-06-22T22:00:00.000Z")
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: when)
        let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("rollout-2026-06-22T15-00-00-\(sessionId).jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        let harvester = CodexRolloutImageHarvester(searchRoots: [root])
        XCTAssertEqual(harvester.rolloutURL(sessionId: sessionId, near: when)?.lastPathComponent,
                       file.lastPathComponent, "found via the date-partition fast path")
    }

    private func rolloutFixture(timestamp: String, sessionId: String, dataURL: String) -> String {
        """
        {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(sessionId)","cwd":"/tmp","originator":"allnighter"}}
        {"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"function_call_output","call_id":"call_image","output":[{"type":"input_image","image_url":"\(dataURL)"}]}}
        """
    }

    private func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }
}
