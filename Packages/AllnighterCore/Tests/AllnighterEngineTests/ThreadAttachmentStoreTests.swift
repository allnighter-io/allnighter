import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ThreadAttachmentStoreTests: XCTestCase {

    private func tempThreadDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("att-\(UUID().uuidString)")
    }

    private func tinyPNG() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testAtomicDraftAndAttachmentIndexes() throws {
        let dir = tempThreadDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ThreadAttachmentStore(threadDirectory: dir)
        let now = Date(timeIntervalSince1970: 0)
        _ = try store.ingestDraft(
            data: tinyPNG(), threadId: "t1", sourceKind: .paste, draftId: "d1", now: now
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.draftIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.draftDirectory.appendingPathComponent("d1.png").path))

        let (_, refs) = try store.promoteDrafts(draftIds: ["d1"], threadId: "t1", now: now)
        XCTAssertEqual(refs.map(\.attachmentId), ["d1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.attachmentIndexURL.path))
        let attachment = try XCTUnwrap(store.attachment(for: "d1"))
        try store.verifyHash(for: attachment)
    }

    func testOrphanRecoveryRemovesMissingBytesAndUnindexedFiles() throws {
        let dir = tempThreadDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ThreadAttachmentStore(threadDirectory: dir)
        let now = Date(timeIntervalSince1970: 0)
        _ = try store.ingestDraft(data: tinyPNG(), threadId: "t1", sourceKind: .paste, draftId: "d1", now: now)
        _ = try store.promoteDrafts(draftIds: ["d1"], threadId: "t1", now: now)

        // Orphan file on disk without index row
        try tinyPNG().write(to: store.attachmentsDirectory.appendingPathComponent("orphan.png"))

        // Index row without bytes
        var index = store.loadAttachmentIndex()
        index.attachments.append(TurnAttachment(
            id: "ghost", threadId: "t1", createdAt: now, storagePath: "attachments/ghost.png",
            mimeType: "image/png", byteSize: 1, storedSha256: "00", sourceKind: .paste, wasDownscaled: false
        ))
        try store.saveAttachmentIndex(index)

        let (removedRows, removedFiles) = try store.recoverOrphans()
        XCTAssertEqual(removedRows, 1)
        XCTAssertEqual(removedFiles, 1)
        XCTAssertNil(store.attachment(for: "ghost"))
    }

    func testHashMismatchDetected() throws {
        let dir = tempThreadDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = ThreadAttachmentStore(threadDirectory: dir)
        let now = Date(timeIntervalSince1970: 0)
        _ = try store.ingestDraft(data: tinyPNG(), threadId: "t1", sourceKind: .paste, draftId: "d1", now: now)
        let (attachments, _) = try store.promoteDrafts(draftIds: ["d1"], threadId: "t1", now: now)
        var bad = attachments[0]
        bad.storedSha256 = "deadbeef"
        try store.saveAttachmentIndex(AttachmentIndex(attachments: [bad]))

        XCTAssertThrowsError(try store.verifyHash(for: bad)) { error in
            XCTAssertEqual(error as? AttachmentError, .hashMismatch)
        }
    }
}
