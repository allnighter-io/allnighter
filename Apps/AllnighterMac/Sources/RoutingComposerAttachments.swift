import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

// Attachment capture and chip helpers (CM-S09). State owner: RoutingComposer.

extension RoutingComposer {

    // Cursor-style attachment row: images are bigger thumbnail tiles (no label, hover-X
    // top-right, click to view); a captured .txt keeps a compact doc chip. The attachment is
    // the durable thing; it travels with the run to every worker.
    var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(attachments) { att in
                    ComposerAttachmentTile(
                        attachment: att,
                        thumb: attachmentThumbs[att.id],
                        onRemove: { removeAttachment(att) },
                        onOpen: { openAttachment(att) }
                    )
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    /// Freeze a pasted clipboard image to a temp PNG and add a chip. Returns true so the
    /// text view consumes the paste (no beep, no empty insert). `name` is the Finder
    /// filename for a copied image file, else "Pasted image".
    func captureImage(_ image: NSImage, name: String) -> Bool {
        guard let frozen = ComposerImageFreezer.freeze(image: image) else { return false }
        let displayName = name.isEmpty ? frozen.name : name
        addAttachment(fileURL: frozen.url, displayName: displayName, thumb: frozen.thumb)
        return true
    }

    /// A long paste → capture to a temp .txt and add a chip, keeping the editor clean.
    /// The captured text is delivered to every worker as run context on send.
    func captureLongText(_ text: String) -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-composer-freeze", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("paste-\(UUID().uuidString).txt")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return false }
        let att = ComposeAttachment(
            id: UUID().uuidString, fileURL: url,
            displayName: ComposerPasteContract.chipLabel(charCount: text.count), kind: .text)
        attachments.append(att)
        composerFocused = true
        return true
    }

    /// Paperclip → pick image files. Each is frozen to a temp PNG and added as a chip.
    func pickImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic, .image]
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let frozen = ComposerImageFreezer.freeze(fileURL: url) else { continue }
            addAttachment(fileURL: frozen.url, displayName: frozen.name, thumb: frozen.thumb)
        }
    }

    func addAttachment(fileURL: URL, displayName: String, thumb: NSImage?) {
        let att = ComposeAttachment(id: UUID().uuidString, fileURL: fileURL, displayName: displayName, kind: .image)
        attachments.append(att)
        if let thumb { attachmentThumbs[att.id] = thumb }
        composerFocused = true
    }

    func removeAttachment(_ att: ComposeAttachment) {
        attachments.removeAll { $0.id == att.id }
        attachmentThumbs[att.id] = nil
        try? FileManager.default.removeItem(at: att.fileURL)
    }

    /// Click an attachment to view it — opens the frozen file in the default viewer
    /// (Preview for images, the editor for a captured .txt).
    func openAttachment(_ att: ComposeAttachment) {
        NSWorkspace.shared.open(att.fileURL)
    }
}
