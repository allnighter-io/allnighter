import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

/// Shared image ingest pipeline for GUI, CLI, and MCP surfaces.
public struct AttachmentIngestor: Sendable {
    public var policy: AttachmentPolicy

    public init(policy: AttachmentPolicy = .default) {
        self.policy = policy
    }

    public func ingest(
        fileURL: URL,
        sourceKind: AttachmentSourceKind,
        originalName: String? = nil
    ) throws -> IngestedAttachment {
        let data = try Data(contentsOf: fileURL)
        let name = originalName ?? fileURL.lastPathComponent
        return try ingest(data: data, declaredMIME: nil, sourceKind: sourceKind, originalName: name)
    }

    public func ingest(
        data: Data,
        declaredMIME: String?,
        sourceKind: AttachmentSourceKind,
        originalName: String? = nil
    ) throws -> IngestedAttachment {
        guard !data.isEmpty else { throw AttachmentError.decodeFailed }
        if data.count > policy.maxBytesPerImage { throw AttachmentError.tooLarge }

        let sourceSha = sha256(data)
        let sniffed = sniffMIME(data: data, declared: declaredMIME)
        guard isAllowedImageMIME(sniffed) else { throw AttachmentError.unsupportedType }

        #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
        guard let (cgImage, originalWidth, originalHeight) = try decodeImage(data: data) else {
            throw AttachmentError.decodeFailed
        }
        let megapixels = (originalWidth * originalHeight) / 1_000_000
        if megapixels > policy.maxDecodeMegapixels { throw AttachmentError.tooLarge }

        let (scaled, storedWidth, storedHeight, wasDownscaled) = downscaleIfNeeded(
            cgImage, maxLongEdge: policy.maxLongEdgePixels
        )
        guard let pngData = encodePNG(scaled) else { throw AttachmentError.decodeFailed }
        if pngData.count > policy.maxBytesPerImage { throw AttachmentError.tooLarge }

        return IngestedAttachment(
            pngData: pngData,
            mimeType: "image/png",
            byteSize: pngData.count,
            storedSha256: sha256(pngData),
            sourceSha256: sourceSha,
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            storedWidth: storedWidth,
            storedHeight: storedHeight,
            wasDownscaled: wasDownscaled
        )
        #else
        // No platform image codec: image ingest is unsupported off Apple platforms.
        throw AttachmentError.unsupportedType
        #endif
    }

    public func ingestBase64(
        _ base64: String,
        declaredMIME: String?,
        sourceKind: AttachmentSourceKind = .mcpBase64,
        originalName: String? = nil
    ) throws -> IngestedAttachment {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !data.isEmpty else {
            throw AttachmentError.base64Invalid
        }
        return try ingest(data: data, declaredMIME: declaredMIME, sourceKind: sourceKind, originalName: originalName)
    }

    // MARK: - Private

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sniffMIME(data: Data, declared: String?) -> String {
        if let declared, isAllowedImageMIME(declared) { return declared }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count > 12 {
            let webp = String(data: data[8..<12], encoding: .ascii)
            if webp == "WEBP" { return "image/webp" }
        }
        return declared ?? "application/octet-stream"
    }

    private func isAllowedImageMIME(_ mime: String) -> Bool {
        switch mime.lowercased() {
        case "image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp":
            return true
        default:
            return false
        }
    }

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    private func decodeImage(data: Data) throws -> (CGImage, Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return (image, image.width, image.height)
    }

    private func downscaleIfNeeded(
        _ image: CGImage,
        maxLongEdge: Int
    ) -> (CGImage, Int, Int, Bool) {
        let w = image.width
        let h = image.height
        let longEdge = max(w, h)
        guard longEdge > maxLongEdge else { return (image, w, h, false) }

        let scale = CGFloat(maxLongEdge) / CGFloat(longEdge)
        let newW = max(1, Int(CGFloat(w) * scale))
        let newH = max(1, Int(CGFloat(h) * scale))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (image, w, h, false)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let scaled = context.makeImage() else { return (image, w, h, false) }
        return (scaled, newW, newH, true)
    }

    private func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
    #endif
}
