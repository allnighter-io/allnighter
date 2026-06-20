import SwiftUI
import AppKit

// MARK: - ALTextEditor
//
// Multiline field with ink-primary caret + selection — not system accent blue.
// Height starts at one line and grows with content up to maxHeight (Cursor-style).

enum ComposeEditorMetrics {
  static let lineHeight: CGFloat = 18
  static let verticalInset: CGFloat = 8
  /// One line of 13pt body + container inset.
  static let minHeight: CGFloat = lineHeight + verticalInset
  static let maxHeight: CGFloat = 120
}

enum ALTextEditorCommand {
    case returnKey
    case escape
    case moveUp
    case moveDown
}

struct ALTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var isFocused: Binding<Bool>?
    var minHeight: CGFloat = ComposeEditorMetrics.minHeight
    var maxHeight: CGFloat = ComposeEditorMetrics.maxHeight
    var onCommand: ((ALTextEditorCommand) -> Bool)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            contentHeight: $contentHeight,
            isFocused: isFocused,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onCommand: onCommand
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        if let textView = scroll.documentView as? NSTextView {
            style(textView)
            textView.delegate = context.coordinator
            textView.string = text
        }
        context.coordinator.scrollView = scroll
        DispatchQueue.main.async { context.coordinator.refreshHeight() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.minHeight = minHeight
        context.coordinator.maxHeight = maxHeight
        context.coordinator.onCommand = onCommand
        style(textView)
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.refreshHeight()
        if isFocused?.wrappedValue == true, scroll.window?.firstResponder !== textView {
            scroll.window?.makeFirstResponder(textView)
        }
    }

    private func style(_ textView: NSTextView) {
        let ink = NSColor(ALColor.textPrimary)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = ink
        textView.insertionPointColor = ink
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(ALColor.active),
            .foregroundColor: ink,
        ]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.focusRingType = .none
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var contentHeight: Binding<CGFloat>
        var isFocused: Binding<Bool>?
        var minHeight: CGFloat
        var maxHeight: CGFloat
        var onCommand: ((ALTextEditorCommand) -> Bool)?
        weak var scrollView: NSScrollView?

        init(
            text: Binding<String>,
            contentHeight: Binding<CGFloat>,
            isFocused: Binding<Bool>?,
            minHeight: CGFloat,
            maxHeight: CGFloat,
            onCommand: ((ALTextEditorCommand) -> Bool)?
        ) {
            self.text = text
            self.contentHeight = contentHeight
            self.isFocused = isFocused
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.onCommand = onCommand
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            refreshHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return onCommand?(.returnKey) ?? false
            case #selector(NSResponder.cancelOperation(_:)):
                return onCommand?(.escape) ?? false
            case #selector(NSResponder.moveUp(_:)):
                return onCommand?(.moveUp) ?? false
            case #selector(NSResponder.moveDown(_:)):
                return onCommand?(.moveDown) ?? false
            default:
                return false
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
        }

        func refreshHeight() {
            guard let scrollView,
                  let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let width = max(scrollView.bounds.width, 1)
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset.height * 2
            let measured = ceil(used.height + inset)
            let clamped = min(max(measured, minHeight), maxHeight)
            let scrollable = measured > maxHeight

            scrollView.hasVerticalScroller = scrollable
            if scrollable {
                textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            } else {
                textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: clamped)
            }

            if abs(contentHeight.wrappedValue - clamped) > 0.5 {
                contentHeight.wrappedValue = clamped
            }
        }
    }
}
