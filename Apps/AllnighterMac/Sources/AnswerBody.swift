import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

/// Always-visible "Copy" button at the foot of every agent answer. The markdown
/// renderer doesn't reliably support text selection, so this is the dependable way to
/// get an answer onto the clipboard. Shows a "Copied" confirmation.
/// A settled agent answer: rich markdown OR raw selectable source (conversation-wide,
/// toggled by ⌥⌘R / the footer), with a footer carrying the Raw⇄Rendered toggle, an
/// auto-copy "Copied" flash (raw drag-select), and the explicit Copy button.
struct AnswerBody: View {
    @Environment(ThreadsViewModel.self) private var threads
    let markdown: String
    @State private var copiedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if threads.showRawAnswers {
                    SelectableText(text: markdown, onCopied: { _ in flashCopied() })
                } else {
                    MarkdownText(markdown: markdown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if !markdown.isEmpty {
            HStack(spacing: 8) {
                Button { threads.showRawAnswers.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10, weight: .medium))
                        Text(threads.showRawAnswers ? "Rendered" : "Raw").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(ALColor.subtle, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .help(threads.showRawAnswers
                      ? "Show rendered markdown (⌥⌘R)"
                      : "Show raw text — drag to select, auto-copies (⌥⌘R)")

                if copiedFlash {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        Text("Copied").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(ALPalette.green500)
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
                CopyButton(text: markdown)
            }
            .padding(.top, 3)
            .animation(.easeInOut(duration: 0.15), value: copiedFlash)
        }
    }

    private func flashCopied() {
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
    }
}

/// The explicit one-click "Copy this answer" button (shared chrome).
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .medium))
                Text(copied ? "Copied" : "Copy").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(copied ? ALPalette.green500 : ALColor.textMuted)
            .padding(.horizontal, 8).frame(height: 24)
            .background(ALColor.subtle, in: Capsule())
            .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Copy this answer")
    }
}
