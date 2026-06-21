import XCTest
import AppKit
@testable import AllnighterMac

/// Proves the paste CONTRACT that was missing (the bug): image file URLs and raw pixels
/// are read as images — even when an incidental string rides along — and the clipboard is
/// reported pasteable so `validateUserInterfaceItem` keeps right-click/menu Paste enabled.
/// NOTE: this is the logic proof; the founder's wall test (copy a real image, paste into
/// the real composer via ⌘V and context menu) remains the acceptance proof.
final class ComposerPasteboardReaderTests: XCTestCase {

    private func tiffData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }

    private func pngData() -> Data {
        NSBitmapImageRep(data: tiffData())!.representation(using: .png, properties: [:])!
    }

    private func scratchPasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("alln-test-\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    func testReadsRawPixelImage() {
        let pb = scratchPasteboard()
        pb.setData(tiffData(), forType: .tiff)
        guard case .image(_, let name)? = ComposerPasteboardReader.read(from: pb) else {
            return XCTFail("a screenshot/pixel clipboard must read as an image")
        }
        XCTAssertEqual(name, "Pasted image")
        XCTAssertTrue(ComposerPasteboardReader.canReadImageOrText(from: pb), "Paste must be enabled")
    }

    func testReadsFinderImageFileWithFilename() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(UUID().uuidString).png")
        try pngData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let pb = scratchPasteboard()
        pb.writeObjects([url as NSURL])
        guard case .image(_, let name)? = ComposerPasteboardReader.read(from: pb) else {
            return XCTFail("a Finder-copied image file must read as an image")
        }
        XCTAssertEqual(name, url.lastPathComponent, "the chip keeps the Finder filename")
    }

    func testImageWinsOverIncidentalString() {
        // The exact original bug: image clipboards often also carry a string; reading text
        // first swallowed the image. Image must win.
        let pb = scratchPasteboard()
        pb.setData(tiffData(), forType: .tiff)
        pb.setString("https://example.com/incidental", forType: .string)
        guard case .image? = ComposerPasteboardReader.read(from: pb) else {
            return XCTFail("image must win over an incidental string")
        }
    }

    func testReadsPlainText() {
        let pb = scratchPasteboard()
        pb.setString("just text", forType: .string)
        guard case .text(let t)? = ComposerPasteboardReader.read(from: pb) else {
            return XCTFail("a text clipboard reads as text")
        }
        XCTAssertEqual(t, "just text")
    }

    func testEmptyClipboardIsNotPasteable() {
        let pb = scratchPasteboard()
        XCTAssertNil(ComposerPasteboardReader.read(from: pb))
        XCTAssertFalse(ComposerPasteboardReader.canReadImageOrText(from: pb))
    }
}
