import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class AttachmentIngestorTests: XCTestCase {

    private func tinyPNG(width: Int = 8, height: Int = 8) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testIngestProducesStableStoredSha256() throws {
        let png = tinyPNG()
        let ingestor = AttachmentIngestor()
        let a = try ingestor.ingest(data: png, declaredMIME: "image/png", sourceKind: .cliFile)
        let b = try ingestor.ingest(data: png, declaredMIME: "image/png", sourceKind: .cliFile)
        XCTAssertEqual(a.storedSha256, b.storedSha256)
        XCTAssertEqual(a.mimeType, "image/png")
    }

    func testDownscaleWhenLongEdgeExceedsPolicy() throws {
        let png = tinyPNG(width: 3000, height: 1000)
        let ingestor = AttachmentIngestor(policy: .default)
        let result = try ingestor.ingest(data: png, declaredMIME: "image/png", sourceKind: .paste)
        XCTAssertTrue(result.wasDownscaled)
        XCTAssertEqual(max(result.storedWidth, result.storedHeight), 2048)
    }

    func testRejectsUnsupportedType() {
        let ingestor = AttachmentIngestor()
        XCTAssertThrowsError(try ingestor.ingest(
            data: Data("not an image".utf8), declaredMIME: "text/plain", sourceKind: .cliFile
        )) { error in
            XCTAssertEqual(error as? AttachmentError, .unsupportedType)
        }
    }

    func testRejectsInvalidBase64() {
        let ingestor = AttachmentIngestor()
        XCTAssertThrowsError(try ingestor.ingestBase64("%%%", declaredMIME: "image/png")) { error in
            XCTAssertEqual(error as? AttachmentError, .base64Invalid)
        }
    }
}
