import SwiftUI
import AppKit

/// A read-only, fully selectable text view backed by a native `NSTextView`. Unlike
/// SwiftUI's per-block markdown rendering (where selection can't cross blocks), this is ONE
/// text run — drag-select anything, across paragraphs/headings/code. Used for the "raw"
/// view of a chat/answer. On a deliberate drag-select (mouse-up with a non-empty selection)
/// it auto-copies and reports the text (for a "Copied" toast). Self-sizing: it reports its
/// content height so it lays out inline in the scrolling thread.
struct SelectableText: NSViewRepresentable {
    let text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    /// Called after an auto-copy fires (the copied string), so the host can flash "Copied".
    var onCopied: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onCopied: onCopied) }

    func makeNSView(context: Context) -> AutoCopyTextView {
        let tv = AutoCopyTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.onCopied = { [weak coordinator = context.coordinator] in coordinator?.onCopied?($0) }
        apply(tv)
        return tv
    }

    func updateNSView(_ tv: AutoCopyTextView, context: Context) {
        context.coordinator.onCopied = onCopied
        tv.onCopied = { [weak coordinator = context.coordinator] in coordinator?.onCopied?($0) }
        if tv.string != text || tv.font != font {
            apply(tv)
            tv.invalidateIntrinsicContentSize()
        }
    }

    private func apply(_ tv: AutoCopyTextView) {
        tv.string = text
        tv.font = font
        tv.textColor = NSColor(ALColor.textPrimary)
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor(ALColor.accent).withAlphaComponent(0.35),
            .foregroundColor: NSColor(ALColor.textPrimary),
        ]
    }

    final class Coordinator: NSObject {
        var onCopied: ((String) -> Void)?
        init(onCopied: ((String) -> Void)?) { self.onCopied = onCopied }
    }
}

/// NSTextView that auto-copies a deliberate drag-selection on mouse-up and self-sizes to
/// its content height.
final class AutoCopyTextView: NSTextView {
    var onCopied: ((String) -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let range = selectedRange()
        guard range.length > 0 else { return }
        let selected = (string as NSString).substring(with: range)
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(selected, forType: .string)
        onCopied?(selected)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}
