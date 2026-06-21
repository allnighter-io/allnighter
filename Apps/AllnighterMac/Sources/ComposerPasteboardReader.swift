import AppKit

/// Reads the clipboard for a composer paste, following the product contract proven by the
/// PasteImagePoC: a Finder-copied image FILE comes first (file URL → NSImage), then raw
/// pixel data (screenshot / copied-from-browser), then a text fallback. We deliberately do
/// NOT check `.string` first — many image pasteboards also carry an incidental string, and
/// checking text first would swallow the image (the original bug).
enum ComposerPasteboardReader {
    enum Payload {
        case image(NSImage, suggestedName: String)
        case text(String)
    }

    /// The pasteboard types the NSTextView must ADVERTISE (`readablePasteboardTypes`) so
    /// AppKit keeps Paste enabled for an image-only clipboard — without this, Paste is
    /// greyed out and the custom handler never runs.
    static let readableTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .tiff, .png,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("com.apple.icns"),
        .string,
    ]

    static func read(from pasteboard: NSPasteboard) -> Payload? {
        // 1) Image file(s) — Finder copy, "Copy Image Address"→file, etc.
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL]) ?? []
        for url in urls where url.isFileURL {
            if let image = NSImage(contentsOf: url) {
                let name = url.lastPathComponent.isEmpty ? "Image" : url.lastPathComponent
                return .image(image, suggestedName: name)
            }
        }
        // 2) Raw pixels — screenshot, copied image from a browser/Preview.
        if let image = NSImage(pasteboard: pasteboard) {
            return .image(image, suggestedName: "Pasted image")
        }
        // 3) Plain text fallback.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    /// Whether Paste should be enabled — drives both `validateUserInterfaceItem` (right-click
    /// / main-menu Paste) and is the same contract the handler uses.
    static func canReadImageOrText(from pasteboard: NSPasteboard) -> Bool {
        read(from: pasteboard) != nil
    }
}
