import SwiftUI

/// Centered scrim overlays on the Boost window hero card (mockup `.ov` blocks).
struct BoostWindowHeroOverlay: View {
    enum Style: Equatable {
        case off
        case quiet
        case needsYou(String)
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
                icon
                Text(title)
                    .font(ALFont.sans(17, .heavy))
                    .tracking(-0.17)
                    .foregroundStyle(ALColor.textPrimary)
                description
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
        case .quiet: "No quiet run-up before this window"
        case .needsYou(let name): "\(name) needs you"
        }
    }

    @ViewBuilder
    private var description: some View {
        switch style {
        case .off:
            (Text("Turn it on to land a second fresh bucket in your peak window. ") +
             Text("Off by default").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary) +
             Text(" — it spends a little of your normal subscription."))
        case .quiet:
            (Text("You're already running agents before this slot — there's ") +
             Text("nothing to seed").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary) +
             Text(". Move the window after a quiet stretch."))
        case .needsYou(let name):
            (Text("\(name) showed a sign-in prompt. Allnighter ") +
             Text("stopped instead of auto-confirming").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary) +
             Text(" — sign in to resume."))
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch style {
        case .off:
            overlayIcon(symbol: "moon.fill", tone: .muted)
        case .quiet:
            overlayIcon(symbol: "waveform.path.ecg", tone: .danger)
        case .needsYou:
            overlayIcon(symbol: "exclamationmark.triangle.fill", tone: .warning)
        }
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
