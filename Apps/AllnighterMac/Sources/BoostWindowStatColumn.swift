import SwiftUI
import AllnighterCore

/// Left stat column for the Boost window hero card (mockup `.num` block).
struct BoostWindowStatColumn: View {
    let enabled: Bool
    let displayState: BoostWindowDisplayState
    let resetMid: Int

    private var boostLive: Bool {
        enabled && displayState != .off && displayState != .noQuietRunUp
    }

    private var bucketTo: String { boostLive ? "2" : "1" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR PEAK 5 HOURS")
                .font(ALFont.sans(11, .bold))
                .tracking(1.1)
                .foregroundStyle(ALColor.textFaint)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("1")
                    .font(ALFont.mono(34, .bold))
                    .foregroundStyle(ALColor.textFaint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(boostLive ? ALColor.accent : ALColor.textFaint)
                Text(bucketTo)
                    .font(ALFont.mono(34, .bold))
                    .foregroundStyle(boostLive ? ALColor.textPrimary : ALColor.textFaint)
                Text("buckets")
                    .font(ALFont.sans(13.5, .semibold))
                    .foregroundStyle(ALColor.textMuted)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 2 }
            }
            .padding(.top, 9)

            HStack(alignment: .center, spacing: 11) {
                glowDot
                Text(boostLive ? "2×" : "1×")
                    .font(ALFont.sans(52, .heavy))
                    .foregroundStyle(boostLive ? ALColor.accentText : ALColor.textFaint)
                    .tracking(-1.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("the capacity")
                        .font(ALFont.sans(13, .semibold))
                        .foregroundStyle(ALColor.textSecondary)
                    if boostLive {
                        Text("same 5 hours")
                            .font(ALFont.sans(13, .semibold))
                            .foregroundStyle(ALColor.accentText)
                    } else {
                        Text("no boost")
                            .font(ALFont.sans(13, .semibold))
                            .foregroundStyle(ALColor.textMuted)
                        Text("nothing to seed")
                            .font(ALFont.sans(13, .semibold))
                            .foregroundStyle(ALColor.textSecondary)
                    }
                }
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 12) {
                Divider().overlay(ALColor.borderSubtle)
                subcopy
                if enabled && displayState == .estimated {
                    Badge(text: "estimated", tone: .warning, dot: false, mono: true)
                }
            }
            .padding(.top, 18)
        }
    }

    private var glowDot: some View {
        Circle()
            .fill(boostLive ? ALColor.accent : ALPalette.ink500)
            .frame(width: 9, height: 9)
            .shadow(
                color: boostLive ? ALColor.accent.opacity(0.5) : .clear,
                radius: boostLive ? 8 : 0,
                x: 0,
                y: 0
            )
            .shadow(
                color: boostLive ? ALColor.accent.opacity(0.16) : .clear,
                radius: boostLive ? 0 : 0,
                x: 0,
                y: 0
            )
            .overlay {
                if boostLive {
                    Circle()
                        .strokeBorder(ALColor.accent.opacity(0.16), lineWidth: 4)
                        .frame(width: 17, height: 17)
                }
            }
    }

    @ViewBuilder
    private var subcopy: some View {
        switch displayState {
        case .off:
            Text("Off by default — enable when you want a mid-window reset.")
                .font(ALFont.sans(12.5))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        case .noQuietRunUp:
            (Text("No quiet run-up. ") + Text("Nothing to seed").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary) + Text(" — move it after some downtime."))
                .font(ALFont.sans(12.5))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        default:
            (Text("Fresh reset lands ") +
             Text(formatClock(resetMid)).fontWeight(.semibold).foregroundStyle(ALColor.textSecondary) +
             Text(" — mid-window, not after."))
                .font(ALFont.sans(12.5))
                .foregroundStyle(ALColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatClock(_ minutes: Int) -> String {
        let m = BoostWindowTiming.mod1440(minutes)
        let h = m / 60
        let min = m % 60
        let period = h >= 12 ? "PM" : "AM"
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, min, period)
    }
}
