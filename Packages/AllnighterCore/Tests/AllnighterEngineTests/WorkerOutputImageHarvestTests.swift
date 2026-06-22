import XCTest
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
}
