import SwiftUI

// Allnighter signature SwiftUI components, built on the Theme tokens. These are
// the Swift mirror of `docs/design-system/components/` — keep names + behavior
// aligned with the spec. Visual SSOT: docs/design-system/. Governance: docs/gui/.

// MARK: - StatusPill
//
// The Council's signature status indicator: a pill with a colored dot.
// `running` blinks — the same heartbeat as the live mark.
// Spec: docs/design-system/components/product/StatusPill.{jsx,prompt.md}

struct StatusPill: View {
    enum Kind: Sendable, CaseIterable { case queued, running, done, failed, timedOut }

    let kind: Kind
    var label: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .opacity(kind == .running && dim ? 0.3 : 1)
            Text(label ?? defaultLabel)
                .font(.alCaption.weight(.semibold))
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 20)
        .foregroundStyle(textColor)
        .background(fillColor, in: Capsule())
        .onAppear {
            guard kind == .running, !reduceMotion else { return }
            withAnimation(Theme.Motion.blink) { dim = true }
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
        case .queued: .alInk400
        case .running: .alBlue500
        case .done: .alGreen500
        case .failed: .alRed500
        case .timedOut: .alYellow500
        }
    }
    private var fillColor: Color {
        switch kind {
        case .queued: .alBgActive
        case .running: .alInfoSurface
        case .done: .alSuccessSurface
        case .failed: .alDangerSurface
        case .timedOut: .alWarningSurface
        }
    }
    private var textColor: Color {
        switch kind {
        case .queued: .alTextMuted
        case .running: .alBlue400
        case .done: .alGreen400
        case .failed: .alRed400
        case .timedOut: .alYellow400
        }
    }
}

// MARK: - WorkerChip
//
// A worker in the panel or the live run grid: glyph · name + model · trailing
// meta / status / selection check.
// Spec: docs/design-system/components/product/WorkerChip.jsx

struct WorkerChip: View {
    let name: String
    var model: String? = nil
    var systemImage: String? = nil
    var status: StatusPill.Kind? = nil
    var meta: String? = nil
    var selectable: Bool = false
    var selected: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        if selectable {
            Button { onToggle?() } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Color.alBgActive)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: systemImage ?? "cpu")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.alTextSecondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.alBody.weight(.semibold))
                    .foregroundStyle(Color.alTextPrimary)
                    .lineLimit(1)
                if let model {
                    Text(model)
                        .font(.alMonoSm)
                        .foregroundStyle(Color.alTextFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                if let meta {
                    Text(meta).font(.alMonoSm).foregroundStyle(Color.alTextMuted)
                }
                if let status {
                    StatusPill(kind: status)
                }
                if selectable {
                    checkBox
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private var checkBox: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.xs)
            .fill(selected ? Color.alAccent : .clear)
            .frame(width: 18, height: 18)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.xs)
                    .strokeBorder(selected ? Color.alAccent : Color.alBorderStrong, lineWidth: 1.5)
            }
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.alTextOnAmber)
                }
            }
    }

    private var backgroundColor: Color { selected ? Color.alAccentSurface : Color.alBgRaised }
    private var borderColor: Color {
        if selected { return .alAccentBorder }
        if status == .running { return Color.alBlue500.opacity(0.30) }
        return .alBorderSubtle
    }
}

// MARK: - Buttons
//
// Spec: docs/design-system/components/core/Button.jsx
// primary (amber) · secondary · ghost · danger. Pressed scales; primary/danger
// glow on hover.

enum ALButtonVariant: Sendable { case primary, secondary, ghost, danger }

struct AllnighterButtonStyle: ButtonStyle {
    var variant: ALButtonVariant = .primary

    func makeBody(configuration: Configuration) -> some View {
        ALButtonSurface(variant: variant, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == AllnighterButtonStyle {
    static var alPrimary: Self { .init(variant: .primary) }
    static var alSecondary: Self { .init(variant: .secondary) }
    static var alGhost: Self { .init(variant: .ghost) }
    static var alDanger: Self { .init(variant: .danger) }
}

private struct ALButtonSurface<Label: View>: View {
    let variant: ALButtonVariant
    let isPressed: Bool
    @ViewBuilder var label: Label

    @State private var hover = false

    var body: some View {
        label
            .font(.alBody.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: Theme.Control.h)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay {
                if let border = borderColor {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(border, lineWidth: 1)
                }
            }
            .alGlowAmber(hover && variant == .primary)
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: Theme.Motion.fast), value: isPressed)
            .animation(.easeOut(duration: Theme.Motion.fast), value: hover)
            .onHover { hover = $0 }
    }

    private var foreground: Color {
        switch variant {
        case .primary: .alTextOnAmber
        case .secondary: .alTextPrimary
        case .ghost: hover ? .alTextPrimary : .alTextSecondary
        case .danger: Color(hex: 0x220707)
        }
    }
    private var background: Color {
        switch variant {
        case .primary: hover ? .alAccentHover : .alAccent
        case .secondary: hover ? .alBgHover : .alBgSurface
        case .ghost: hover ? .alBgHover : .clear
        case .danger: hover ? .alRed400 : .alRed500
        }
    }
    private var borderColor: Color? {
        switch variant {
        case .secondary: hover ? .alBorderStrong : .alBorderDefault
        default: nil
        }
    }
}

// MARK: - Card
//
// Spec: docs/design-system/components/core/Card.jsx
// default (raised) · accent (amber tint) · flush (surface).

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
            .padding(pad ? Theme.Space.s4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(baseFill, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .background(
                variant == .accent ? Color.alAccentSurface : .clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(borderColor, lineWidth: 1)
            }
            .alShadowSm()
    }

    private var baseFill: Color { variant == .flush ? .alBgSurface : .alBgRaised }
    private var borderColor: Color { variant == .accent ? .alAccentBorder : .alBorderSubtle }
}

// MARK: - LiveMark
//
// The brand mark: a crescent + a cursor block. Solid amber = idle, blinking
// amber = running, green = done — the logo IS the activity indicator.
// NOTE: shape approximation of assets/allnighter-glyph-live.svg; replace with
// the real brand glyph (asset catalog) in a later GUI polish pass.

struct LiveMark: View {
    enum Phase: Sendable { case idle, running, done }

    var state: Phase = .idle
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: size * 0.14) {
            Crescent()
                .fill(markColor, style: FillStyle(eoFill: true))
                .frame(width: size * 0.66, height: size)
            RoundedRectangle(cornerRadius: 1)
                .fill(markColor)
                .frame(width: size * 0.17, height: size * 0.44)
                .opacity(state == .running && dim ? 0.3 : 1)
        }
        .onAppear {
            guard state == .running, !reduceMotion else { return }
            withAnimation(Theme.Motion.blink) { dim = true }
        }
    }

    private var markColor: Color { state == .done ? .alGreen500 : .alAmber500 }
}

private struct Crescent: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let d = min(rect.width, rect.height)
        let outer = CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
        p.addEllipse(in: outer)
        let inner = outer.offsetBy(dx: d * 0.32, dy: -d * 0.05).insetBy(dx: d * 0.10, dy: d * 0.10)
        p.addEllipse(in: inner)
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
            Text("allnighter").font(.alH2).foregroundStyle(Color.alTextPrimary)
        }

        HStack(spacing: 8) {
            ForEach(StatusPill.Kind.allCases, id: \.self) { StatusPill(kind: $0) }
        }

        HStack(spacing: 10) {
            Button("Run council") {}.buttonStyle(.alPrimary)
            Button("Secondary") {}.buttonStyle(.alSecondary)
            Button("Ghost") {}.buttonStyle(.alGhost)
            Button("Stop") {}.buttonStyle(.alDanger)
        }

        VStack(spacing: 8) {
            WorkerChip(name: "Claude Code", model: "claude-opus-4-8", systemImage: "cpu",
                       status: .running, meta: "2.4s", selectable: true, selected: true)
            WorkerChip(name: "Codex", model: "gpt-5-codex", systemImage: "cpu",
                       status: .done, meta: "1.1s", selectable: true, selected: false)
            WorkerChip(name: "Grok", model: "grok-4", systemImage: "cpu", status: .failed)
        }

        Text("Master plan ready")
            .font(.alTitle).foregroundStyle(Color.alTextPrimary)
            .alCard(.accent)
    }
    .padding(24)
    .frame(width: 460)
    .background(Color.alBgBase)
}
