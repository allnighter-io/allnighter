import SwiftUI
import AllnighterCore

/// Hero zoom chart — "Normally" vs "With boost" bucket anatomy (mockup SSOT).
struct BoostWindowZoomChart: View {
    let windowStart: Int
    let resetMid: Int
    let displayState: BoostWindowDisplayState
    let enabled: Bool

    private let labelWidth: CGFloat = 104
    private let chartHeight: CGFloat = 196
    private let blockHeight: CGFloat = 54
    private let normRowY: CGFloat = 32
    private let boostRowY: CGFloat = 114
    private let axisY: CGFloat = 180

    private var windowEnd: Int { BoostWindowTiming.windowEnd(windowStart) }
    private var showsBoostTrack: Bool {
        enabled && displayState != .noQuietRunUp && displayState != .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            chartCanvas
        }
        .overlay {
            if displayState == .estimated {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(ALColor.borderDefault)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Same 5 hours")
                .font(ALFont.sans(12, .bold))
                .foregroundStyle(ALColor.textSecondary)
            Spacer()
            Text("\(formatFullClock(windowStart)) – \(formatFullClock(windowEnd))")
                .font(ALFont.mono(11.5, .semibold))
                .foregroundStyle(ALColor.textFaint)
        }
    }

    // MARK: - Canvas

    private var chartCanvas: some View {
        GeometryReader { geo in
            let trackW = max(0, geo.size.width - labelWidth)
            let wasteX = labelWidth + trackW
            let freshX = labelWidth + trackW * 0.5

            ZStack(alignment: .topLeading) {
                rowLabels

                normalBucket(trackWidth: trackW)
                resetMarker(
                    chip: "reset \(formatShort(windowEnd)) · too late",
                    tone: .muted,
                    line: AnyView(dashedResetLine.frame(width: 2, height: 58)),
                    x: wasteX,
                    y: 28
                )

                if showsBoostTrack {
                    seededBucket(trackWidth: trackW)
                    freshBucket(trackWidth: trackW)
                    resetMarker(
                        chip: "fresh reset · \(formatShort(resetMid))",
                        tone: .fresh,
                        line: AnyView(
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ALColor.accent)
                                .frame(width: 2, height: 58)
                                .shadow(color: ALColor.accent.opacity(0.5), radius: 6, x: 0, y: 0)
                        ),
                        x: freshX,
                        y: 110
                    )
                } else {
                    fallbackBoostBucket(trackWidth: trackW)
                }

                hourAxis(trackWidth: trackW)
            }
        }
        .frame(height: chartHeight)
    }

    private var rowLabels: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Normally")
                    .font(ALFont.sans(12, .bold))
                    .foregroundStyle(ALColor.textMuted)
                Text("1 bucket")
                    .font(ALFont.mono(10, .medium))
                    .foregroundStyle(ALColor.textFaint)
            }
            .frame(width: labelWidth, alignment: .leading)
            .offset(y: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("With ")
                    Text("boost").foregroundStyle(ALPalette.amber300)
                }
                .font(ALFont.sans(12, .bold))
                .foregroundStyle(ALColor.accentText)
                Text(showsBoostTrack ? "2 buckets" : "1 bucket")
                    .font(ALFont.mono(10, .medium))
                    .foregroundStyle(ALColor.textFaint)
            }
            .frame(width: labelWidth, alignment: .leading)
            .offset(y: 130)
        }
    }

    // MARK: - Buckets

    private func normalBucket(trackWidth: CGFloat) -> some View {
        bucketBlock(
            title: "One bucket",
            subtitle: "\(formatShort(windowStart))–\(formatShort(windowEnd))",
            style: .normal
        )
        .frame(width: trackWidth, height: blockHeight)
        .offset(x: labelWidth, y: normRowY)
    }

    private func seededBucket(trackWidth: CGFloat) -> some View {
        bucketBlock(
            title: "Seeded bucket",
            subtitle: "opened while idle",
            style: .seeded
        )
        .frame(width: trackWidth * 0.5, height: blockHeight)
        .offset(x: labelWidth, y: boostRowY)
    }

    private func freshBucket(trackWidth: CGFloat) -> some View {
        bucketBlock(
            title: "Fresh bucket",
            subtitle: "fresh again",
            style: .fresh
        )
        .frame(width: trackWidth * 0.5, height: blockHeight)
        .overlay(alignment: .topTrailing) {
            Text("+1 bucket")
                .font(ALFont.mono(9, .heavy))
                .tracking(0.36)
                .textCase(.uppercase)
                .foregroundStyle(ALColor.textOnAmber)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(ALColor.accent))
                .shadow(color: ALColor.accent.opacity(0.4), radius: 4, x: 0, y: 2)
                .offset(x: -8, y: -10)
        }
        .offset(x: labelWidth + trackWidth * 0.5, y: boostRowY)
    }

    private func fallbackBoostBucket(trackWidth: CGFloat) -> some View {
        bucketBlock(
            title: "One bucket",
            subtitle: "nothing to seed",
            style: .seeded
        )
        .frame(width: trackWidth, height: blockHeight)
        .offset(x: labelWidth, y: boostRowY)
    }

    private enum BucketStyle { case normal, seeded, fresh }

    private func bucketBlock(title: String, subtitle: String, style: BucketStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ALFont.sans(12.5, .bold))
                .foregroundStyle(titleColor(style))
                .lineLimit(1)
            Text(subtitle)
                .font(ALFont.mono(10))
                .foregroundStyle(subtitleColor(style))
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(style))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor(style), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if style == .fresh {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ALPalette.amber500.opacity(0.2), lineWidth: 1)
                    .padding(1)
                    .blendMode(.plusLighter)
            }
        }
        .shadow(color: style == .fresh ? ALColor.accent.opacity(0.28) : .clear, radius: 14, x: 0, y: 0)
    }

    private func titleColor(_ style: BucketStyle) -> Color {
        switch style {
        case .fresh: ALPalette.amber300
        case .normal, .seeded: ALColor.textSecondary
        }
    }

    private func subtitleColor(_ style: BucketStyle) -> Color {
        style == .fresh ? ALPalette.amber400 : ALColor.textFaint
    }

    private func backgroundColor(_ style: BucketStyle) -> Color {
        switch style {
        case .normal: ALPalette.ink600
        case .seeded: ALColor.active
        case .fresh: ALColor.accentSurface
        }
    }

    private func borderColor(_ style: BucketStyle) -> Color {
        switch style {
        case .normal: ALColor.borderStrong
        case .seeded: ALColor.borderDefault
        case .fresh: ALColor.accent.opacity(0.5)
        }
    }

    // MARK: - Markers

    private enum ChipTone { case muted, fresh }

    private func resetMarker(chip: String, tone: ChipTone, line: AnyView, x: CGFloat, y: CGFloat) -> some View {
        ZStack(alignment: .top) {
            line
            resetChip(text: chip, tone: tone)
                .fixedSize()
                .offset(y: -22)
        }
        .position(x: x, y: y + 29)
    }

    private func resetChip(text: String, tone: ChipTone) -> some View {
        HStack(spacing: 5) {
            if tone == .fresh {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(ALFont.mono(10, .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(tone == .fresh ? ALColor.accent : ALColor.active)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tone == .fresh ? Color.clear : ALColor.borderDefault, lineWidth: 1)
        )
        .foregroundStyle(tone == .fresh ? ALColor.textOnAmber : ALColor.textMuted)
    }

    private var dashedResetLine: some View {
        GeometryReader { geo in
            Path { path in
                let mid = geo.size.width / 2
                var y: CGFloat = 0
                while y < geo.size.height {
                    path.move(to: CGPoint(x: mid, y: y))
                    path.addLine(to: CGPoint(x: mid, y: min(y + 4, geo.size.height)))
                    y += 8
                }
            }
            .stroke(ALPalette.ink400, lineWidth: 2)
        }
    }

    // MARK: - Axis

    private func hourAxis(trackWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(axisTicks, id: \.self) { tick in
                let frac = CGFloat(tick - windowStart) / CGFloat(BoostWindowSettings.windowLengthMinutes)
                Text(formatShort(tick))
                    .font(ALFont.mono(10))
                    .foregroundStyle(ALColor.textFaint)
                    .fixedSize()
                    .offset(x: labelWidth + frac * trackWidth - 12, y: axisY)
            }
        }
    }

    private var axisTicks: [Int] {
        var ticks: [Int] = []
        var t = windowStart
        while t <= windowEnd + 1 {
            ticks.append(t)
            t += 60
        }
        return ticks
    }

    // MARK: - Clock

    private func formatFullClock(_ minutes: Int) -> String {
        let m = BoostWindowTiming.mod1440(minutes)
        let h = m / 60
        let min = m % 60
        let period = h >= 12 ? "PM" : "AM"
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, min, period)
    }

    /// Compact axis / chip times — matches mockup `fmtShort` (`8a`, `10:30a`).
    private func formatShort(_ minutes: Int) -> String {
        let m = BoostWindowTiming.mod1440(minutes)
        let h = m / 60
        let min = m % 60
        let ap = h < 12 ? "a" : "p"
        var hour12 = h % 12
        if hour12 == 0 { hour12 = 12 }
        if min == 0 { return "\(hour12)\(ap)" }
        return String(format: "%d:%02d\(ap)", hour12, min)
    }
}
