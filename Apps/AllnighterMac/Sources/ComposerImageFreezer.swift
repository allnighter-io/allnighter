import AppKit

/// Freezes a composer image (pasted NSImage or a picked file) into a stable temp PNG so
/// the value can't change under us between attach and send, and produces a small
/// thumbnail for the chip. The frozen file is what the run path ingests into the thread's
/// canonical attachment store.
enum ComposerImageFreezer {
    struct Frozen {
        let url: URL
        let name: String
        let thumb: NSImage?
    }

    private static var freezeRoot: URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-composer-freeze", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Freeze a pasted clipboard image.
    static func freeze(image: NSImage) -> Frozen? {
        guard let png = pngData(from: image) else { return nil }
        let url = freezeRoot.appendingPathComponent("paste-\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return Frozen(url: url, name: "Pasted image", thumb: thumbnail(from: image))
    }

    /// Freeze a picked image file (copied so a later edit/delete can't change it).
    static func freeze(fileURL: URL) -> Frozen? {
        guard let image = NSImage(contentsOf: fileURL) else { return nil }
        // Re-encode to PNG so every attachment is a uniform, self-contained file.
        guard let png = pngData(from: image) else { return nil }
        let url = freezeRoot.appendingPathComponent("file-\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return Frozen(url: url, name: fileURL.lastPathComponent, thumb: thumbnail(from: image))
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func thumbnail(from image: NSImage, max: CGFloat = 160) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(max / size.width, max / size.height, 1)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()
        return thumb
    }
}
