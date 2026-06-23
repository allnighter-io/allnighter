import SwiftUI

/// Centered scrim overlays on the Boost window hero card (mockup `.ov` blocks).
struct BoostWindowHeroOverlay: View {
    enum Style: Equatable {
        case off
        case needsYou(String)
        // Note: "no quiet run-up" is intentionally NOT an overlay — it never blocks the panel.
        // It shows as a small inline note under the slider (see BoostWindowView.softNote).
    }

    let style: Style
    var onEnable: () -> Void = {}

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: 0x0D101A).opacity(0.88))
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.15))

            VStack(spacing: 14) {
                overlayIconView
                Text(title)
                    .font(ALFont.sans(17, .heavy))
                    .tracking(-0.17)
                    .foregroundStyle(ALColor.textPrimary)
                overlayMessage
                    .font(ALFont.sans(13))
                    .foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
                if case .off = style {
                    Button(action: onEnable) {
                        Label("Turn on boost window", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.alPrimary)
                }
            }
            .padding(30)
        }
    }

    private var title: String {
        switch style {
        case .off: "Boost window is off"
        case .needsYou(let name): "\(name) needs you"
        }
    }

    @ViewBuilder
    private var overlayMessage: some View {
        switch style {
        case .off:
            emphasizedMessage(
                "Turn it on to land a second fresh bucket in your peak window. ",
                emphasis: "Off by default",
                suffix: " — it spends a little of your normal subscription."
            )
        case .needsYou(let name):
            emphasizedMessage(
                "\(name) showed a sign-in prompt. Allnighter ",
                emphasis: "stopped instead of auto-confirming",
                suffix: " — sign in to resume."
            )
        }
    }

    @ViewBuilder
    private var overlayIconView: some View {
        switch style {
        case .off:
            overlayIcon(symbol: "moon.fill", tone: .muted)
        case .needsYou:
            overlayIcon(symbol: "exclamationmark.triangle.fill", tone: .warning)
        }
    }

    private func emphasizedMessage(_ prefix: String, emphasis: String, suffix: String) -> Text {
        Text(prefix)
            + Text(emphasis).fontWeight(.semibold).foregroundStyle(ALColor.textSecondary)
            + Text(suffix)
    }

    private func overlayIcon(symbol: String, tone: IconTone) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(tone.foreground)
            .frame(width: 46, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tone.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tone.border, lineWidth: 1)
            )
    }

    private enum IconTone {
        case muted, warning, danger

        var foreground: Color {
            switch self {
            case .muted: ALColor.textMuted
            case .warning: ALPalette.yellow400
            case .danger: ALPalette.red400
            }
        }

        var background: Color {
            switch self {
            case .muted: ALColor.active
            case .warning: ALColor.warningSurface
            case .danger: ALColor.dangerSurface
            }
        }

        var border: Color {
            switch self {
            case .muted: ALColor.borderDefault
            case .warning: ALPalette.yellow500.opacity(0.32)
            case .danger: ALPalette.red500.opacity(0.3)
            }
        }
    }
}
