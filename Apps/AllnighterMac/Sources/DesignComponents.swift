import SwiftUI

// Allnighter signature SwiftUI components, built on AllnighterTokens (AL*).
// Swift mirror of docs/design-system/components/ + the team handoff spec
// (docs/gui/surfaces/council/handoff.md). Visual SSOT: docs/design-system/.

// MARK: - StatusPill
//
// The signature run-status chip: dot + label. The `running` dot PULSES
// (ALMotion.pulse). Spec: handoff §StatusPill, components/product/StatusPill.

struct StatusPill: View {
    enum Kind: Sendable, CaseIterable { case queued, running, done, failed, timedOut }

    let kind: Kind
    var label: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .opacity(kind == .running && pulsing ? 0.45 : 1)
            Text(label ?? defaultLabel)
                .font(ALFont.caption.weight(.semibold))
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 20)
        .foregroundStyle(textColor)
        .background(fillColor, in: Capsule())
        .onAppear {
            guard kind == .running, !reduceMotion else { return }
            withAnimation(ALMotion.pulse) { pulsing = true }
        }
    }

    private var defaultLabel: String {
        switch kind {
        case .queued: "Queued"
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .timedOut: "Timed out"
        }
    }
    private var dotColor: Color {
        switch kind {
        case .queued: ALColor.statusQueued
        case .running: ALColor.statusRunning
        case .done: ALColor.statusDone
        case .failed: ALColor.statusFailed
        case .timedOut: ALColor.statusTimeout
        }
    }
    private var fillColor: Color {
        switch kind {
        case .queued: ALColor.active
        case .running: ALColor.infoSurface
        case .done: ALColor.successSurface
        case .failed: ALColor.dangerSurface
        case .timedOut: ALColor.warningSurface
        }
    }
    private var textColor: Color {
        switch kind {
        case .queued: ALColor.textMuted
        case .running: ALPalette.blue400
        case .done: ALPalette.green400
        case .failed: ALPalette.red400
        case .timedOut: ALPalette.yellow400
        }
    }
}

// MARK: - WorkerGlyph
//
// A worker's brand glyph: a tinted square. Brand SVGs (Simple Icons) get
// bundled later; for now SF Symbol fallbacks per handoff §Iconography.

struct WorkerGlyph: View {
    var systemImage: String = "cpu"
    var tint: Color = ALColor.textSecondary
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: ALRadius.md)
            .fill(ALColor.active)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(tint)
            }
    }
}

// MARK: - WorkerChip
//
// Two modes: `selectable` (sidebar panel: glyph + name + model + checkbox) and
// `status` (run grid: glyph + name + model + StatusPill + meta).
// Spec: handoff §WorkerChip, components/product/WorkerChip.

struct WorkerChip: View {
    let name: String
    var model: String? = nil
    var systemImage: String = "cpu"
    var glyphTint: Color = ALColor.textSecondary
    var status: StatusPill.Kind? = nil
    var meta: String? = nil
    var selectable: Bool = false
    var selected: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        if selectable {
            Button { onToggle?() } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            WorkerGlyph(systemImage: systemImage, tint: glyphTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(ALFont.body.weight(.semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .lineLimit(1)
                if let model {
                    Text(model)
                        .font(ALFont.monoSm)
                        .foregroundStyle(ALColor.textFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                if let meta {
                    Text(meta).font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                }
                if let status { StatusPill(kind: status) }
                if selectable { checkBox }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private var checkBox: some View {
        RoundedRectangle(cornerRadius: ALRadius.xs)
            .fill(selected ? ALColor.accent : .clear)
            .frame(width: 18, height: 18)
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.xs)
                    .strokeBorder(selected ? ALColor.accent : ALColor.borderStrong, lineWidth: 1.5)
            }
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(ALColor.textOnAmber)
                }
            }
    }

    private var backgroundColor: Color { ALColor.raised }
    private var borderColor: Color {
        if selected { return ALColor.accentBorder }
        if status == .running { return ALColor.statusRunning.opacity(0.30) }
        return ALColor.borderSubtle
    }
}

// MARK: - Buttons
//
// primary (amber) · secondary · ghost · danger. Pressed scales; primary glows
// on hover. Spec: handoff §Button, components/core/Button.

enum ALButtonVariant: Sendable { case primary, secondary, ghost, danger }

struct AllnighterButtonStyle: ButtonStyle {
    var variant: ALButtonVariant = .primary
    var small: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ALButtonSurface(variant: variant, small: small, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == AllnighterButtonStyle {
    static var alPrimary: Self { .init(variant: .primary) }
    static var alSecondary: Self { .init(variant: .secondary) }
    static var alGhost: Self { .init(variant: .ghost) }
    static var alDanger: Self { .init(variant: .danger) }
    static func alPrimary(small: Bool) -> Self { .init(variant: .primary, small: small) }
    static func alSecondary(small: Bool) -> Self { .init(variant: .secondary, small: small) }
}

private struct ALButtonSurface<Label: View>: View {
    let variant: ALButtonVariant
    var small: Bool = false
    let isPressed: Bool
    @ViewBuilder var label: Label

    @State private var hover = false

    var body: some View {
        label
            .font((small ? ALFont.label : ALFont.body).weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? ALControl.heightSm : ALControl.height)
            .background(background, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .overlay {
                if let border = borderColor {
                    RoundedRectangle(cornerRadius: ALRadius.sm).strokeBorder(border, lineWidth: 1)
                }
            }
            .modifier(GlowIf(active: hover && variant == .primary))
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(ALMotion.fast, value: isPressed)
            .animation(ALMotion.fast, value: hover)
            .onHover { hover = $0 }
    }

    private var foreground: Color {
        switch variant {
        case .primary: ALColor.textOnAmber
        case .secondary: ALColor.textPrimary
        case .ghost: hover ? ALColor.textPrimary : ALColor.textSecondary
        case .danger: Color(hex: 0x220707)
        }
    }
    private var background: Color {
        switch variant {
        case .primary: hover ? ALColor.accentHover : ALColor.accent
        case .secondary: hover ? ALColor.hover : ALColor.surface
        case .ghost: hover ? ALColor.hover : .clear
        case .danger: hover ? ALPalette.red400 : ALPalette.red500
        }
    }
    private var borderColor: Color? {
        switch variant {
        case .secondary: hover ? ALColor.borderStrong : ALColor.borderDefault
        default: nil
        }
    }
}

private struct GlowIf: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        active ? AnyView(content.alGlowAmber()) : AnyView(content)
    }
}

// MARK: - IconButton

struct IconButton: View {
    let systemImage: String
    var accessibilityLabel: String
    var small: Bool = false
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: small ? 12 : 13))
                .foregroundStyle(hover ? ALColor.textPrimary : ALColor.textSecondary)
                .frame(width: small ? ALControl.heightSm : ALControl.height,
                       height: small ? ALControl.heightSm : ALControl.height)
                .background(hover ? ALColor.hover : .clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

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

// MARK: - Card

enum ALCardVariant: Sendable { case `default`, accent, flush }

extension View {
    func alCard(_ variant: ALCardVariant = .default, pad: Bool = true) -> some View {
        modifier(AllnighterCard(variant: variant, pad: pad))
    }
}

struct AllnighterCard: ViewModifier {
    var variant: ALCardVariant = .default
    var pad: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(pad ? ALSpace.s4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(baseFill, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .background(
                variant == .accent ? ALColor.accentSurface : .clear,
                in: RoundedRectangle(cornerRadius: ALRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(borderColor, lineWidth: 1)
            }
            .modifier(ShadowIf(on: variant != .flush))
    }

    private var baseFill: Color { variant == .flush ? ALColor.surface : ALColor.raised }
    private var borderColor: Color { variant == .accent ? ALColor.accentBorder : ALColor.borderSubtle }
}

private struct ShadowIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        on ? AnyView(content.alShadowSm()) : AnyView(content)
    }
}

// MARK: - SegmentedTabs

struct SegmentedTabs: View {
    struct Item: Identifiable, Hashable { let id: String; let label: String; var count: Int? = nil }

    let items: [Item]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSel = item.id == selection
                Button { selection = item.id } label: {
                    HStack(spacing: 5) {
                        Text(item.label)
                        if let c = item.count {
                            Text("\(c)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                        }
                    }
                    .font(ALFont.label.weight(.medium))
                    .foregroundStyle(isSel ? ALColor.textPrimary : ALColor.textMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(isSel ? ALColor.raised : .clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

// MARK: - LiveMark
//
// The brand mark: an amber crescent + a cursor block. Only the block animates:
// idle solid · running blinks · done turns green. Geometry per handoff
// §"The live mark" (100×100 box). NOTE: native rebuild of the brand glyph;
// swap for the bundled vector asset in a later polish pass.

struct LiveMark: View {
    enum Phase: Sendable { case idle, running, done }

    var state: Phase = .idle
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinkOn = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Crescent()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFD79E), Color(hex: 0xFFA630), Color(hex: 0xF0901C)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    style: FillStyle(eoFill: true)
                )
            RoundedRectangle(cornerRadius: size * 0.026)
                .fill(blockColor)
                .frame(width: size * 0.105, height: size * 0.17)
                .offset(x: size * 0.595, y: size * 0.43)
                .opacity(state == .running && !blinkOn ? 0 : 1)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard state == .running, !reduceMotion else { return }
            withAnimation(ALMotion.blink) { blinkOn = false }
        }
    }

    private var blockColor: Color { state == .done ? ALColor.statusDone : Color(hex: 0xFFE9C6) }
}

private struct Crescent: Shape {
    // 100×100 design box: filled circle r32 @ (47,50) MINUS circle r28 @ (62,41).
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
            CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s)
        }
        var p = Path()
        p.addEllipse(in: circle(47, 50, 32))
        p.addEllipse(in: circle(62, 41, 28))
        return p
    }
}

// MARK: - Preview

#Preview("Foundation — tokens & components") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 14) {
            LiveMark(state: .idle)
            LiveMark(state: .running)
            LiveMark(state: .done)
            Text("alln").font(ALFont.h2).foregroundStyle(ALColor.textPrimary)
            Badge(text: "5/5 healthy", tone: .positive, dot: true)
        }
        HStack(spacing: 8) {
            ForEach(StatusPill.Kind.allCases, id: \.self) { StatusPill(kind: $0) }
        }
        HStack(spacing: 10) {
            Button("Run team") {}.buttonStyle(.alPrimary)
            Button("Export Markdown") {}.buttonStyle(.alSecondary)
            Button("Copy") {}.buttonStyle(.alGhost)
            Button("Stop") {}.buttonStyle(.alDanger)
            IconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
        }
        SegmentedTabs(items: [.init(id: "plan", label: "Plan"),
                              .init(id: "members", label: "Worker answers", count: 6)],
                      selection: .constant("plan"))
        VStack(spacing: 8) {
            WorkerChip(name: "Opus 4.8", model: "via claude-code", systemImage: "cpu",
                       glyphTint: ALColor.accent, status: .running, meta: "00:04",
                       selectable: true, selected: true)
            WorkerChip(name: "Grok Build", model: "via grok-cli", systemImage: "terminal",
                       status: .failed, meta: "auth expired")
        }
        Text("Plan ready").font(ALFont.title).foregroundStyle(ALColor.textPrimary).alCard(.accent)
    }
    .padding(24)
    .frame(width: 480)
    .background(ALColor.base)
}
