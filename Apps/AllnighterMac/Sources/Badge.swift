import SwiftUI
import AppKit

// MARK: - Badge
//
// Pill, tinted surface + matching text, optional leading dot.
// Spec: handoff §Badge.

struct Badge: View {
    enum Tone: Sendable { case positive, accent, neutral, warning, danger }

    let text: String
    var tone: Tone = .neutral
    var dot: Bool = false
    var mono: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(dotColor).frame(width: 6, height: 6) }
            Text(text).font((mono ? ALFont.monoSm : ALFont.caption).weight(.semibold))
        }
        .padding(.horizontal, 8)
        .frame(height: 19)
        .foregroundStyle(textColor)
        .background(fill, in: Capsule())
    }

    private var fill: Color {
        switch tone {
        case .positive: ALColor.successSurface
        case .accent: ALColor.accentSurface
        case .neutral: ALColor.active
        case .warning: ALColor.warningSurface
        case .danger: ALColor.dangerSurface
        }
    }
    private var textColor: Color {
        switch tone {
        case .positive: ALPalette.green400
        case .accent: ALColor.accentText
        case .neutral: ALColor.textMuted
        case .warning: ALPalette.yellow400
        case .danger: ALPalette.red400
        }
    }
    private var dotColor: Color {
        switch tone {
        case .positive: ALColor.statusDone
        case .accent: ALColor.accent
        case .neutral: ALColor.textFaint
        case .warning: ALColor.statusTimeout
        case .danger: ALColor.statusFailed
        }
    }
}

