import SwiftUI
import AllnighterMarkdown

extension Theme {
    /// Allnighter's dark, IDE/Cursor-grade Markdown theme, built on our tokens.
    /// Base structure from `.gitHub`, re-colored for the dark canvas. Refined as we
    /// wire it into the Inbox + Floor. `@MainActor` because the block builders use
    /// SwiftUI views (main-actor-isolated) under Swift 6 strict concurrency.
    @MainActor static let allnighter: Theme = Theme.gitHub
        .text {
            ForegroundColor(ALColor.textSecondary)
            BackgroundColor(Color.clear)
            FontSize(14)
        }
        .strong { FontWeight(.semibold) }
        .link { ForegroundColor(ALColor.accentText) }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(ALColor.textPrimary)
            BackgroundColor(ALColor.surface)
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                    ForegroundColor(ALColor.textSecondary)
                }
                .padding(14)
                .background(ALColor.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ALColor.borderSubtle, lineWidth: 1))
                .markdownMargin(top: 8, bottom: 8)
        }
        .blockquote { configuration in
            configuration.label
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(ALColor.accentBorder).frame(width: 2)
                }
                .markdownTextStyle { ForegroundColor(ALColor.textPrimary) }
        }
}
