import SwiftUI
import AllnighterMarkdown

/// Allnighter's single Markdown view — renders agent output (Inbox replies + the
/// Team Run Floor) through our forked `AllnighterMarkdown` engine, themed to our
/// tokens for Cursor-grade rendering. One renderer everywhere = one consistent
/// experience. (Theme fidelity lands next; this wires the engine in.)
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.allnighter)
            .textSelection(.enabled)
    }
}
